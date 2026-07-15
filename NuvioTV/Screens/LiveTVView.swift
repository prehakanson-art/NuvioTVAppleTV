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

enum ChannelSort: String, CaseIterable, Identifiable {
    case defaultOrder = "Default"
    case nameAsc = "A → Z"
    case nameDesc = "Z → A"
    var id: String { rawValue }
}

struct LiveTVView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @StateObject private var viewModel = LiveTVViewModel()

    /// Push the channel into the shared streams flow (fetch → pick → play).
    let onSelectChannel: (MetaItem) -> Void

    @State private var searchText = ""
    @State private var sortMode: ChannelSort = .defaultOrder
    @State private var selectedGroup = ""   // "" = all groups

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            content
        }
        .task { await viewModel.loadIfNeeded(addonManager: addonManager) }
    }

    /// Any control that switches from the grouped rows to a flat, filtered grid.
    private var filtering: Bool {
        !searchText.isEmpty || sortMode != .defaultOrder || !selectedGroup.isEmpty
    }

    /// Channels for the flat view: pick the group, de-dup, search, then sort.
    private var displayChannels: [MetaItem] {
        var pool = selectedGroup.isEmpty
            ? viewModel.sections.flatMap(\.channels)
            : (viewModel.sections.first { $0.title == selectedGroup }?.channels ?? [])
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.id).inserted }
        if !searchText.isEmpty {
            pool = pool.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortMode {
        case .nameAsc:  pool.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc: pool.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .defaultOrder: break
        }
        return pool
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
                    controls
                    if filtering {
                        filteredGrid
                    } else {
                        ForEach(viewModel.sections) { section in
                            channelRow(section)
                        }
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

    /// Search field + sort + group filter.
    private var controls: some View {
        HStack(spacing: NuvioSpacing.lg) {
            HStack(spacing: NuvioSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.textSecondary)
                TextField("Search channels", text: $searchText)
                    .font(.system(size: 23))
            }
            .padding(.horizontal, NuvioSpacing.lg)
            .padding(.vertical, NuvioSpacing.md)
            .background(theme.palette.field, in: RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous))
            .frame(maxWidth: 560)

            NuvioDropdown(
                title: "Sort",
                selection: sortMode.rawValue,
                options: ChannelSort.allCases.map { NuvioDropdownOption($0.rawValue) },
                triggerWidth: 260
            ) { sortMode = ChannelSort(rawValue: $0) ?? .defaultOrder }

            if viewModel.sections.count > 1 {
                NuvioDropdown(
                    title: "Group",
                    selection: selectedGroup.isEmpty ? "All groups" : selectedGroup,
                    options: [NuvioDropdownOption("All groups")]
                        + viewModel.sections.map { NuvioDropdownOption($0.title) },
                    triggerWidth: 360
                ) { selectedGroup = ($0 == "All groups") ? "" : $0 }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NuvioSpacing.huge)
    }

    private var filteredGrid: some View {
        Group {
            if displayChannels.isEmpty {
                Text("No channels match “\(searchText)”.")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(.horizontal, NuvioSpacing.huge)
                    .padding(.top, NuvioSpacing.xl)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300, maximum: 300), spacing: NuvioSpacing.lg, alignment: .top)],
                    alignment: .leading,
                    spacing: NuvioSpacing.xl
                ) {
                    ForEach(displayChannels) { channel in
                        Button { onSelectChannel(channel) } label: {
                            ChannelCard(channel: channel)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        .onPlayPauseCommand { onSelectChannel(channel) }
                    }
                }
                .padding(.horizontal, NuvioSpacing.huge)
            }
        }
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
