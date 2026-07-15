import SwiftUI

/// Live TV / IPTV tab. Surfaces every `tv`-type catalog from the installed
/// addons (IPTV/live addons declare their channel lists as `type: "tv"`) and
/// plays a chosen channel through the normal source picker → player pipeline,
/// so a channel's direct m3u8/HLS stream just plays. No debrid, no Detail page.
@MainActor
final class LiveTVViewModel: ObservableObject {
    struct Section: Identifiable {
        let id: String
        let title: String
        let channels: [MetaItem]
    }

    @Published var sections: [Section] = []
    @Published var isLoading = false
    private var loaded = false

    func loadIfNeeded(addonManager: AddonManager) async {
        guard !loaded else { return }
        loaded = true
        await load(addonManager: addonManager)
    }

    func load(addonManager: AddonManager) async {
        isLoading = sections.isEmpty

        // Every plain (no required-extra) tv catalog across enabled addons.
        var requests: [(addon: InstalledAddon, catalog: ManifestCatalog)] = []
        for addon in addonManager.catalogAddons {
            for catalog in (addon.manifest.catalogs ?? [])
            where catalog.type == "tv" && !catalog.requiresExtra {
                requests.append((addon, catalog))
            }
        }
        guard !requests.isEmpty else {
            sections = []
            isLoading = false
            return
        }

        var built: [(Int, Section)] = []
        await withTaskGroup(of: (Int, Section?).self) { group in
            for (i, req) in requests.enumerated() {
                group.addTask {
                    let channels = (try? await StremioAPI.catalog(addon: req.addon, catalog: req.catalog)) ?? []
                    guard !channels.isEmpty else { return (i, nil) }
                    let title = req.catalog.name ?? req.catalog.id.capitalized
                    return (i, Section(id: "\(req.addon.id)|\(req.catalog.id)", title: title, channels: channels))
                }
            }
            for await (i, section) in group { if let section { built.append((i, section)) } }
        }
        sections = built.sorted { $0.0 < $1.0 }.map(\.1)
        isLoading = false
    }
}

struct LiveTVView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @StateObject private var viewModel = LiveTVViewModel()

    /// Push the channel into the shared streams flow (fetch → pick → play).
    let onSelectChannel: (MetaItem) -> Void

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            content
        }
        .task { await viewModel.loadIfNeeded(addonManager: addonManager) }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.sections.isEmpty {
            NuvioLoadingView(label: "Loading channels…")
        } else if viewModel.sections.isEmpty {
            NuvioEmptyState(
                icon: "tv",
                title: "No Live TV yet",
                message: "Install a Live TV or IPTV add-on (one that provides “tv” catalogs) from Settings → Add-ons, and its channels appear here."
            )
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: NuvioSpacing.xl) {
                    header
                    ForEach(viewModel.sections) { section in
                        channelRow(section)
                    }
                }
                .padding(.top, NuvioSpacing.xl)
                .padding(.bottom, NuvioSpacing.huge)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live TV")
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(theme.palette.textPrimary)
            Text("Channels from your installed add-ons")
                .font(.system(size: 21))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .padding(.leading, NuvioSpacing.huge)
    }

    private func channelRow(_ section: LiveTVViewModel.Section) -> some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            RowHeader(title: section.title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: NuvioSpacing.lg) {
                    ForEach(section.channels) { channel in
                        Button {
                            onSelectChannel(channel)
                        } label: {
                            ChannelCard(channel: channel)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        // ⏯ plays a channel too.
                        .onPlayPauseCommand { onSelectChannel(channel) }
                    }
                }
                .padding(.horizontal, NuvioSpacing.huge)
                .padding(.vertical, NuvioSpacing.lg)
            }
            .scrollClipDisabled()
        }
    }
}

/// A landscape channel tile — channel logo/poster on a dark plate with the name
/// underneath. Focus ring + optional zoom, matching the rest of the app.
private struct ChannelCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var perf = PerformanceSettingsStore.shared
    @Environment(\.isFocused) private var isFocused
    let channel: MetaItem

    private let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            ZStack {
                theme.palette.backgroundCard
                RemoteImage(
                    url: channel.logo ?? channel.poster ?? channel.background,
                    contentMode: .fit,
                    maxDimension: width
                )
                .padding(NuvioSpacing.md)
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(perf.settings.cardShadows && isFocused ? 0.65 : 0),
                    radius: perf.settings.cardShadows && isFocused ? 22 : 0, y: 10)

            MarqueeText(
                text: channel.name,
                font: .system(size: 22, weight: .medium),
                color: isFocused ? theme.palette.textPrimary : theme.palette.textSecondary,
                active: isFocused
            )
            .frame(width: width, alignment: .leading)
        }
        .scaleEffect(perf.focusZoomEffective && isFocused ? 1.06 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
    }
}
