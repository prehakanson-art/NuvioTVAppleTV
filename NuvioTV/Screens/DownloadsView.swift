import SwiftUI

/// Offline downloads: play saved movies/episodes with no network, and manage
/// (pause / resume / delete) in-progress ones.
struct DownloadsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var downloads: DownloadManager

    /// Plays a completed download from its local file.
    let onPlay: (MetaItem, StreamEntry) -> Void

    var body: some View {
        DetailScaffold(title: "Downloads", subtitle: downloadsSubtitle) {
            StorageBar(info: downloads.storageInfo())

            if downloads.items.isEmpty {
                NuvioEmptyState(
                    icon: "arrow.down.circle",
                    title: "No downloads",
                    message: "Pick a source on any title and choose Download to save it here for offline viewing."
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVStack(spacing: NuvioSpacing.sm) {
                    ForEach(downloads.items) { item in
                        DownloadRow(item: item, onPlay: { play(item) })
                    }
                }
            }
        }
    }

    private var downloadsSubtitle: String {
        let done = downloads.items.filter { $0.status == .completed }.count
        let size = ByteCountFormatter.string(fromByteCount: downloads.totalBytesOnDisk, countStyle: .file)
        return done > 0 ? "\(done) saved · \(size) on disk" : "Saved for offline viewing"
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
        .padding(.bottom, NuvioSpacing.sm)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 16, height: 16)
            Text(text).font(.system(size: 17)).foregroundStyle(theme.palette.textSecondary)
        }
    }
}

private struct DownloadRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.isFocused) private var isFocused
    let item: DownloadedItem
    let onPlay: () -> Void

    var body: some View {
        Button(action: primaryAction) {
            HStack(spacing: NuvioSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(isFocused ? theme.palette.secondary : theme.palette.textTertiary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(1)
                    if item.status != .completed {
                        ProgressView(value: item.fraction)
                            .tint(theme.palette.secondary)
                            .frame(maxWidth: 420)
                    }
                    Text(statusLine)
                        .font(.system(size: 17))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, NuvioSpacing.lg)
            .frame(minHeight: 78)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.settingsRowRadius, style: .continuous)
                    .fill(isFocused ? theme.palette.focusBackground : theme.palette.backgroundCard.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.settingsRowRadius, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(PlainCardButtonStyle())
        .contextMenu {
            if item.status == .completed { Button { onPlay() } label: { Label("Play", systemImage: "play.fill") } }
            if item.status == .downloading { Button { downloads.pause(item.id) } label: { Label("Pause", systemImage: "pause.fill") } }
            if item.status == .paused || item.status == .failed { Button { downloads.resume(item.id) } label: { Label("Resume", systemImage: "arrow.clockwise") } }
            Button(role: .destructive) { downloads.delete(item.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func primaryAction() {
        switch item.status {
        case .completed: onPlay()
        case .downloading: downloads.pause(item.id)
        case .paused, .failed: downloads.resume(item.id)
        }
    }

    private var title: String {
        if let s = item.season, let e = item.episode {
            return "\(item.name) · S\(s):E\(e)"
        }
        return item.name
    }

    private var icon: String {
        switch item.status {
        case .completed: return "play.circle.fill"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private var statusLine: String {
        switch item.status {
        case .completed: return item.sizeLabel.map { "Saved · \($0)" } ?? "Saved"
        case .downloading: return "Downloading \(Int(item.fraction * 100))%\(item.sizeLabel.map { " of \($0)" } ?? "")"
        case .paused: return "Paused \(Int(item.fraction * 100))% — select to resume"
        case .failed: return "Failed — select to retry"
        }
    }
}
