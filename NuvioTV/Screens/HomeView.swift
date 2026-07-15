import SwiftUI

struct HomeRow: Identifiable {
    let id: String
    let title: String
    let items: [MetaItem]
    /// Source catalog, so the row can navigate to a paginated "See All".
    var addon: InstalledAddon?
    var catalog: ManifestCatalog?
}

/// A home screen row: either a catalog of posters or a collection of folders.
enum HomeEntry: Identifiable {
    case catalog(HomeRow)
    case collection(NuvioCollection)

    var id: String {
        switch self {
        case .catalog(let row): return row.id
        case .collection(let collection): return "collection|\(collection.id)"
        }
    }
}

/// Persists the last-rendered Home catalog rows (their items) to disk, keyed by
/// catalog key, so the screen paints instantly on a cold start and then
/// refreshes in the background (stale-while-revalidate).
enum HomeCatalogCache {
    private static let fileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("nuvio-home-catalogs.json")
    }()

    static func load() -> [String: [MetaItem]] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [MetaItem]].self, from: data) else { return [:] }
        return decoded
    }

    static func save(_ rows: [String: [MetaItem]]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var entries: [HomeEntry] = []
    @Published var isLoading = false
    /// Current phase label for the first-run stepped loading backdrop
    /// (nil when not doing a cold, cache-less load).
    @Published var loadingStep: String?
    @Published var loadError: String?
    /// The default billboard title (first catalog item with art), computed on
    /// load. The LIVE hero — which changes as focus moves — lives in a separate
    /// `HeroFocus` object so its frequent animated updates only re-render the
    /// billboard, NOT the poster rows. That full re-render was cancelling the
    /// first long-press on a card right after moving to it.
    var initialHero: MetaItem?

    private var loadedFingerprint: [String] = []

    func loadIfNeeded(
        addonManager: AddonManager,
        collections: CollectionsStore,
        settings: HomeCatalogSettingsStore
    ) async {
        // Fingerprint includes catalog counts (so rows refresh when the live
        // manifests replace the bundled seed) plus the layout customization
        // state and collection list, so edits re-render immediately.
        var fingerprint = addonManager.catalogAddons.map {
            "\($0.id)#\(($0.manifest.catalogs ?? []).count)"
        }
        fingerprint.append(settings.orderKeys.joined(separator: ","))
        fingerprint.append(settings.disabledKeys.sorted().joined(separator: ","))
        fingerprint.append(settings.customTitles.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","))
        fingerprint.append(collections.collections.map { "\($0.id)#\($0.folders.count)#\($0.title)" }.joined(separator: ","))
        guard entries.isEmpty || fingerprint != loadedFingerprint else { return }
        loadedFingerprint = fingerprint
        await load(addonManager: addonManager, collections: collections, settings: settings)
    }

    func load(
        addonManager: AddonManager,
        collections: CollectionsStore,
        settings: HomeCatalogSettingsStore
    ) async {
        isLoading = entries.isEmpty
        loadError = nil

        // Assemble the available rows keyed the same way the sync payload is,
        // then let the layout settings decide order and visibility.
        var catalogByKey: [String: (addon: InstalledAddon, catalog: ManifestCatalog)] = [:]
        var catalogKeys: [String] = []
        for addon in addonManager.catalogAddons {
            for catalog in (addon.manifest.catalogs ?? []).filter({ !$0.requiresExtra }).prefix(6) {
                let key = HomeCatalogSettingsStore.catalogKey(
                    addonID: addon.manifest.id, type: catalog.type, catalogID: catalog.id
                )
                guard catalogByKey[key] == nil else { continue }
                catalogKeys.append(key)
                catalogByKey[key] = (addon, catalog)
            }
        }
        var collectionByKey: [String: NuvioCollection] = [:]
        var collectionKeys: [String] = []
        for collection in collections.collections {
            let key = HomeCatalogSettingsStore.collectionKey(collection.id)
            collectionKeys.append(key)
            collectionByKey[key] = collection
        }

        let orderedKeys = settings
            .mergedOrder(catalogKeys: catalogKeys, collectionKeys: collectionKeys)
            .filter { settings.isEnabled(key: $0) }

        // STALE: on a cold start, paint the last-saved catalog items instantly
        // (paired with the live addon/catalog so "See All" still works), then
        // refresh below.
        if entries.isEmpty {
            let cached = HomeCatalogCache.load()
            var stale: [HomeEntry] = []
            for key in orderedKeys {
                if let collection = collectionByKey[key] {
                    stale.append(.collection(collection))
                } else if let request = catalogByKey[key], let items = cached[key], !items.isEmpty {
                    stale.append(.catalog(HomeRow(
                        id: Self.rowID(request),
                        title: Self.rowTitle(key: key, request: request, settings: settings),
                        items: items, addon: request.addon, catalog: request.catalog
                    )))
                }
            }
            if !stale.isEmpty {
                entries = stale
                if initialHero == nil { initialHero = Self.firstHero(stale) }
            }
        }

        // The stepped backdrop only shows when there's genuinely nothing on
        // screen (true first run). Warm starts render from cache instantly.
        isLoading = entries.isEmpty
        if isLoading {
            // No artificial pause — go straight to fetching so the first-run
            // load is as fast as the network allows.
            loadingStep = "Loading catalogs…"
        }

        // REVALIDATE: fetch every catalog in parallel.
        var fetched: [(index: Int, key: String?, entry: HomeEntry)] = []
        await withTaskGroup(of: (Int, String?, HomeEntry?).self) { group in
            for (index, key) in orderedKeys.enumerated() {
                if let collection = collectionByKey[key] {
                    fetched.append((index, nil, .collection(collection)))
                    continue
                }
                guard let request = catalogByKey[key] else { continue }
                let title = Self.rowTitle(key: key, request: request, settings: settings)
                let rowID = Self.rowID(request)
                group.addTask {
                    let items = (try? await StremioAPI.catalog(addon: request.addon, catalog: request.catalog)) ?? []
                    guard !items.isEmpty else { return (index, key, nil) }
                    let row = HomeRow(
                        id: rowID,
                        title: title,
                        items: Array(items.prefix(30)),
                        addon: request.addon,
                        catalog: request.catalog
                    )
                    return (index, key, .catalog(row))
                }
            }
            for await (index, key, entry) in group {
                if let entry { fetched.append((index, key, entry)) }
            }
        }

        if isLoading { loadingStep = "Loading artwork…" }

        let ordered = fetched.sorted { $0.index < $1.index }
        let freshEntries = ordered.map(\.entry)
        // Keep stale rows on screen if the refresh came back empty (offline).
        if !freshEntries.isEmpty { entries = freshEntries }

        // Persist fresh catalog items for the next cold start.
        var toCache: [String: [MetaItem]] = [:]
        for row in ordered {
            if let key = row.key, case .catalog(let r) = row.entry { toCache[key] = r.items }
        }
        if !toCache.isEmpty { HomeCatalogCache.save(toCache) }

        if initialHero == nil { initialHero = Self.firstHero(entries) }
        if entries.isEmpty {
            loadError = "No catalogs available. Check your addons and network connection."
        }
        isLoading = false
        loadingStep = nil

        // Warm the poster cache for the below-the-fold rows so scrolling down
        // hits disk, not the network. First rows render on their own.
        let prefetchURLs = entries.dropFirst(2).flatMap { entry -> [String] in
            guard case .catalog(let row) = entry else { return [] }
            return row.items.prefix(12).compactMap(\.poster)
        }
        if !prefetchURLs.isEmpty, PerformanceSettingsStore.shared.settings.artworkPrefetch {
            ImageCache.shared.prefetch(urls: Array(prefetchURLs))
        }
    }

    // MARK: Row builders (shared between the cache-paint and live-fetch paths)

    static func rowID(_ request: (addon: InstalledAddon, catalog: ManifestCatalog)) -> String {
        "\(request.addon.id)|\(request.catalog.type)|\(request.catalog.id)"
    }

    static func rowTitle(
        key: String,
        request: (addon: InstalledAddon, catalog: ManifestCatalog),
        settings: HomeCatalogSettingsStore
    ) -> String {
        // APK row header format: "{Catalog Name} - {Type}" (e.g. "Trending Movies - Movie").
        let typeLabel: String
        switch request.catalog.type {
        case "series", "tv": typeLabel = "Series"
        case "movie": typeLabel = "Movie"
        default: typeLabel = request.catalog.type.capitalized
        }
        let baseName = request.catalog.name ?? request.catalog.id.capitalized
        if let custom = settings.customTitle(for: key) { return custom }
        var title = baseName
        if settings.catalogAddonNameEnabled { title += " · \(request.addon.manifest.name)" }
        if settings.catalogTypeSuffixEnabled { title += " - \(typeLabel)" }
        return title
    }

    static func firstHero(_ entries: [HomeEntry]) -> MetaItem? {
        let firstCatalog = entries.lazy.compactMap { entry -> HomeRow? in
            if case .catalog(let row) = entry { return row }
            return nil
        }.first
        return firstCatalog?.items.first { $0.background != nil } ?? firstCatalog?.items.first
    }
}

