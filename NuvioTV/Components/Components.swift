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

    /// Dedicated download session for artwork. Posters/backdrops nearly all come
    /// from one host (image.tmdb.org), so the default 6-connections-per-host cap
    /// throttles a full poster grid to 6 at a time — raise it so the grid fills
    /// in far fewer round-trips. Own URLCache keeps HTTP-cached art off the
    /// shared session.
    static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 12
        config.timeoutIntervalForRequest = 25
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 128 << 20)
        return URLSession(configuration: config)
    }()

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
        // Under real memory pressure, decoded pixels are the cheapest thing to
        // give back (they re-decode from disk on demand) — dropping them here
        // is what keeps tvOS from jetsamming the whole app instead.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.memory.removeAllObjects() }
    }

    /// Decode `data` off the render path, downsampled (via ImageIO) to
    /// `budget` pixels on the longest side when the source is larger.
    ///
    /// Callers that know their rendered size pass a tight budget (a poster
    /// card never needs a 2000×3000 "original" — decoding it full-size costs
    /// ~24 MB where ~3 MB carries the identical rendered pixels). With no
    /// budget the device framebuffer cap applies (1920 on the 1080p HD, 3840
    /// on 4K devices) — beyond the framebuffer there is nothing more to show,
    /// so every path stays pixel-identical.
    static func decodeDownsampled(_ data: Data, budget: CGFloat? = nil) -> UIImage? {
        let maxDim = min(budget ?? .greatestFiniteMagnitude,
                         PerformanceProfile.maxImagePixelSize)
        guard let src = CGImageSourceCreateWithData(data as CFData,
                        [kCGImageSourceShouldCache: false] as CFDictionary) else {
            // Fallback: force the decode now so it doesn't happen lazily on
            // the render path while a row scrolls.
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
    /// (under `memoryKey`, which carries the decode-budget bucket) and its
    /// file's mtime is touched so it survives LRU trimming. Disk always stores
    /// the original encoded bytes keyed by URL — one file serves every size.
    func diskImage(for key: String, budget: CGFloat? = nil, memoryKey: String? = nil) async -> UIImage? {
        let fileURL = fileURL(for: key)
        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                guard let self,
                      let data = try? Data(contentsOf: fileURL),
                      // Decode HERE (background, downsampled) — otherwise UIKit
                      // decodes lazily on first draw, i.e. on the render path
                      // while a row is scrolling.
                      let prepared = Self.decodeDownsampled(data, budget: budget) else {
                    continuation.resume(returning: nil)
                    return
                }
                self.insertMemory(prepared, for: memoryKey ?? key)
                try? self.fm.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
                continuation.resume(returning: prepared)
            }
        }
    }

    /// Store in memory now and persist the encoded bytes to disk in the
    /// background. Pass the original downloaded `data` to avoid re-encoding.
    /// `memoryKey` (when given) carries the decode-budget bucket; disk is
    /// always keyed by the plain URL.
    func insert(_ image: UIImage, for key: String, data: Data? = nil, memoryKey: String? = nil) {
        insertMemory(image, for: memoryKey ?? key)
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
                guard let (data, _) = try? await ImageCache.downloadSession.data(from: url),
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
    /// Longest rendered side in POINTS, when the caller knows it (poster and
    /// episode cards do). Decoding is capped at 1.5× this size in pixels —
    /// still supersampled relative to what's drawn, so the rendered output is
    /// identical, but a grid of cards stops decoding full "original" TMDB art
    /// it can never show. `nil` (heroes/backdrops) = device framebuffer cap.
    var maxDimension: CGFloat? = nil

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

    /// Pixel budget for the decode (longest side), from the rendered size.
    private var pixelBudget: CGFloat? {
        maxDimension.map { $0 * UIScreen.main.scale * 1.5 }
    }

    /// Memory-cache key: the URL plus the budget bucket, so a small card decode
    /// is never handed to a full-screen consumer of the same URL (and vice
    /// versa). Disk stays keyed by plain URL — encoded bytes fit every size.
    private func memoryKey(_ value: String) -> String {
        pixelBudget.map { "\(value)#\(Int($0))" } ?? value
    }

    /// Commit a loaded image, fading only when "Artwork fade-in" is on
    /// (Settings → Performance) — each fade re-renders the cell for its
    /// duration, which adds up during a fast row scroll on older boxes.
    private func show(_ newImage: UIImage?, key: String?, duration: Double) {
        if PerformanceSettingsStore.shared.settings.artworkFadeIn {
            withAnimation(.easeOut(duration: duration)) { image = newImage; shownKey = key }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { image = newImage; shownKey = key }
        }
    }

    private func load(_ value: String?) async {
        guard let value, let parsed = URL(string: value) else {
            show(nil, key: nil, duration: 0.2)
            return
        }
        if value == shownKey { return }
        if let cached = ImageCache.shared.image(for: memoryKey(value)) {
            show(cached, key: value, duration: 0.28)
            return
        }
        // Disk hit: survives relaunch, so a previously seen poster shows without
        // a network round-trip.
        if let disk = await ImageCache.shared.diskImage(
            for: value, budget: pixelBudget, memoryKey: memoryKey(value)
        ) {
            if Task.isCancelled { return }
            show(disk, key: value, duration: 0.28)
            return
        }
        // Keep the current image visible while the replacement downloads.
        guard let (data, _) = try? await ImageCache.downloadSession.data(from: parsed),
              !Task.isCancelled else { return }
        // Decode off the render path (UIKit otherwise decodes lazily on first
        // draw — a scroll hitch per newly visible poster), downsampled to this
        // view's own pixel budget (a poster card must not decode a full-res
        // backdrop-sized original).
        let budget = pixelBudget
        guard let prepared = await Task.detached(priority: .userInitiated, operation: {
            ImageCache.decodeDownsampled(data, budget: budget)
        }).value else { return }
        if Task.isCancelled { return }
        ImageCache.shared.insert(prepared, for: value, data: data, memoryKey: memoryKey(value))
        show(prepared, key: value, duration: 0.35)
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

// MARK: - Marquee title

/// Focus-marquee for long titles (the Android app's default): while `active`
/// (card focused) an overflowing title scrolls horizontally in a seamless
/// loop; inactive (or fitting) it renders as a plain truncated Text. The
/// measuring/animating variant exists ONLY on the focused card, so grids pay
/// zero extra cost — critical after the row-perf work.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let active: Bool

    var body: some View {
        if active {
            ActiveMarquee(text: text, font: font, color: color)
        } else {
            Text(text).font(font).foregroundStyle(color).lineLimit(1)
        }
    }
}

private struct ActiveMarquee: View {
    let text: String
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    /// Gap between the looping copies, and scroll speed in pt/s.
    private let gap: CGFloat = 60
    private let speed: CGFloat = 55

    private var overflows: Bool { textWidth > boxWidth + 1 }

    var body: some View {
        HStack(spacing: gap) {
            measuredText
            if overflows {
                // Second copy so the loop wraps seamlessly instead of
                // snapping back to the start.
                Text(text).font(font).foregroundStyle(color).fixedSize()
            }
        }
        .offset(x: offset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { boxWidth = geo.size.width }
            }
        )
        .onChange(of: textWidth) { _, _ in startIfNeeded() }
        .onChange(of: boxWidth) { _, _ in startIfNeeded() }
    }

    private var measuredText: some View {
        Text(text).font(font).foregroundStyle(color)
            .fixedSize()   // natural width, so overflow is measurable
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { textWidth = geo.size.width }
                }
            )
    }

    private func startIfNeeded() {
        guard overflows, offset == 0 else { return }
        let distance = textWidth + gap
        // Brief hold so the title is readable before it starts moving.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard overflows, offset == 0 else { return }
            withAnimation(.linear(duration: distance / speed)
                .delay(0.4)
                .repeatForever(autoreverses: false)) {
                offset = -distance
            }
        }
    }
}

