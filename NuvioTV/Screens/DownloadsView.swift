import SwiftUI

/// Storage bar + poster grids of downloaded titles (cover + info), separated
/// into Movies and Shows sections like the Search screen. Embedded directly in
/// the Library "Downloads" tab.
struct DownloadsContent: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var layout: HomeCatalogSettingsStore

    /// Plays a completed download from its local file.
    let onPlay: (MetaItem, StreamEntry) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: layout.posterSize.posterWidth,
                            maximum: layout.posterSize.posterWidth),
                  spacing: NuvioSpacing.lg, alignment: .top)]
    }

    private func isShow(_ item: DownloadedItem) -> Bool {
        item.season != nil || item.type == "series" || item.type == "tv"
    }
    private var movieItems: [DownloadedItem] { downloads.items.filter { !isShow($0) } }
    private var showItems: [DownloadedItem] { downloads.items.filter(isShow) }

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.xl) {
            StorageBar(info: downloads.storageInfo())
                .padding(.horizontal, NuvioSpacing.huge)

            if downloads.items.isEmpty {
                NuvioEmptyState(
                    icon: "arrow.down.circle",
                    title: "No downloads",
                    message: "Pick a source on any title and choose Download to save it here for offline viewing."
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                if !movieItems.isEmpty {
                    LibrarySection(title: "Movies") { grid(movieItems) }
                }
                if !showItems.isEmpty {
                    LibrarySection(title: "Shows") { grid(showItems) }
                }
            }
        }
    }

    private func grid(_ items: [DownloadedItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: NuvioSpacing.xl) {
            ForEach(items) { item in
                Button { primaryAction(item) } label: {
                    DownloadCardLabel(item: item)
                }
                .buttonStyle(PlainCardButtonStyle())
                .contextMenu {
                    if item.status == .completed {
                        Button { play(item) } label: { Label("Play", systemImage: "play.fill") }
                    }
                    if item.status == .downloading {
                        Button { downloads.pause(item.id) } label: { Label("Pause", systemImage: "pause.fill") }
                    }
                    if item.status == .paused || item.status == .failed {
                        Button { downloads.resume(item.id) } label: { Label("Resume", systemImage: "arrow.clockwise") }
                    }
                    Button(role: .destructive) { downloads.delete(item.id) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    private func primaryAction(_ item: DownloadedItem) {
        switch item.status {
        case .completed: play(item)
        case .downloading: downloads.pause(item.id)
        case .paused, .failed: downloads.resume(item.id)
        }
    }

    private func play(_ item: DownloadedItem) {
        guard let url = downloads.localURL(metaID: item.metaID, season: item.season, episode: item.episode) else { return }
        let meta = MetaItem(id: item.metaID, type: item.type, name: item.name,
                            poster: item.poster, background: item.background, logo: item.logo)
        let stream = Stream(name: item.name, title: item.episodeTitle ?? item.name,
                            description: item.sizeLabel, url: url.absoluteString,
                            infoHash: nil, behaviorHints: nil)
        onPlay(meta, StreamEntry(addonName: "Downloaded", stream: stream))
    }
}

/// Poster card for one download: cover art with a status overlay for anything
/// not finished, plus title/status underneath. Reads `isFocused` here (as the
/// button's label) so it lights up on focus like the rest of the poster grid.
private struct DownloadCardLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var layout: HomeCatalogSettingsStore
    @Environment(\.isFocused) private var isFocused
    let item: DownloadedItem

    private var cardWidth: CGFloat { layout.posterSize.posterWidth }
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }
    private var cornerRadius: CGFloat { CGFloat(layout.posterCornerRadius) }

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            ZStack {
                RemoteImage(url: item.poster, maxDimension: cardHeight)
                    .aspectRatio(2 / 3, contentMode: .fill)

                if item.status != .completed {
                    Rectangle().fill(Color.black.opacity(0.5))
                    VStack(spacing: 10) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 46))
                            .foregroundStyle(.white)
                        if item.status == .downloading || item.status == .paused {
                            ProgressStrip(fraction: item.fraction)
                                .frame(width: cardWidth * 0.66)
                        }
                    }
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(theme.palette.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if item.status == .completed {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(theme.palette.secondary)
                        .padding(10)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(isFocused ? 0.7 : 0.35), radius: isFocused ? 24 : 10, y: 10)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: title,
                    font: .system(size: 22, weight: .medium),
                    color: isFocused ? theme.palette.textPrimary : theme.palette.textSecondary,
                    active: isFocused
                )
                Text(statusLine)
                    .font(.system(size: 18))
                    .foregroundStyle(theme.palette.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
    }

    private var title: String {
        if let s = item.season, let e = item.episode { return "\(item.name) · S\(s):E\(e)" }
        return item.name
    }

    private var statusIcon: String {
        switch item.status {
        case .completed: return "play.circle.fill"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private var statusLine: String {
        switch item.status {
        case .completed: return item.sizeLabel.map { "Saved · \($0)" } ?? "Saved offline"
        case .downloading: return "Downloading \(Int(item.fraction * 100))%\(item.sizeLabel.map { " of \($0)" } ?? "")"
        case .paused: return "Paused \(Int(item.fraction * 100))% — select to resume"
        case .failed: return "Failed — select to retry"
        }
    }
}

/// Apple TV storage overview: a segmented bar (other apps' usage + this app's
/// downloads + free) with total/free labels, so you can see what's available.
private struct StorageBar: View {
    @EnvironmentObject private var theme: ThemeManager
    let info: DownloadManager.StorageInfo

    private func label(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            HStack {
                Text("Apple TV storage")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                Spacer()
                Text("\(label(info.available)) free of \(label(info.total))")
                    .font(.system(size: 19))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            GeometryReader { geo in
                let w = geo.size.width
                // Other usage = everything used that ISN'T our downloads.
                let otherFrac = max(0, info.usedFraction - info.downloadsFraction)
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.palette.backgroundCard)              // free track
                    HStack(spacing: 0) {
                        Rectangle().fill(theme.palette.textTertiary.opacity(0.6))   // other apps/system
                            .frame(width: w * otherFrac)
                        Rectangle().fill(theme.palette.secondary)                   // this app's downloads
                            .frame(width: w * info.downloadsFraction)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 16)

            HStack(spacing: NuvioSpacing.lg) {
                legend(color: theme.palette.textTertiary.opacity(0.6), text: "Other · \(label(info.used - info.usedByDownloads))")
                legend(color: theme.palette.secondary, text: "Downloads · \(label(info.usedByDownloads))")
            }
            Text("tvOS may remove downloads if the Apple TV runs low on storage.")
                .font(.system(size: 15))
                .foregroundStyle(theme.palette.textTertiary)
        }
        .padding(NuvioSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: NuvioRadius.lg, style: .continuous)
                .fill(theme.palette.background.opacity(0.55))
        )
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 16, height: 16)
            Text(text).font(.system(size: 17)).foregroundStyle(theme.palette.textSecondary)
        }
    }
}