/// The live billboard title, updated as focus moves across cards. Kept separate
/// from HomeViewModel and owned by HomeView WITHOUT observation, so its frequent
/// animated changes re-render only the billboard subviews — not the poster rows.
@MainActor
final class HeroFocus: ObservableObject {
    @Published var item: MetaItem?
    /// Fetches full metadata for a bare item (Continue Watching rows only
    /// store name + art) — set by HomeView. Successful results are cached.
    var enrich: ((MetaItem) async -> MetaItem?)?
    private var task: Task<Void, Never>?
    /// The id the debounce is ABOUT to commit. Guarding only against the
    /// COMMITTED item had a race: moving X→Y→X inside the debounce window
    /// passed the guard (item still X) without cancelling the pending Y, so Y
    /// landed while focus sat on X — the "wrong hero" flash.
    private var pendingID: String?
    private var enriched: [String: MetaItem] = [:]

    /// Debounced so fast scrolling through a row doesn't thrash the backdrop,
    /// animated for a smooth crossfade.
    func focus(_ newItem: MetaItem) {
        guard newItem.id != (pendingID ?? item?.id) else { return }
        task?.cancel()
        pendingID = newItem.id
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)   // let focus settle
            guard !Task.isCancelled else { return }
            let display = enriched[newItem.id] ?? newItem
            let fade = PerformanceSettingsStore.shared.heroCrossfadeEffective
            withAnimation(fade ? .easeInOut(duration: 0.4) : nil) { item = display }
            pendingID = nil
            // Bare item (no synopsis): fetch the full meta so the billboard
            // shows description/genres/rating, and swap it in if still current.
            guard display.description == nil, let enrich else { return }
            guard let full = await enrich(display), !Task.isCancelled,
                  self.item?.id == display.id else { return }
            enriched[display.id] = full
            withAnimation(fade ? .easeInOut(duration: 0.25) : nil) { self.item = full }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var collections: CollectionsStore
    @EnvironmentObject private var homeCatalogSettings: HomeCatalogSettingsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var watched: WatchedStore
    // Owned by RootView so it PERSISTS across tab switches. If it were a local
    // @StateObject, switching away and back would rebuild HomeView with a fresh
    // (empty) model → a "Loading catalogs" spinner with no focusable element →
    // focus falls back to the sidebar, which reopened the panel.
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject private var perf = PerformanceSettingsStore.shared