// MARK: - Poster card

struct PosterCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var watched: WatchedStore
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var layout: HomeCatalogSettingsStore
    @ObservedObject private var perf = PerformanceSettingsStore.shared
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
                RemoteImage(url: item.poster, maxDimension: cardHeight)
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
            // FOCUSED card only. A drop shadow is an offscreen render pass per
            // card; with the old always-on ambient shadow every visible poster
            // paid one, which is a large share of the scroll cost on the
            // A8/A10X boxes. One shadow (the focused pop) keeps the depth cue.
            .shadow(color: .black.opacity(perf.settings.cardShadows && isFocused ? 0.65 : 0),
                    radius: perf.settings.cardShadows && isFocused ? 22 : 0, y: 10)

            if layout.showPosterLabels {
                MarqueeText(
                    text: item.name,
                    font: .system(size: 22, weight: .medium),
                    color: isFocused ? theme.palette.textPrimary : theme.palette.textSecondary,
                    active: isFocused
                )
                .frame(width: cardWidth, alignment: .leading)
            }
        }
        .scaleEffect(perf.settings.focusZoom && isFocused ? 1.08 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
    }
}

struct ProgressStrip: View {
    @EnvironmentObject private var theme: ThemeManager
    let fraction: Double

    var body: some View {
        // No GeometryReader: a full-width fill Capsule scaled horizontally to
        // the fraction. Every Continue Watching card carries one of these, and
        // GeometryReader forces each into its own layout pass — measurable
        // scroll cost across a row of them. scaleEffect is a cheap transform.
        Capsule().fill(Color.white.opacity(0.35))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(theme.palette.secondary)
                    .scaleEffect(x: CGFloat(min(max(fraction, 0.02), 1)), y: 1, anchor: .leading)
            }
            .frame(height: 6)
    }
}

