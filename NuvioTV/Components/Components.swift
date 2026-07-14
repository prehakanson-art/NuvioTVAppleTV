import SwiftUI
import UIKit
import CryptoKit
import ImageIO

// MARK: - Image cache

/// Process-wide image cache with two layers:
///
/// * **Memory** (`NSCache`) — decoded pixels, instant re-show. `AsyncImage`
///   re-downloads and re-decodes every time its view is recreated (which the
///   home hero does on every focus move) — that was the backdrop flicker.
/// * **Disk** (`Caches/nuvio-images`) — the original encoded bytes, so posters
///   and backdrops survive an app relaunch and don't have to be refetched.
///   LRU-trimmed to a byte budget on launch.
///
/// Memory lookups are synchronous; disk lookups are async (off the main
/// thread) and promote hits back into the memory layer.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let memory = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "nuvio.imagecache.io", qos: .utility)
    private let fm = FileManager.default
    private let diskURL: URL
    private let diskBudget = 512 * 1024 * 1024   // ~512 MB of encoded images

    private init() {
        // Sized to the hardware: the Apple TV HD has 2 GB total — a 256 MB
        // decoded-pixel cache there gets the app jetsammed.
        memory.countLimit = PerformanceProfile.imageCacheCount
        memory.totalCostLimit = PerformanceProfile.imageCacheBytes
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskURL = caches.appendingPathComponent("nuvio-images", isDirectory: true)
        try? fm.createDirectory(at: diskURL, withIntermediateDirectories: true)
        ioQueue.async { [weak self] in self?.trimDisk() }
    }

    /// Decode `data` off the render path. On the 1080p Apple TV HD it's
    /// downsampled (via ImageIO) to the panel's own resolution — pixel-identical
    /// on that display but a fraction of the memory of a full 4K-ish TMDB
    /// "original". On 4K devices `maxImagePixelSize` is nil, so this is a plain
    /// full-resolution decode — unchanged from before.
    static func decodeDownsampled(_ data: Data) -> UIImage? {
        // Full-res path (nil budget) or fallback: force the decode now so it
        // doesn't happen lazily on the render path while a row scrolls.
        guard let maxDim = PerformanceProfile.maxImagePixelSize,
              let src = CGImageSourceCreateWithData(data as CFData,
                        [kCGImageSourceShouldCache: false] as CFDictionary) else {
            let decoded = UIImage(data: data)
            return decoded?.preparingForDisplay() ?? decoded
        }
        // Source already within the display's budget — plain decode.
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
           max(w, h) <= maxDim {
            let decoded = UIImage(data: data)
            return decoded?.preparingForDisplay() ?? decoded
        }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,   // decode now, off-main
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else {
            let decoded = UIImage(data: data)
            return decoded?.preparingForDisplay() ?? decoded
        }
        return UIImage(cgImage: cg)
    }

    /// Synchronous memory-only lookup.
    func image(for key: String) -> UIImage? { memory.object(forKey: key as NSString) }

    /// Off-main disk lookup. On a hit the image is promoted back into memory
    /// and its file's mtime is touched so it survives LRU trimming.
    func diskImage(for key: String) async -> UIImage? {
        let fileURL = fileURL(for: key)
        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                guard let self,
                      let data = try? Data(contentsOf: fileURL),
                      // Decode HERE (background, downsampled) — otherwise UIKit
                      // decodes lazily on first draw, i.e. on the render path
                      // while a row is scrolling.
                      let prepared = Self.decodeDownsampled(data) else {
                    continuation.resume(returning: nil)
                    return
                }
                self.insertMemory(prepared, for: key)
                try? self.fm.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
                continuation.resume(returning: prepared)
            }
        }
    }

    /// Store in memory now and persist the encoded bytes to disk in the
    /// background. Pass the original downloaded `data` to avoid re-encoding.
    func insert(_ image: UIImage, for key: String, data: Data? = nil) {
        insertMemory(image, for: key)
        let payload = data ?? image.jpegData(compressionQuality: 0.9)
        guard let payload else { return }
        let fileURL = fileURL(for: key)
        ioQueue.async { try? payload.write(to: fileURL, options: .atomic) }
    }

    private func insertMemory(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return diskURL.appendingPathComponent(name)
    }

    /// Warm the cache for images that will be needed soon (posters in rows
    /// below the fold). Downloads straight into the disk layer at utility
    /// priority; anything already in memory or on disk is skipped.
    func prefetch(urls: [String]) {
        Task.detached(priority: .utility) { [weak self] in
            for urlString in urls {
                guard let self, let url = URL(string: urlString) else { continue }
                if self.image(for: urlString) != nil { continue }
                if FileManager.default.fileExists(atPath: self.fileURL(for: urlString).path) { continue }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      // Pre-decode (downsampled) so the first display is free.
                      let prepared = ImageCache.decodeDownsampled(data) else { continue }
                self.insert(prepared, for: urlString, data: data)
            }
        }
    }

    /// Evict oldest files (by mtime) until the directory is under budget.
    private func trimDisk() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let contents = try? fm.contentsOfDirectory(
            at: diskURL, includingPropertiesForKeys: keys
        ) else { return }
        var files = contents.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { return nil }
            return (url, size, date)
        }
        var total = files.reduce(0) { $0 + $1.size }
        guard total > diskBudget else { return }
        files.sort { $0.date < $1.date }   // oldest first
        for file in files {
            if total <= diskBudget { break }
            try? fm.removeItem(at: file.url)
            total -= file.size
        }
    }
}