    let onSelect: (MetaItem) -> Void
    let onResume: (WatchProgress) -> Void
    var onResumeFromStart: (WatchProgress) -> Void = { _ in }
    /// Opens the source list (StreamsView) so the user picks a stream manually.
    var onPlayManually: (MetaItem, MetaVideo?) -> Void = { _, _ in }
    let onOpenCollection: (NuvioCollection) -> Void
    var onSeeAll: (InstalledAddon, ManifestCatalog, String) -> Void = { _, _, _ in }
    /// Fires when the first load attempt finishes (success or error), so the
    /// root can re-enable the sidebar only once content exists to hold focus.
    var onContentReady: () -> Void = {}

    private var layout: HomeLayout { homeCatalogSettings.homeLayout }

    /// The big title/logo/synopsis hero panel is a MODERN-only affordance.
    /// Classic keeps the focus-following backdrop but drops the panel (that's
    /// the whole point of Classic — a lighter, rows-first home), and Grid has
    /// no billboard at all.
    private var showsHeroPanel: Bool { layout == .modern }

    /// How far the row scroll starts below the top. Modern reserves room for the
    /// hero panel; Classic shows just a sliver of backdrop; Grid starts flush.
    private var rowsTopInset: CGFloat {
        switch layout {
        case .grid: return 0
        case .modern: return 130
        case .classic: return 60
        }
    }

    // Owned via @State (NOT @StateObject) so HomeView does NOT observe it —
    // hero changes must re-render only the billboard subviews, never the rows.
    @State private var hero = HeroFocus()

