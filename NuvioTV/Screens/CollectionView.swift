import SwiftUI

// MARK: - Home row (folder tiles)

/// A collection rendered as a home row of folder tiles, mirroring the Android
/// CollectionRowSection: each folder is a card showing its cover image (or
/// emoji fallback); selecting one opens the collection browser.
struct CollectionRowSection: View {
    @EnvironmentObject private var theme: ThemeManager

    let collection: NuvioCollection
    let title: String
    let onOpen: () -> Void
    /// Reports card focus gain/loss so Home can track which row holds focus
    /// (row auto-hide).
    var onCardFocus: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            RowHeader(title: title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: NuvioSpacing.lg) {
                    ForEach(collection.folders) { folder in
                        Button(action: onOpen) {
                            CollectionFolderCard(folder: folder, glowEnabled: collection.focusGlowEnabled ?? true)
                                .onFocusChange { onCardFocus($0) }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                    if collection.folders.isEmpty {
                        Button(action: onOpen) {
                            CollectionFolderCard(folder: nil, fallbackTitle: collection.title,
                                                 glowEnabled: collection.focusGlowEnabled ?? true)
                                .onFocusChange { onCardFocus($0) }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                }
                .padding(.horizontal, NuvioSpacing.huge)
                .padding(.vertical, NuvioSpacing.lg)
            }
            .scrollClipDisabled()
        }
    }
}

/// ALL collections as a single headerless Home row — one tile per collection.
/// (On Home there's deliberately no row title; the reorder screen labels the
/// whole group "Collections".)
struct CollectionsRowSection: View {
    let collections: [NuvioCollection]
    let onOpen: (NuvioCollection) -> Void

    /// Collections flagged "pin to top" sort first, in their given order;
    /// everything else keeps the Home-layout order after them. Home already
    /// folds every collection into this one combined row, so a per-collection
    /// pin can't move it to its own row position — instead it wins its place
    /// within this shared tile strip.
    private var ordered: [NuvioCollection] {
        let pinned = collections.filter(\.pinToTop)
        guard !pinned.isEmpty else { return collections }
        let rest = collections.filter { !$0.pinToTop }
        return pinned + rest
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: NuvioSpacing.lg) {
                ForEach(ordered) { collection in
                    Button { onOpen(collection) } label: {
                        CollectionTileCard(collection: collection)
                    }
                    .buttonStyle(PlainCardButtonStyle())
                }
            }
            .padding(.horizontal, NuvioSpacing.huge)
            .padding(.vertical, NuvioSpacing.lg)
        }
        .scrollClipDisabled()
    }
}

/// A tile representing a whole collection (its first folder's cover/emoji plus
/// the collection title), used in the combined Home collections row.
struct CollectionTileCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var perf = PerformanceSettingsStore.shared
    @Environment(\.isFocused) private var isFocused
    let collection: NuvioCollection

    private var firstFolder: NuvioCollectionFolder? { collection.folders.first }
    private var cover: String? { firstFolder?.coverImageUrl }
    private var emoji: String? { firstFolder?.coverEmoji }

    /// Tile size follows the (editable) shape of the collection's first folder.
    private var cardSize: CGSize {
        switch firstFolder?.tileShape {
        case "POSTER": return CGSize(width: 220, height: 330)
        case "LANDSCAPE": return CGSize(width: 380, height: 214)
        default: return CGSize(width: 260, height: 260)   // SQUARE
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: NuvioRadius.md).fill(theme.palette.surface)
                if let cover, !cover.isEmpty {
                    // .fit keeps a logo intact; a full landscape picture still
                    // reads well centered on the branded surface.
                    RemoteImage(url: cover, contentMode: .fit)
                        .padding(NuvioSpacing.sm)
                        .clipShape(RoundedRectangle(cornerRadius: NuvioRadius.md))
                } else if let emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 84))
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(perf.settings.cardShadows && isFocused ? 0.65 : 0),
                    radius: perf.settings.cardShadows && isFocused ? 22 : 0, y: 10)
            // Collection-authored "focus glow" — a colored halo behind the tile,
            // distinct from the neutral drop shadow above. Off by default per
            // folder if the collection disabled it in the editor.
            .shadow(color: glowEnabled && isFocused ? theme.palette.focusRing.opacity(0.85) : .clear,
                    radius: glowEnabled && isFocused ? 28 : 0)

            Text(collection.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isFocused ? theme.palette.textPrimary : theme.palette.textSecondary)
                .lineLimit(1)
                .frame(width: cardSize.width, alignment: .leading)
        }
        .scaleEffect(perf.focusZoomEffective && isFocused ? 1.06 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
    }

    private var glowEnabled: Bool { collection.focusGlowEnabled ?? true }
}