// MARK: - Remote image

/// Cached async image with a shimmer placeholder and a crossfade-in. Keeps the
/// previously shown image on screen while a new URL loads, so changing the hero
/// backdrop is a smooth crossfade rather than a flash.
struct RemoteImage: View {
    let url: String?
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center

    @State private var image: UIImage?
    @State private var shownKey: String?

    var body: some View {
        Color.clear.overlay(alignment: alignment) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .id(shownKey)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .clipped()
        .task(id: url) { await load(url) }
    }

    private func load(_ value: String?) async {
        guard let value, let parsed = URL(string: value) else {
            withAnimation(.easeOut(duration: 0.2)) { image = nil; shownKey = nil }
            return
        }
        if value == shownKey { return }
        if let cached = ImageCache.shared.image(for: value) {
            withAnimation(.easeOut(duration: 0.28)) { image = cached; shownKey = value }
            return
        }
        // Disk hit: survives relaunch, so a previously seen poster shows without
        // a network round-trip.
        if let disk = await ImageCache.shared.diskImage(for: value) {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.28)) { image = disk; shownKey = value }
            return
        }
        // Keep the current image visible while the replacement downloads.
        guard let (data, _) = try? await URLSession.shared.data(from: parsed),
              !Task.isCancelled else { return }
        // Decode off the render path (UIKit otherwise decodes lazily on first
        // draw — a scroll hitch per newly visible poster), downsampled to the
        // device's pixel budget (a full 3840px backdrop decode wrecks the HD).
        guard let prepared = await Task.detached(priority: .userInitiated, operation: {
            ImageCache.decodeDownsampled(data)
        }).value else { return }
        if Task.isCancelled { return }
        ImageCache.shared.insert(prepared, for: value, data: data)
        withAnimation(.easeInOut(duration: 0.35)) { image = prepared; shownKey = value }
    }

    private var placeholder: some View {
        PlaceholderShimmer()
    }
}

/// Dimmed placeholder shown while an image downloads. Deliberately STATIC:
/// the earlier breathing animation started a repeat-forever animation in
/// every freshly created cell — during a fast row scroll that's dozens of
/// simultaneous animations spinning up, which visibly stuttered scrolling on
/// the A10X.
private struct PlaceholderShimmer: View {
    var body: some View {
        NuvioPrimitives.neutral875
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 30))
                    .foregroundStyle(NuvioPrimitives.neutral700)
            )
            .opacity(0.7)
    }
}

// MARK: - Poster card

struct PosterCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var watched: WatchedStore
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var layout: HomeCatalogSettingsStore
    @Environment(\.isFocused) private var isFocused

    let item: MetaItem
    var progress: Double? = nil

    private var cardWidth: CGFloat { layout.posterSize.posterWidth }
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }
    private var cornerRadius: CGFloat { CGFloat(layout.posterCornerRadius) }

    /// Explicit progress wins; otherwise an O(1) Continue Watching lookup so
    /// a started movie/show carries its progress bar EVERYWHERE it appears
    /// (home rows, search, discover, library…), not just the CW row.
    private var effectiveProgress: Double? {
        if let progress { return progress }
        return progressStore.continueFractions[item.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: item.poster)
                    .aspectRatio(2 / 3, contentMode: .fill)
                if let progress = effectiveProgress, progress > 0 {
                    ProgressStrip(fraction: progress)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(theme.palette.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if watched.isWatched(item) { WatchedBadge().padding(10) }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(isFocused ? 0.7 : 0.35), radius: isFocused ? 24 : 10, y: 10)

            if layout.showPosterLabels {
                Text(item.name)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isFocused ? theme.palette.textPrimary : theme.palette.textSecondary)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
    }
}

struct ProgressStrip: View {
    @EnvironmentObject private var theme: ThemeManager
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.35))
                Capsule()
                    .fill(theme.palette.secondary)
                    .frame(width: max(geo.size.width * fraction, 6))
            }
        }
        .frame(height: 6)
    }
}

/// Landscape card used for Continue Watching and episode thumbnails.
struct LandscapeCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused

    let imageURL: String?
    let title: String
    let subtitle: String?
    var progress: Double? = nil
    var watched: Bool = false
    var rating: String? = nil
    var width: CGFloat = 380
    /// Spoiler-blur the still until the card is focused (then it reveals).
    var blurImage: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: imageURL)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .blur(radius: blurImage && !isFocused ? 28 : 0)
                if let progress, progress > 0 {
                    ProgressStrip(fraction: progress)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .background(theme.palette.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let rating { RatingBadge(rating: rating).padding(10) }
            }
            .overlay(alignment: .topTrailing) {
                if watched { WatchedBadge().padding(10) }
            }
            .overlay(
                RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(isFocused ? 0.7 : 0.35), radius: isFocused ? 24 : 10, y: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isFocused ? theme.palette.textPrimary : theme.palette.textSecondary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 19))
                        .foregroundStyle(theme.palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
    }
}