    var body: some View {
        ZStack(alignment: .top) {
            theme.palette.background.ignoresSafeArea()
            if layout != .grid && perf.settings.heroBackdrop { HeroBackdropView(hero: hero) }
            // The billboard (backdrop + info) is PINNED at the top; only the
            // rows scroll beneath it. That's what keeps the hero locked to the
            // focused title as you move through the 2nd, 3rd… rows (Netflix).
            VStack(alignment: .leading, spacing: 0) {
                if showsHeroPanel {
                    HeroInfoView(hero: hero)
                        .padding(.top, 56)
                        .padding(.leading, NuvioSpacing.huge)
                        // Rows scroll BEHIND the billboard (scrollClipDisabled
                        // lets them protrude above the scroll area), so the
                        // billboard must win the sibling draw order.
                        .zIndex(1)
                }
                rowsScroll
            }
        }
        .task {
            // Continue Watching rows only persist name/art — this fetches the
            // full meta (synopsis/genres/rating) for the billboard on demand.
            hero.enrich = { [weak addonManager] bare in
                guard let addonManager,
                      let addon = addonManager.metaAddon(for: bare.type, id: bare.id),
                      let full = try? await StremioAPI.meta(addon: addon, type: bare.type, id: bare.id)
                else { return nil }
                // Keep the art the progress row already had when the meta
                // addon returns none (hero backdrop must never go blank).
                return MetaItem(
                    id: full.id, type: full.type, name: full.name,
                    poster: full.poster ?? bare.poster,
                    background: full.background ?? bare.background,
                    logo: full.logo ?? bare.logo,
                    description: full.description, releaseInfo: full.releaseInfo,
                    imdbRating: full.imdbRating, runtime: full.runtime,
                    genres: full.genres, cast: full.cast, videos: full.videos
                )
            }
            await reload()
        }
        // Periodic catalog auto-refresh (Settings → Content & Discovery).
        // Restarts whenever the cadence changes; 0 = off. Uses the FORCED
        // load (not loadIfNeeded — the fingerprint wouldn't have changed) so
        // new releases appear without relaunching.
        .task(id: homeCatalogSettings.autoRefreshMinutes) {
            let minutes = homeCatalogSettings.autoRefreshMinutes
            guard minutes > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
                guard !Task.isCancelled else { return }
                await viewModel.load(
                    addonManager: addonManager,
                    collections: collections,
                    settings: homeCatalogSettings
                )
            }
        }
        .onChange(of: addonManager.addons) { _, _ in Task { await reload() } }
        .onChange(of: collections.collections) { _, _ in Task { await reload() } }
        .onChange(of: homeCatalogSettings.orderKeys) { _, _ in Task { await reload() } }
        .onChange(of: homeCatalogSettings.disabledKeys) { _, _ in Task { await reload() } }
        .onChange(of: homeCatalogSettings.customTitles) { _, _ in Task { await reload() } }
    }

    private func reload() async {
        await viewModel.loadIfNeeded(
            addonManager: addonManager,
            collections: collections,
            settings: homeCatalogSettings
        )
        if hero.item == nil { hero.item = viewModel.initialHero }
        onContentReady()
    }

    @ViewBuilder
    private var rowsContent: some View {
        if viewModel.isLoading && viewModel.entries.isEmpty {
            HomeLoadingBackdrop(step: viewModel.loadingStep)
                .frame(maxWidth: .infinity)
                .frame(height: 460)
        } else if let error = viewModel.loadError, viewModel.entries.isEmpty {
            VStack(spacing: NuvioSpacing.lg) {
                NuvioEmptyState(icon: "antenna.radiowaves.left.and.right.slash", title: "Nothing to show", message: error)
                Button {
                    Task { await reload() }
                } label: {
                    RetryLabel()
                }
                .buttonStyle(PlainCardButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 460)
        } else {
            rowsList
        }
    }

    private var rowsScroll: some View {
        ScrollView(.vertical) {
            // Grid stacks many tall poster grids; a LazyVStack keeps off-screen
            // catalogs from all rendering at once (the source of the grid lag).
            // Row layouts keep the eager VStack (its LazyHStack children stay
            // lazy) so vertical focus moves never wait on row creation.
            Group {
                if layout == .grid {
                    LazyVStack(alignment: .leading, spacing: NuvioSpacing.xl) { rowsContent }
                } else {
                    VStack(alignment: .leading, spacing: NuvioSpacing.xl) { rowsContent }
                }
            }
            .padding(.top, layout == .grid ? 40 : NuvioSpacing.md)
            .padding(.bottom, NuvioSpacing.huge)
        }
        // Vertically CLIPPED on purpose (no scrollClipDisabled): rows scrolled
        // up past the viewport are hard-cut below the billboard, so they can
        // never render over the background art. Scrolling is fully native —
        // the old scrollPosition pin (forcing the focused row to the top slot)
        // double-drove the scroll against the focus engine and made every row
        // change a whole-content jump; the focus engine alone is smooth.
        .padding(.top, rowsTopInset)
    }

    @ViewBuilder
    private var rowsList: some View {
        let continueItems = progressStore.continueWatching(sortMode: homeCatalogSettings.continueWatchingSortMode)
        if !continueItems.isEmpty {
            continueRow(continueItems)
        }

        ForEach(viewModel.entries) { entry in
            rowEntry(entry)
        }
    }

    @ViewBuilder
    private func rowEntry(_ entry: HomeEntry) -> some View {
        switch entry {
        case .catalog(let row):
            if layout == .grid {
                posterGrid(row)
            } else {
                horizontalRow(row)
            }
        case .collection(let collection):
            let key = HomeCatalogSettingsStore.collectionKey(collection.id)
            CollectionRowSection(
                collection: collection,
                title: homeCatalogSettings.customTitle(for: key) ?? collection.title,
                onOpen: { onOpenCollection(collection) }
            )
        }
    }

    private func continueRow(_ items: [WatchProgress]) -> some View {
        ContinueWatchingRow(
            items: items,
            hero: hero,
            // Grid renders no backdrop/billboard, so don't pay the per-focus
            // hero update (and its enrich fetch) where nothing displays it.
            drivesHero: layout != .grid,
            imageFor: continueImage,
            subtitleFor: continueSubtitle,
            blurFor: { [blur = homeCatalogSettings.blurContinueWatchingNextUp] progress in
                blur && progress.fraction < 0.02
            },
            heroItemFor: heroItem(from:),
            onResume: onResume,
            menuFor: { progress in AnyView(continueMenu(progress)) }
        )
    }

    // MARK: Rows

    /// Row header with a focusable "See All" affordance when the catalog can
    /// be paginated.
    @ViewBuilder
    private func catalogHeader(_ row: HomeRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            RowHeader(title: row.title)
            if let addon = row.addon, let catalog = row.catalog {
                Spacer()
                Button {
                    onSeeAll(addon, catalog, row.title)
                } label: {
                    SeeAllLabel()
                }
                .buttonStyle(PlainCardButtonStyle())
                .padding(.trailing, NuvioSpacing.huge)
            }
        }
    }

    /// Modern view can show landscape cards instead of portrait posters (APK's
    /// "Landscape Posters" toggle).
    private var useLandscape: Bool {
        layout == .modern && homeCatalogSettings.landscapePosters
    }

    private func horizontalRow(_ row: HomeRow) -> some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            catalogHeader(row)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: NuvioSpacing.lg) {
                    ForEach(row.items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            Group {
                                if useLandscape {
                                    LandscapeCard(
                                        imageURL: item.background ?? item.poster,
                                        title: item.name,
                                        subtitle: nil,
                                        width: 340
                                    )
                                } else {
                                    PosterCard(item: item)
                                }
                            }
                            .onFocusChange { focused in
                                if focused { hero.focus(item) }
                            }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        .contextMenu { posterMenu(item) }
                        // ⏯ on a focused card skips the Detail page and goes
                        // straight to the source picker.
                        .onPlayPauseCommand { onPlayManually(item, nil) }
                    }
                }
                .padding(.horizontal, NuvioSpacing.huge)
                .padding(.vertical, NuvioSpacing.lg)
            }
            .scrollClipDisabled()
        }
    }

    private func posterGrid(_ row: HomeRow) -> some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            catalogHeader(row)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: homeCatalogSettings.posterSize.posterWidth,
                                             maximum: homeCatalogSettings.posterSize.posterWidth),
                                   spacing: NuvioSpacing.lg, alignment: .top)],
                alignment: .leading,
                spacing: NuvioSpacing.xl
            ) {
                ForEach(row.items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        // Grid shows no billboard, so we deliberately do NOT
                        // drive the hero here — that per-focus enrich fetch was
                        // firing a network request on every D-pad move and is
                        // what made grid navigation lag.
                        PosterCard(item: item)
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .contextMenu { posterMenu(item) }
                    // ⏯ parity with the horizontal rows: skip Detail, go
                    // straight to the source picker.
                    .onPlayPauseCommand { onPlayManually(item, nil) }
                }
            }
            .padding(.horizontal, NuvioSpacing.huge)
            .padding(.vertical, NuvioSpacing.md)
        }
    }

    /// Hold-Select options for a poster: Details / Library / Watched. Same set
    /// for movies and shows (user asked for parity).
    @ViewBuilder
    private func posterMenu(_ item: MetaItem) -> some View {
        Button { onSelect(item) } label: { Label("Go to Details", systemImage: "info.circle") }
        Button {
            library.toggle(item)
        } label: {
            Label(library.contains(item) ? "Remove from Library" : "Add to Library",
                  systemImage: library.contains(item) ? "bookmark.slash" : "bookmark")
        }
        Button {
            watched.toggleMovie(item)
        } label: {
            Label(watched.isWatched(item) ? "Mark as Unwatched" : "Mark as Watched",
                  systemImage: watched.isWatched(item) ? "eye.slash" : "checkmark.circle")
        }
    }

    /// Hold-Select options for a Continue Watching card.
    @ViewBuilder
    private func continueMenu(_ progress: WatchProgress) -> some View {
        Button { onSelect(heroItem(from: progress)) } label: {
            Label("Go to Details", systemImage: "info.circle")
        }
        Button { onPlayManually(heroItem(from: progress), metaVideo(from: progress)) } label: {
            Label("Play Manually", systemImage: "list.and.film")
        }
        Button { onResumeFromStart(progress) } label: {
            Label("Start from Beginning", systemImage: "gobackward")
        }
        Button(role: .destructive) {
            // Remove the whole show (all episodes), like Netflix/Hulu — deleting
            // only this episode would let another episode of the same show pop
            // straight back into the row.
            progressStore.removeShow(metaID: progress.metaID)
        } label: {
            Label("Remove from Continue Watching", systemImage: "xmark")
        }
    }

    /// Rebuilds the episode identity from a progress entry (same shape the
    /// root's resume() builds) so manual playback keeps saving under the
    /// episode key instead of forking a new entry under the show.
    private func metaVideo(from progress: WatchProgress) -> MetaVideo? {
        guard progress.season != nil || progress.episode != nil else { return nil }
        return MetaVideo(
            id: progress.id,
            title: progress.episodeTitle,
            season: progress.season,
            episode: progress.episode
        )
    }

    private func continueSubtitle(_ progress: WatchProgress) -> String? {
        if let season = progress.season, let episode = progress.episode {
            var line = "S\(season):E\(episode)"
            if let title = progress.episodeTitle { line += " · \(title)" }
            return line
        }
        return nil
    }

    /// Continue Watching card art: the episode still when enabled and present,
    /// otherwise the show backdrop/poster.
    private func continueImage(_ progress: WatchProgress) -> String? {
        if homeCatalogSettings.useEpisodeThumbnailsInCw, let thumb = progress.episodeThumbnail, !thumb.isEmpty {
            return thumb
        }
        return progress.background ?? progress.poster
    }

    /// A hero-bar item for a Continue Watching entry. Progress rows only carry
    /// name/art, so prefer the full MetaItem when the title is also in a
    /// loaded catalog row (description, genres, rating…).
    private func heroItem(from progress: WatchProgress) -> MetaItem {
        for entry in viewModel.entries {
            if case .catalog(let row) = entry,
               let match = row.items.first(where: { $0.id == progress.metaID }) {
                return match
            }
        }
        return MetaItem(
            id: progress.metaID, type: progress.type, name: progress.name,
            poster: progress.poster, background: progress.background, logo: progress.logo
        )
    }
}