struct CollectionFolderCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var perf = PerformanceSettingsStore.shared
    @Environment(\.isFocused) private var isFocused

    let folder: NuvioCollectionFolder?
    var fallbackTitle: String = ""
    var glowEnabled: Bool = true

    private var title: String { folder?.title ?? fallbackTitle }
    private var isPoster: Bool { folder?.tileShape == "POSTER" }
    private var isLandscape: Bool { folder?.tileShape == "LANDSCAPE" }

    private var cardSize: CGSize {
        if isPoster { return CGSize(width: 220, height: 330) }
        if isLandscape { return CGSize(width: 360, height: 200) }
        return CGSize(width: 260, height: 260)   // SQUARE default
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: NuvioRadius.md)
                    .fill(theme.palette.surface)
                if let cover = folder?.coverImageUrl, !cover.isEmpty {
                    RemoteImage(url: cover, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: NuvioRadius.md))
                } else if let emoji = folder?.coverEmoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 84))
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(perf.settings.cardShadows && isFocused ? 0.65 : 0),
                    radius: perf.settings.cardShadows && isFocused ? 22 : 0, y: 10)
            .shadow(color: glowEnabled && isFocused ? theme.palette.focusRing.opacity(0.85) : .clear,
                    radius: glowEnabled && isFocused ? 28 : 0)

            if folder?.hideTitle != true && !title.isEmpty {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isFocused ? theme.palette.textPrimary : theme.palette.textSecondary)
                    .lineLimit(1)
                    .frame(width: cardSize.width, alignment: .leading)
            }
        }
        .scaleEffect(perf.focusZoomEffective && isFocused ? 1.06 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isFocused)
    }
}

// MARK: - Collection browser (tabbed grid)