/// Borderless button wrapper so cards manage their own focus visuals.
struct PlainCardButtonStyle: ButtonStyle {
    /// Reports Select press begin/end so screens can pause state changes that
    /// would re-render mid-hold and break context-menu long presses.
    var onPressChanged: ((Bool) -> Void)? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressChanged?(pressed)
            }
    }
}

// MARK: - Badges & meta

/// A `•` separator dot for meta lines (APK style).
struct MetaDot: View {
    @EnvironmentObject private var theme: ThemeManager
    var body: some View {
        Text("•")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(theme.palette.textTertiary)
    }
}

/// A meta-line text segment styled like the APK's "Type • Genre • Year" line.
struct MetaDotText: View {
    @EnvironmentObject private var theme: ThemeManager
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(theme.palette.textSecondary)
    }
}

/// A dot-separated meta line ("A • B • C"), optionally ending with an IMDb badge.
/// Matches the APK's detail/home meta rows.
struct MetaLine: View {
    let segments: [String]
    var imdbRating: String? = nil

    var body: some View {
        HStack(spacing: NuvioSpacing.sm) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, seg in
                if index > 0 { MetaDot() }
                MetaDotText(seg)
            }
            if let imdbRating {
                if !segments.isEmpty { MetaDot() }
                ImdbBadge(rating: imdbRating)
            }
        }
    }
}

struct MetaBadge: View {
    let text: String
    var tint: Color = .white.opacity(0.14)
    var textColor: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Small "watched" checkmark chip shown on poster/landscape cards.
struct WatchedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(.white)
            .padding(9)
            .background(Circle().fill(NuvioPrimitives.success))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }
}

/// Small star-rating chip (e.g. "★ 8.4") shown on episode cards.
struct RatingBadge: View {
    let rating: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NuvioPrimitives.imdb)
            Text(rating)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.65), in: Capsule())
    }
}

/// A row of MDBList source ratings (IMDb, TMDB, RT, Metacritic, …), each a
/// small labeled chip. Mirrors the Android hero `MDBListRatingsRow`.
struct MDBListRatingsRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let entries: [MDBListRatingEntry]

    var body: some View {
        HStack(spacing: NuvioSpacing.md) {
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Text(entry.provider.label)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(theme.palette.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.palette.secondary.opacity(0.22),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(entry.text)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
        }
    }
}

struct ImdbBadge: View {
    let rating: String

    var body: some View {
        HStack(spacing: 7) {
            Text("IMDb")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(NuvioPrimitives.imdb, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(rating)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Section header

struct RowHeader: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(theme.palette.textPrimary)
            .padding(.leading, NuvioSpacing.huge)
    }
}

// MARK: - Hero gradients (ported from Nuvio's ModernHeroGradientLayer)

struct HeroGradient: View {
    let background: Color
    var fullBleed: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: background, location: 0),
                    .init(color: background.opacity(0.86), location: 0.22),
                    .init(color: background.opacity(0.56), location: 0.46),
                    .init(color: background.opacity(0.16), location: 0.76),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: UnitPoint(x: fullBleed ? 0.65 : 0.45, y: 0.5)
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: background.opacity(0.25), location: 0.4),
                    .init(color: background.opacity(0.65), location: 0.75),
                    .init(color: background, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Loading / error states

struct NuvioLoadingView: View {
    @EnvironmentObject private var theme: ThemeManager
    var label: String = "Loading"

    var body: some View {
        VStack(spacing: NuvioSpacing.lg) {
            ProgressView()
                .tint(theme.palette.secondary)
                .scaleEffect(1.4)
            Text(label)
                .font(.system(size: 24))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NuvioEmptyState: View {
    @EnvironmentObject private var theme: ThemeManager
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: NuvioSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(theme.palette.textTertiary)
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.palette.textPrimary)
            Text(message)
                .font(.system(size: 23))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Formatting helpers

enum DateFormat {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let plainDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let output: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .none; return f
    }()

    /// Localized long date ("5 July 2026") from an ISO date or a plain
    /// `yyyy-MM-dd`. Returns nil if unparseable/empty.
    static func releaseDate(_ isoDate: String?) -> String? {
        guard let isoDate, !isoDate.isEmpty else { return nil }
        let date = isoWithFraction.date(from: isoDate)
            ?? iso.date(from: isoDate)
            ?? plainDate.date(from: String(isoDate.prefix(10)))
        return date.map { output.string(from: $0) }
    }
}

enum TimeFormat {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    static func signedDelta(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "-" : "+"
        return sign + clock(abs(seconds))
    }
}