/// Continue Watching as its OWN view so the per-card focus bookkeeping stays
/// local. The remembered-card snap-back state used to live on HomeView itself,
/// so every left/right step inside this row wrote HomeView @State and
/// re-rendered the ENTIRE Home body — all rows — once per step. That's why
/// only this row lagged while the rest of Home was fine. Here, a focus step
/// re-renders just this row.
private struct ContinueWatchingRow: View {
    let items: [WatchProgress]
    /// Plain let (not observed): the row only CALLS into the hero, it never
    /// renders from it.
    let hero: HeroFocus
    /// False in Grid layout, where no backdrop/billboard renders the hero.
    let drivesHero: Bool
    let imageFor: (WatchProgress) -> String?
    let subtitleFor: (WatchProgress) -> String?
    let blurFor: (WatchProgress) -> Bool
    let heroItemFor: (WatchProgress) -> MetaItem
    let onResume: (WatchProgress) -> Void
    let menuFor: (WatchProgress) -> AnyView

    // Last-focused card. Coming back UP into the row after its horizontal
    // scroll moved, the focus engine can pick a geometrically-wrong card (the
    // "jumps to the 5th" bug). Two defenses: prefersDefaultFocus marks the
    // remembered card, and a FocusState snap-back forcibly returns focus to
    // it when the row is ENTERED on a different one.
    @State private var focusedContinueID: String?
    @FocusState private var focusedCWCard: String?
    @Namespace private var continueScope

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            RowHeader(title: "Continue Watching")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: NuvioSpacing.lg) {
                    ForEach(items) { progress in
                        Button {
                            onResume(progress)
                        } label: {
                            LandscapeCard(
                                imageURL: imageFor(progress),
                                title: progress.name,
                                subtitle: subtitleFor(progress),
                                progress: progress.fraction,
                                blurImage: blurFor(progress)
                            )
                            // Hero bar follows focus here too, like every other
                            // row. Inside the label: `\.isFocused` only resolves
                            // within the focusable Button, not around it.
                            // (The remembered card is updated in the FocusState
                            // onChange below — NOT here, or the wrong entry card
                            // would overwrite it before the snap-back runs.)
                            .onFocusChange { focused in
                                if focused, drivesHero { hero.focus(heroItemFor(progress)) }
                            }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        .focused($focusedCWCard, equals: progress.id)
                        // Returning to the row lands on the card you left, not
                        // the geometrically-nearest one after the pin scroll.
                        .prefersDefaultFocus(focusedContinueID == progress.id, in: continueScope)
                        .contextMenu { menuFor(progress) }
                        // ⏯ resumes instantly from a focused CW card too.
                        .onPlayPauseCommand { onResume(progress) }
                    }
                }
                .padding(.horizontal, NuvioSpacing.huge)
                .padding(.vertical, NuvioSpacing.lg)
            }
            .scrollClipDisabled()
            .focusScope(continueScope)
            .onChange(of: focusedCWCard) { oldValue, newValue in
                if let newValue {
                    // ENTERING the row on the wrong (geometric) card — snap
                    // back to the one the user left. In-row moves (oldValue
                    // non-nil) do NOTHING: writing @State on every left/right
                    // step re-rendered the whole row (every card + its
                    // progress-strip GeometryReader) each move — the lag.
                    if oldValue == nil,
                       let last = focusedContinueID, last != newValue,
                       items.contains(where: { $0.id == last }) {
                        focusedCWCard = last
                    }
                } else {
                    // LEAVING the row: record the card we were on so the next
                    // entry lands back on it. One re-render, off the hot path
                    // (focus has already left) — and it refreshes the
                    // prefersDefaultFocus markers for that next entry.
                    focusedContinueID = oldValue
                }
            }
        }
    }
}