/// Full collection browser: folder tabs across the top (with an "All" tab when
/// enabled) and a poster grid below — the APK's TABBED_GRID view mode.
struct CollectionView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var tmdbSettings: TMDBSettingsStore

    let collection: NuvioCollection
    let onSelect: (MetaItem) -> Void

    @State private var selectedFolderID: String?   // nil = All
    @State private var itemsByFolder: [String: [MetaItem]] = [:]
    @State private var isLoading = true
    @State private var hasUnsupportedSources = false

    private var visibleItems: [MetaItem] {
        if let selectedFolderID {
            return itemsByFolder[selectedFolderID] ?? []
        }
        // "All" preserves folder order and de-dupes across folders.
        var seen = Set<String>()
        return collection.folders.flatMap { itemsByFolder[$0.id] ?? [] }.filter { seen.insert($0.id).inserted }
    }

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: NuvioSpacing.lg)]

    /// The collection's background picture — explicit backdrop, else the first
    /// folder's cover (so it matches the tile).
    private var backdropURL: String? {
        if let b = collection.backdropImageUrl, !b.isEmpty { return b }
        if let c = collection.folders.first?.coverImageUrl, !c.isEmpty { return c }
        return nil
    }

    private var hasTabs: Bool { collection.folders.count > 1 || !collection.showAllTab }
    /// Height reserved for the pinned header (title + optional tabs) — the grid
    /// starts below it and posters slide up UNDER the scrim/header.
    private var headerInset: CGFloat { hasTabs ? 230 : 150 }

    var body: some View {
        ZStack(alignment: .top) {
            theme.palette.background.ignoresSafeArea()
            // Same HQ picture as the tile, used as the collection's background.
            if let backdrop = backdropURL {
                RemoteImage(url: backdrop, contentMode: .fill)
                    .ignoresSafeArea()
                    .opacity(0.3)
                    .overlay(theme.palette.background.opacity(0.35).ignoresSafeArea())
            }

            // Scrolling posters (full-bleed; content padded to clear the header).
            grid

            // The "grain bar": a background-toned scrim over the top that hides
            // posters as they scroll up under the header, matching the pinned
            // treatment elsewhere. Title/tabs draw ON TOP of it.
            LinearGradient(
                stops: [
                    .init(color: theme.palette.background, location: 0),
                    .init(color: theme.palette.background, location: 0.62),
                    .init(color: theme.palette.background.opacity(0), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: headerInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            // Pinned header — drawn last so it's in FRONT of the posters.
            VStack(alignment: .leading, spacing: NuvioSpacing.lg) {
                Text(collection.title)
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(.horizontal, NuvioSpacing.huge)
                folderTabs
            }
            .padding(.top, NuvioSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task { await loadAll() }
        .onAppear {
            if !collection.showAllTab {
                selectedFolderID = collection.folders.first?.id
            }
        }
    }

    @ViewBuilder
    private var grid: some View {
        if isLoading {
            NuvioLoadingView(label: "Loading collection")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleItems.isEmpty {
            NuvioEmptyState(
                icon: "rectangle.stack",
                title: "Nothing here yet",
                message: hasUnsupportedSources
                    ? "This folder uses TMDB sources — enable TMDB in Settings → Integrations to show them here."
                    : "This folder has no items. Add catalog sources to it in Settings → Collections."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: NuvioSpacing.xl) {
                    ForEach(visibleItems) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                }
                .padding(.horizontal, NuvioSpacing.huge)
                .padding(.top, headerInset)
                .padding(.bottom, NuvioSpacing.xxl)
            }
        }
    }

    @ViewBuilder
    private var folderTabs: some View {
        if collection.folders.count > 1 || !collection.showAllTab {
            ScrollView(.horizontal) {
                HStack(spacing: NuvioSpacing.md) {
                    if collection.showAllTab {
                        folderTab(id: nil, label: "All")
                    }
                    ForEach(collection.folders) { folder in
                        folderTab(id: folder.id, label: folder.title)
                    }
                }
                .padding(.horizontal, NuvioSpacing.huge)
                .padding(.vertical, NuvioSpacing.sm)
            }
            .scrollClipDisabled()
        }
    }

    private func folderTab(id: String?, label: String) -> some View {
        Button {
            selectedFolderID = id
        } label: {
            FolderTabPill(label: label, selected: selectedFolderID == id)
        }
        .buttonStyle(PlainCardButtonStyle())
    }

    private func loadAll() async {
        isLoading = true
        var unsupported = false
        var results: [String: [MetaItem]] = [:]
        let tmdbEnabled = tmdbSettings.isEnabled
        let tmdbLanguage = tmdbSettings.settings.language
        await withTaskGroup(of: (String, [MetaItem]).self) { group in
            for folder in collection.folders {
                // TMDB sources resolve only when the integration is enabled;
                // Trakt sources always resolve (public API, no toggle needed).
                let tmdbSources = folder.effectiveSources.filter { $0.provider.lowercased() == "tmdb" }
                let traktSources = folder.effectiveSources.filter { $0.isTraktSource }
                let otherUnsupported = folder.effectiveSources.filter {
                    !$0.isAddonSource && $0.provider.lowercased() != "tmdb" && !$0.isTraktSource
                }
                if !otherUnsupported.isEmpty || (!tmdbSources.isEmpty && !tmdbEnabled) {
                    unsupported = true
                }
                let addonSources = folder.addonSources
                let resolvableTmdb = tmdbEnabled ? tmdbSources : []
                guard !addonSources.isEmpty || !resolvableTmdb.isEmpty || !traktSources.isEmpty else { continue }
                let addons = addonManager.addons
                let manager = addonManager
                group.addTask {
                    var items: [MetaItem] = []
                    var seen = Set<String>()
                    for source in addonSources {
                        guard let addonID = source.addonId,
                              let type = source.type,
                              let catalogID = source.catalogId,
                              let addon = await Self.match(addons: addons, id: addonID),
                              let catalog = (addon.manifest.catalogs ?? [])
                                .first(where: { $0.type == type && $0.id == catalogID })
                        else { continue }
                        let fetched = (try? await StremioAPI.catalog(addon: addon, catalog: catalog)) ?? []
                        for item in fetched where seen.insert(item.id).inserted {
                            items.append(item)
                        }
                    }
                    for source in resolvableTmdb {
                        let fetched = await TMDBService.resolve(source: source, language: tmdbLanguage)
                        for item in fetched where seen.insert(item.id).inserted {
                            items.append(item)
                        }
                    }
                    for source in traktSources {
                        let fetched = await Self.resolveTrakt(source: source, addonManager: manager)
                        for item in fetched where seen.insert(item.id).inserted {
                            items.append(item)
                        }
                    }
                    return (folder.id, items)
                }
            }
            for await (folderID, items) in group {
                results[folderID] = items
            }
        }
        itemsByFolder = results
        hasUnsupportedSources = unsupported
        isLoading = false
    }

    /// Trakt list items arrive with no artwork — enrich the first N via the
    /// installed meta add-on (Cinemeta) so the grid still has posters; the
    /// rest still display (title only) rather than being dropped.
    private static func resolveTrakt(source: CollectionSourceDTO, addonManager: AddonManager) async -> [MetaItem] {
        guard let traktListId = source.traktListId else { return [] }
        let type = (source.mediaType ?? "movie").lowercased() == "tv" ? "show" : "movie"
        let sortBy = source.sortBy ?? "rank"
        let sortHow = source.sortHow ?? "asc"
        let raw = await TraktService.publicListItems(
            traktListId: traktListId, type: type, sortBy: sortBy, sortHow: sortHow
        )
        var enriched = 0
        var out: [MetaItem] = []
        for item in raw {
            let metaType = item.isMovie ? "movie" : "series"
            let id = item.imdb ?? item.tmdb.map { "tmdb:\($0)" }
            guard let id else { continue }
            if enriched < 30, let addon = await addonManager.metaAddon(for: metaType, id: id),
               let meta = try? await StremioAPI.meta(addon: addon, type: metaType, id: id) {
                enriched += 1
                out.append(meta)
            } else {
                out.append(MetaItem(
                    id: id, type: metaType, name: item.title,
                    releaseInfo: item.year.map(String.init)
                ))
            }
        }
        return out
    }

    /// Collections reference addons by manifest id (cross-platform stable),
    /// not by manifest URL.
    private static func match(addons: [InstalledAddon], id: String) async -> InstalledAddon? {
        addons.first { $0.manifest.id == id }
    }
}

/// Folder tab pill with the app's standard selected/focused treatment
/// (secondary fill when selected, focus ring + slight scale when focused).
private struct FolderTabPill: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let label: String
    let selected: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(selected ? theme.palette.onSecondary : theme.palette.textSecondary)
            .padding(.horizontal, NuvioSpacing.lg)
            .padding(.vertical, NuvioSpacing.sm)
            .background(
                Capsule().fill(selected ? theme.palette.secondary
                               : (isFocused ? theme.palette.focusBackground : Color.white.opacity(0.08)))
            )
            .overlay(Capsule().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3))
            .scaleEffect(isFocused ? 1.04 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }
}