/// Landscape card used for Continue Watching and episode thumbnails.
struct LandscapeCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var perf = PerformanceSettingsStore.shared
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
                RemoteImage(url: imageURL, maxDimension: width)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    // Attach `.blur` ONLY on the rare spoiler card. Applied
                    // unconditionally (even at radius 0) it forces every card
                    // into an offscreen render pass that the focus scale
                    // animation re-composites each frame — that, not the row
                    // re-render, is why Continue Watching scrolled heavier
                    // than the poster rows. `blurImage` is fixed per card, so
                    // the branch never flips on focus.
                    .modifier(SpoilerBlur(active: blurImage, revealed: isFocused))
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
            // Focused card only — same offscreen-pass reasoning as PosterCard.
            .shadow(color: .black.opacity(perf.settings.cardShadows && isFocused ? 0.65 : 0),
                    radius: perf.settings.cardShadows && isFocused ? 22 : 0, y: 10)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: title,
                    font: .system(size: 22, weight: .medium),
                    color: isFocused ? theme.palette.textPrimary : theme.palette.textSecondary,
                    active: isFocused
                )
                if let subtitle, !subtitle.isEmpty {
                    MarqueeText(
                        text: subtitle,
                        font: .system(size: 19),
                        color: theme.palette.textTertiary,
                        active: isFocused
                    )
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .scaleEffect(perf.settings.focusZoom && isFocused ? 1.06 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
    }
}

/// Spoiler blur that is entirely ABSENT when inactive — no radius-0 blur
/// layer, so an unblurred card has no offscreen render pass to re-composite
/// during its focus animation. `active` is fixed per card (never toggles on
/// focus), so this branch is identity-stable.
private struct SpoilerBlur: ViewModifier {
    let active: Bool
    let revealed: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if active {
            content
                .blur(radius: revealed ? 0 : 28)
                .animation(nil, value: revealed)   // snap, don't ride the spring
        } else {
            content
        }
    }
}

/// Borderless button wrapper so cards manage their own focus visuals.
struct PlainCardButtonStyle: ButtonStyle {
    /// Reports Select press begin/end so screens can pause state changes that
    /// would re-render mid-hold and break context-menu long presses.
    var onPressChanged: ((Bool) -> Void)? = nil

    func makeBody(configuration: Configuration) -> some View {
        let anims = PerformanceSettingsStore.shared.settings.buttonAnimations
        return configuration.label
            .scaleEffect(anims && configuration.isPressed ? 0.97 : 1)
            .animation(anims ? .easeOut(duration: 0.12) : nil, value: configuration.isPressed)
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
            // The white ring provides the contrast; no shadow — each shadow is
            // an offscreen pass, and one rides on EVERY watched card in a row.
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
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

/// A titled group (header + content) that separates a labelled grid/list, the
/// same Movies/Shows split the Search screen uses. Owns its horizontal padding
/// so the content lines up under the header, and is its own focus section so
/// up/down moves cleanly between groups.
struct LibrarySection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            RowHeader(title: title)
            content
                .padding(.horizontal, NuvioSpacing.huge)
        }
        .focusSection()
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