/// First-run loading backdrop that announces each phase as it happens (add-ons
/// → catalogs → artwork), mirroring the Android app. Completed steps show a
/// check, the active step spins, and pending steps are dimmed. Only shown on a
/// cold, cache-less launch; warm starts render instantly from the disk cache.
private struct HomeLoadingBackdrop: View {
    @EnvironmentObject private var theme: ThemeManager
    let step: String?

    private let steps = ["Loading add-ons…", "Loading catalogs…", "Loading artwork…"]
    private var activeIndex: Int { steps.firstIndex(of: step ?? "") ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.lg) {
            Text("Nuvio")
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.bottom, NuvioSpacing.sm)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                HStack(spacing: NuvioSpacing.md) {
                    icon(for: index)
                        .frame(width: 34, height: 34)
                    Text(label.replacingOccurrences(of: "…", with: ""))
                        .font(.system(size: 27, weight: index == activeIndex ? .semibold : .regular))
                        .foregroundStyle(index <= activeIndex
                            ? theme.palette.textPrimary
                            : theme.palette.textSecondary.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func icon(for index: Int) -> some View {
        if index < activeIndex {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(theme.palette.secondary)
        } else if index == activeIndex {
            ProgressView()
                .progressViewStyle(.circular)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 26))
                .foregroundStyle(theme.palette.textSecondary.opacity(0.35))
        }
    }
}

/// Focus-styled "Try Again" pill shared by network-failure empty states.
struct RetryLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: NuvioSpacing.sm) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 20, weight: .semibold))
            Text("Try Again")
                .font(.system(size: 24, weight: .semibold))
        }
        .foregroundStyle(isFocused ? theme.palette.onSecondary : theme.palette.textPrimary)
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(Capsule().fill(isFocused ? theme.palette.secondary : Color.white.opacity(0.1)))
        .overlay(Capsule().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3))
        .scaleEffect(PerformanceSettingsStore.shared.buttonAnimationsEffective && isFocused ? 1.05 : 1)
        .animation(PerformanceSettingsStore.shared.buttonAnimationsEffective
                   ? .easeInOut(duration: 0.15) : nil, value: isFocused)
    }
}

/// "See All ›" pill shown in a catalog row header (text is reusable for other
/// header-side actions, e.g. "Mark Season Watched").
struct SeeAllLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    var text: String = "See All"

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 22, weight: .semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .bold))
        }
        .foregroundStyle(isFocused ? theme.palette.textPrimary : theme.palette.textSecondary)
        .padding(.horizontal, NuvioSpacing.md)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isFocused ? theme.palette.focusBackground : Color.white.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
        )
        .scaleEffect(PerformanceSettingsStore.shared.buttonAnimationsEffective && isFocused ? 1.06 : 1)
        .animation(PerformanceSettingsStore.shared.buttonAnimationsEffective
                   ? .spring(response: 0.3, dampingFraction: 0.8) : nil, value: isFocused)
    }
}

extension View {
    /// Small helper because `.onFocusChange` reads better at call sites than
    /// the focusable/onChange dance.
    func onFocusChange(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(FocusChangeModifier(action: action))
    }
}

private struct FocusChangeModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    let action: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: isFocused) { _, newValue in
                action(newValue)
            }
            // onChange misses the INITIAL value: a lazy cell created by a fast
            // scroll (or at launch) can be born already-focused with no change
            // event.
            .onAppear {
                if isFocused { action(true) }
            }
    }
}

// MARK: - Billboard (isolated so hero updates don't re-render the rows)

/// Full-bleed backdrop for the focused title. Observes `HeroFocus` on its own,
/// so the animated hero swap re-renders ONLY this view — not the poster rows
/// (that re-render was cancelling the first long-press on a card).
private struct HeroBackdropView: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject var hero: HeroFocus

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let item = hero.item {
                    // No .id() — RemoteImage crossfades internally as the URL
                    // changes, dissolving between titles instead of reloading.
                    RemoteImage(url: item.background ?? item.poster)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                // Netflix scrim: art reads on the top-right; the left third is
                // darkened for the title/synopsis; the lower half dissolves into
                // the background so the rows sit on near-solid black.
                // Smooth continuous ramp (many stops, fade starts immediately)
                // so there's no flat near-solid block that reads as a second
                // "tone" next to the sidebar — it just dissolves into the art.
                LinearGradient(
                    stops: [
                        .init(color: theme.palette.background, location: 0),
                        .init(color: theme.palette.background.opacity(0.92), location: 0.14),
                        .init(color: theme.palette.background.opacity(0.72), location: 0.30),
                        .init(color: theme.palette.background.opacity(0.45), location: 0.46),
                        .init(color: theme.palette.background.opacity(0.20), location: 0.62),
                        .init(color: .clear, location: 0.80)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.32),
                        .init(color: theme.palette.background.opacity(0.55), location: 0.52),
                        .init(color: theme.palette.background, location: 0.66)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

/// Title / meta / synopsis block for the focused title. Same isolation as the
/// backdrop.
private struct HeroInfoView: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var perf = PerformanceSettingsStore.shared
    @ObservedObject var hero: HeroFocus

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            if let item = hero.item {
                // Crossfade ON (Settings → Performance → Hero crossfade): the
                // whole info block dissolves between titles — `.id` replaces
                // the subtree per focus move (logo view + fetch task + text
                // layout), paired with HeroFocus.focus's withAnimation. That
                // teardown is the cost that made Modern scrub heavier than
                // Classic/Grid, so OFF takes the cheap path: in-place updates,
                // texts swap directly, the logo crossfades internally as its
                // URL changes.
                if perf.heroCrossfadeEffective {
                    content(item)
                        .id(item.id)
                        .transition(.opacity)
                } else {
                    content(item)
                }
            }
        }
        .frame(height: 330, alignment: .bottomLeading)
    }

    @ViewBuilder
    private func content(_ item: MetaItem) -> some View {
        if let logo = item.logo {
            RemoteImage(url: logo, contentMode: .fit, alignment: .bottomLeading)
                .frame(width: 460, height: 150)
        } else {
            Text(item.name)
                .font(.system(size: 58, weight: .heavy))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
        }

        // APK meta order: Type • Genre • Runtime • Year • IMDb badge + rating.
        HStack(spacing: NuvioSpacing.sm) {
            MetaDotText(item.typeLabel)
            if let genre = item.genres?.first {
                MetaDot(); MetaDotText(genre)
            }
            if let runtime = item.runtimeFormatted {
                MetaDot(); MetaDotText(runtime)
            }
            if let year = item.year {
                MetaDot(); MetaDotText(year)
            }
            if let rating = item.imdbRating {
                MetaDot(); ImdbBadge(rating: rating)
            }
        }

        if let description = item.description {
            Text(description)
                .font(.system(size: 24))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: 820, alignment: .leading)
        }
    }
}
