import SwiftUI

@MainActor
final class StreamsViewModel: ObservableObject {
    /// Addon → resolution section → size subsection → rows (see SourceSelection).
    @Published var groups: [AddonSourceGroup] = []
    @Published var isLoading = true
    @Published var finishedAddons = 0
    @Published var totalAddons = 0
    /// Addons that returned at least one usable link, in the order they arrived
    /// — drives the filter chips. nil `selectedAddon` = show all (merged).
    @Published var addonNames: [String] = []
    @Published var selectedAddon: String? = nil

    let meta: MetaItem
    let video: MetaVideo?

    /// Every usable link across all addons, kept raw so the addon filter can
    /// re-curate a SINGLE addon's full set (not just what survived the
    /// cross-addon per-tier cap).
    private var pool: [StreamEntry] = []
    /// Links kept per resolution×size cell (2160p·10–20 GB …) when filters on.
    private var perTier = 6
    /// Curated filters on (resolution → size tiers, cached first) vs raw
    /// capped-per-addon.
    private var filtersEnabled = true

    init(meta: MetaItem, video: MetaVideo?) {
        self.meta = meta
        self.video = video
    }

    var streamID: String {
        video?.id ?? meta.id
    }

    /// The id actually sent to stream addons — resolved once, then reused so
    /// the cache key and every fetch agree. Two normalizations, both so a
    /// resumed / manually-played title lands on an id Cinemeta/Comet/Torrentio
    /// can resolve (the "Comet unable to get metadata" empty source page):
    ///  1. `tmdb:<n>` → IMDb `tt` (those addons can't serve tmdb ids).
    ///  2. For a series episode, force the canonical `showId:season:episode`
    ///     form instead of trusting a stored `video.id`, which after a
    ///     Continue-Watching round-trip can be the bare show id.
    private var resolvedID: String?
    private func effectiveStreamID() async -> String {
        if let resolvedID { return resolvedID }
        var showID = meta.id
        if showID.hasPrefix("tmdb:"), let n = Int(showID.dropFirst("tmdb:".count)),
           let tt = await TMDBService.imdbID(tmdbID: n, isMovie: meta.type != "series") {
            showID = tt
        }
        let id: String
        if showID.hasPrefix("tt"), let season = video?.season, let episode = video?.episode {
            id = "\(showID):\(season):\(episode)"
        } else {
            id = video?.id ?? showID
        }
        resolvedID = id
        return id
    }

    var allEntries: [StreamEntry] {
        groups.flatMap(\.entries)
    }

    /// Filter the visible list to a single addon (nil = All). Re-curates from
    /// the raw pool so the chosen addon shows its full per-tier selection.
    func selectAddon(_ name: String?) {
        guard selectedAddon != name else { return }
        selectedAddon = name
        rebuildGroups()
    }

    /// Disk-backed cache of a title's raw source list so re-opening a title
    /// (or resuming from Continue Watching) rebuilds the Sources list instantly
    /// instead of sweeping every addon again. TTL is short because addon direct
    /// links can go stale; the player's failover re-fetches if one has expired.
    static let sourceCache = DiskCache<[CachedStreamSource]>(name: "sources")
    static let sourceCacheTTL: TimeInterval = 15 * 60

    /// Remembers the last successfully-played source per title so "Reuse last
    /// link" can replay it without another addon sweep. Freshness is enforced
    /// per-read against the user's chosen cache window.
    static let lastLinkCache = DiskCache<CachedStreamSource>(name: "lastlink")

    /// The last played source for this title if still within `hours`, else nil.
    func freshLastLink(hours: Int) async -> StreamEntry? {
        let id = await effectiveStreamID()
        guard let cached = await Self.lastLinkCache.value(
            for: id, ttl: TimeInterval(max(1, hours)) * 3600
        ) else { return nil }
        return StreamEntry(addonName: cached.addonName, stream: cached.stream)
    }

    /// Record a resolved, directly-playable source as this title's last link.
    func recordLastLink(_ entry: StreamEntry) {
        guard entry.stream.isPlayable, let id = resolvedID else { return }
        let cached = CachedStreamSource(addonName: entry.addonName, stream: entry.stream)
        Task { await Self.lastLinkCache.store(cached, for: id) }
    }

    /// Merge streams produced by plugin scrapers into the pool (they arrive
    /// after the addon sweep, so re-curate). Deduped by URL.
    func addPluginStreams(_ entries: [StreamEntry]) {
        guard !entries.isEmpty else { return }
        let existing = Set(pool.compactMap { $0.stream.url })
        let fresh = entries.filter { entry in
            guard let url = entry.stream.url else { return false }
            return !existing.contains(url)
        }
        guard !fresh.isEmpty else { return }
        pool.append(contentsOf: fresh)
        rebuildGroups()
    }

    /// Best source for a profile's Auto Link Selector. Entries are already
    /// sorted best-first; we filter by the profile's cached-only / min-
    /// resolution / max-size prefs, then prefer the chosen addon (then the
    /// secondary), falling back to the best remaining link. Unknown
    /// resolution/size never disqualifies a link (missing metadata shouldn't
    /// hide a possibly-good source).
    func autoLinkPick(_ prefs: AutoLinkPreferences) -> StreamEntry? {
        let minTier = prefs.minResolution.isEmpty ? nil
            : ResolutionTier.from(resolutionLabel: prefs.minResolution)
        let maxBytes = prefs.maxSizeGB > 0 ? Int64(prefs.maxSizeGB * 1_073_741_824) : nil
        let pool = allEntries.filter { entry in
            if prefs.cachedOnly && !entry.stream.isCached { return false }
            if let minTier, let label = entry.resolutionLabel,
               ResolutionTier.from(resolutionLabel: label).rawValue > minTier.rawValue { return false }
            if let maxBytes, let bytes = entry.sizeBytes, bytes > 0, bytes > maxBytes { return false }
            return true
        }
        guard !pool.isEmpty else { return nil }
        func firstFromAddon(_ name: String) -> StreamEntry? {
            let q = name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return nil }
            return pool.first { $0.addonName.lowercased().contains(q) }
        }
        return firstFromAddon(prefs.preferredAddon)
            ?? firstFromAddon(prefs.secondaryAddon)
            ?? pool.first
    }

    /// First source to auto-play (entries are already sorted best-first),
    /// honoring cached-only and an optional case-insensitive title regex.
    func autoPlayPick(cachedOnly: Bool, regex: String) -> StreamEntry? {
        let trimmed = regex.trimmingCharacters(in: .whitespaces)
        let re = trimmed.isEmpty ? nil
            : try? NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
        return allEntries.first { entry in
            if cachedOnly && !entry.stream.isCached { return false }
            if let re {
                let hay = "\(entry.addonName) \(entry.displayName) \(entry.displayDetail)"
                let range = NSRange(hay.startIndex..., in: hay)
                if re.firstMatch(in: hay, range: range) == nil { return false }
            }
            return true
        }
    }

    /// Reset and fetch again (the empty state's Try Again) — bypasses the cache
    /// so the user gets a genuinely fresh sweep.
    func reload(addonManager: AddonManager, debridEnabled: Bool, perTier: Int, filtersEnabled: Bool = true) async {
        groups = []
        pool = []
        addonNames = []
        selectedAddon = nil
        finishedAddons = 0
        await load(addonManager: addonManager, debridEnabled: debridEnabled, perTier: perTier, filtersEnabled: filtersEnabled, forceRefresh: true)
    }

    /// When a debrid provider is configured, torrent streams (infoHash, no
    /// direct URL) are kept so they can be resolved on selection; otherwise
    /// only directly-playable http(s) streams are shown.
    ///
    /// Each addon's links are grouped into size tiers (250 MB–4 GB … 30 GB+),
    /// debrid-cached links first within each tier, capped at `perTier` — so
    /// the list is short and useful instead of the 150+ near-identical rips
    /// Torrentio alone returns, which is what made scrolling (and selecting
    /// during load) choke.
    func load(addonManager: AddonManager, debridEnabled: Bool, perTier: Int, filtersEnabled: Bool = true, forceRefresh: Bool = false) async {
        let fetchID = await effectiveStreamID()
        let addons = addonManager.streamAddons.filter { $0.handles(id: fetchID) }
        totalAddons = addons.count
        self.perTier = perTier
        self.filtersEnabled = filtersEnabled
        isLoading = true

        // Instant path: a fresh cached source list rebuilds the whole page with
        // no addon sweep at all.
        if !forceRefresh,
           let cached = await Self.sourceCache.value(for: fetchID, ttl: Self.sourceCacheTTL),
           !cached.isEmpty {
            pool = cached.map { StreamEntry(addonName: $0.addonName, stream: $0.stream) }
            finishedAddons = totalAddons
            rebuildGroups()
            isLoading = false
            return
        }

        await withTaskGroup(of: [StreamEntry].self) { group in
            for addon in addons {
                group.addTask { [meta] in
                    let streams = (try? await StremioAPI.streams(addon: addon, type: meta.type, id: fetchID)) ?? []
                    return streams
                        .filter { $0.isPlayable || (debridEnabled && $0.isTorrent) }
                        .map { StreamEntry(addonName: addon.manifest.name, stream: $0) }
                }
            }
            // Re-curate on throttled batches: recomputing the tier selection per
            // addon made the whole list re-diff several times in the first
            // seconds — exactly while the user starts scrolling it.
            var lastFlush = Date.distantPast
            for await batch in group {
                finishedAddons += 1
                pool.append(contentsOf: batch)
                let now = Date()
                if !pool.isEmpty, now.timeIntervalSince(lastFlush) > 0.4 {
                    rebuildGroups()
                    lastFlush = now
                }
            }
            rebuildGroups()
        }
        isLoading = false

        // Persist for instant re-open.
        let snapshot = pool.map { CachedStreamSource(addonName: $0.addonName, stream: $0.stream) }
        if !snapshot.isEmpty {
            await Self.sourceCache.store(snapshot, for: fetchID)
        }
    }

    /// Recompute `addonNames` + `groups` from the raw pool, honoring the
    /// current addon filter. Called on every load flush and filter change.
    private func rebuildGroups() {
        // First-seen order of the addons that actually returned links.
        var seen = Set<String>()
        addonNames = pool.compactMap { seen.insert($0.addonName).inserted ? $0.addonName : nil }
        // Drop a stale filter (e.g. after a reload dropped that addon).
        if let selected = selectedAddon, !addonNames.contains(selected) {
            selectedAddon = nil
        }
        let scoped0 = selectedAddon.map { name in pool.filter { $0.addonName == name } } ?? pool
        let scoped = SourceSelection.filter(scoped0, streamFilters)
        groups = filtersEnabled
            ? SourceSelection.byAddon(scoped, perTier: perTier)
            : SourceSelection.byAddonUnfiltered(scoped, cap: PlayerSettings.unfilteredPerAddonCap)
    }

    /// User stream filters (min resolution, exclude AV1, HDR/DV/cached only).
    var streamFilters = StreamFilterOptions()
}

struct StreamsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var debrid: DebridStore
    @EnvironmentObject private var playerSettings: PlayerSettingsStore
    @EnvironmentObject private var streamBadges: StreamBadgeStore
    @EnvironmentObject private var plugins: PluginStore
    @EnvironmentObject private var torrent: TorrentSettingsStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var profiles: ProfileStore
    @StateObject private var viewModel: StreamsViewModel

    /// Manual mode (hold-Play / "Play Manually"): skip every auto-action so the
    /// user always lands on the source list, even with Auto Link Selector on.
    let forceManual: Bool
    /// Called when the Auto Link Selector auto-plays, so the caller can pop this
    /// page off the stack — backing out of the player returns to the title, not
    /// the source list.
    var onAutoDismiss: () -> Void = {}

    /// Auto Link Selector is resolving: show a loading screen instead of the
    /// source list so Play goes straight to "loading" with no list flash.
    @State private var autoLinkResolving = false

    @State private var resolving = false
    @State private var resolveError: String?
    // Sources load asynchronously; when the first ones arrive, move focus onto
    // the top source so the trackpad can navigate immediately instead of the
    // user having to swipe to "find" focus.
    @FocusState private var focusedEntry: UUID?
    /// Guards the one-time auto-focus so filter changes don't steal focus.
    @State private var didInitialFocus = false
    /// Guards the one-shot auto-play / reuse-last-link so backing out of the
    /// player lands on the manual list instead of re-triggering.
    @State private var didAutoAct = false

    let onSelect: (StreamEntry, [StreamEntry]) -> Void

    init(meta: MetaItem, video: MetaVideo?, forceManual: Bool = false,
         onAutoDismiss: @escaping () -> Void = {},
         onSelect: @escaping (StreamEntry, [StreamEntry]) -> Void) {
        _viewModel = StateObject(wrappedValue: StreamsViewModel(meta: meta, video: video))
        self.forceManual = forceManual
        self.onAutoDismiss = onAutoDismiss
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            backdrop

            // APK split layout: content info on the LEFT, sources panel on the RIGHT.
            HStack(alignment: .top, spacing: NuvioSpacing.xl) {
                titleBlock
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                sourcesPanel
                    .frame(width: 900)
                    .frame(maxHeight: .infinity)
                    .background(
                        // Opaque: a translucent panel over the full-screen
                        // backdrop forced per-frame blending of the whole
                        // panel while scrolling — a real cost on the A10X.
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(theme.palette.backgroundElevated)
                    )
                    // Keep the scrolling rows INSIDE the rounded panel —
                    // without this they draw over its edges as you scroll.
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, NuvioSpacing.huge)
            .padding(.vertical, NuvioSpacing.xxl)

            if resolving {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    NuvioLoadingView(label: "Resolving via \(debrid.resolverProvider?.displayName ?? (torrent.settings.isConfigured ? "TorrServer" : "debrid"))")
                }
            }
        }
        .task {
            let s = playerSettings.settings
            viewModel.streamFilters = s.streamFilterOptions
            // Auto Link Selector on (and not forced manual): show the loading
            // screen instead of the source list from the very first frame.
            autoLinkResolving = profiles.activeAutoLink.enabled && !forceManual

            // Reuse last link: if we still have a fresh remembered source, play
            // it immediately, but keep loading so backing out shows the full
            // list (and the player's failover has alternates).
            let loadTask = Task {
                await viewModel.load(
                    addonManager: addonManager,
                    debridEnabled: debrid.hasAnyConfigured || torrent.settings.isConfigured,
                    perTier: s.sourcesPerSizeTier,
                    filtersEnabled: s.sourceFiltersEnabled
                )
            }
            // Plugin scrapers run alongside the addon sweep (they want a TMDB id).
            if !plugins.enabledScrapers.isEmpty {
                Task {
                    guard let (tmdbID, isMovie) = await TMDBService.resolveTMDBID(
                        from: viewModel.meta.id, type: viewModel.meta.type
                    ) else { return }
                    let entries = await plugins.streams(
                        tmdbID: String(tmdbID), mediaType: isMovie ? "movie" : "tv",
                        season: viewModel.video?.season, episode: viewModel.video?.episode
                    )
                    viewModel.addPluginStreams(entries)
                }
            }
            if !didAutoAct, !forceManual, s.reuseLastLinkEnabled,
               let last = await viewModel.freshLastLink(hours: s.reuseLastLinkCacheHours) {
                didAutoAct = true
                await loadTask.value
                if autoLinkResolving { onAutoDismiss() }
                onSelect(last, viewModel.allEntries)
                return
            }
            await loadTask.value

            // Auto Link Selector (per profile): pick the best link matching the
            // profile's preferred addon / quality / size and play it directly.
            // Takes precedence over the global auto-play. Skipped in manual mode.
            let autoLink = profiles.activeAutoLink
            if !didAutoAct, !forceManual, autoLink.enabled {
                if let pick = viewModel.autoLinkPick(autoLink) {
                    didAutoAct = true
                    // Pop this page so backing out of the player lands on the
                    // title page, not the source list.
                    onAutoDismiss()
                    handleSelection(pick, viewModel.allEntries)
                } else {
                    // No source matched the prefs — reveal the list as a manual
                    // fallback instead of leaving the loading screen up.
                    autoLinkResolving = false
                }
            }

            // Auto-play best source: once the sweep is done, start the best
            // matching link without waiting for a manual pick.
            if !didAutoAct, !forceManual, s.autoPlaySourceEnabled,
               let best = viewModel.autoPlayPick(
                   cachedOnly: s.autoPlaySourceCachedOnly, regex: s.autoPlaySourceRegex
               ) {
                didAutoAct = true
                handleSelection(best, viewModel.allEntries)
            }

            // Safety net: if we opened in auto-loading mode but nothing acted,
            // drop the loading screen so the user isn't stuck on it.
            if autoLinkResolving && !didAutoAct { autoLinkResolving = false }
        }
        .alert("Couldn't resolve stream", isPresented: Binding(
            get: { resolveError != nil }, set: { if !$0 { resolveError = nil } }
        )) {
            Button("OK", role: .cancel) { resolveError = nil }
        } message: {
            Text(resolveError ?? "")
        }
    }

    /// The right-hand source panel: loading / empty / grouped list.
    @ViewBuilder
    private var sourcesPanel: some View {
        if autoLinkResolving {
            NuvioLoadingView(label: "Finding the best source…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.groups.isEmpty {
            if viewModel.isLoading {
                NuvioLoadingView(label: streamCountLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: NuvioSpacing.lg) {
                    NuvioEmptyState(
                        icon: "play.slash",
                        title: "No sources found",
                        message: "None of your installed addons returned a playable link for this title. Install a stream addon in Settings."
                    )
                    Button {
                        Task {
                            await viewModel.reload(
                                addonManager: addonManager,
                                debridEnabled: debrid.hasAnyConfigured || torrent.settings.isConfigured,
                                perTier: playerSettings.settings.sourcesPerSizeTier,
                                filtersEnabled: playerSettings.settings.sourceFiltersEnabled
                            )
                        }
                    } label: {
                        RetryLabel()
                    }
                    .buttonStyle(PlainCardButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: NuvioSpacing.md) {
                if viewModel.addonNames.count > 1 {
                    addonFilterBar
                }
                streamList
            }
            .padding(NuvioSpacing.md)
        }
    }

    /// Stremio-style addon filter: "All" plus one chip per addon that returned
    /// links. Picking one shows only that addon's sources (still tiered).
    private var addonFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NuvioSpacing.sm) {
                AddonFilterChip(
                    title: "All",
                    selected: viewModel.selectedAddon == nil
                ) { viewModel.selectAddon(nil) }

                ForEach(viewModel.addonNames, id: \.self) { name in
                    AddonFilterChip(
                        title: name,
                        selected: viewModel.selectedAddon == name
                    ) { viewModel.selectAddon(name) }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    /// Torrent entries resolve through the preferred debrid provider before
    /// playback; direct streams pass straight through.
    private func handleSelection(_ entry: StreamEntry, _ all: [StreamEntry]) {
        guard entry.stream.isTorrent else {
            viewModel.recordLastLink(entry)
            onSelect(entry, all)
            return
        }
        guard let provider = debrid.resolverProvider else {
            // No debrid: fall back to P2P (TorrServer) if the user enabled it.
            if torrent.settings.isConfigured {
                resolveViaP2P(entry, all)
            } else {
                resolveError = "Add a debrid API key, or turn on P2P (TorrServer) in Settings → Integrations, to play torrent sources."
            }
            return
        }
        resolving = true
        Task {
            let result = await DebridService.resolve(
                stream: entry.stream,
                provider: provider,
                apiKey: debrid.key(for: provider),
                season: viewModel.video?.season,
                episode: viewModel.video?.episode
            )
            resolving = false
            switch result {
            case .success(let url, let filename):
                let resolved = Stream(
                    name: entry.stream.name,
                    title: filename ?? entry.stream.title,
                    description: entry.stream.description,
                    url: url,
                    infoHash: nil,
                    behaviorHints: entry.stream.behaviorHints
                )
                let resolvedEntry = StreamEntry(addonName: "\(provider.shortName) · \(entry.addonName)", stream: resolved)
                viewModel.recordLastLink(resolvedEntry)
                onSelect(resolvedEntry, all)
            case .missingKey:
                resolveError = "\(provider.displayName) API key is missing."
            case .notCached:
                resolveError = "This torrent isn't cached on \(provider.displayName). Try another source."
            case .failed(let message):
                resolveError = "\(provider.displayName): \(message)"
            }
        }
    }

    /// Play a torrent via the user's TorrServer instance (P2P) — no debrid.
    private func resolveViaP2P(_ entry: StreamEntry, _ all: [StreamEntry]) {
        guard let magnet = entry.stream.magnetURI
            ?? entry.stream.infoHash.map({ "magnet:?xt=urn:btih:\($0)" }) else {
            resolveError = "This source has no magnet link to hand to TorrServer."
            return
        }
        resolving = true
        Task {
            let result = await TorrServerService.resolve(
                magnet: magnet, settings: torrent.settings,
                season: viewModel.video?.season, episode: viewModel.video?.episode
            )
            resolving = false
            switch result {
            case .success(let url, let filename):
                let resolved = Stream(
                    name: entry.stream.name,
                    title: filename ?? entry.stream.title,
                    description: entry.stream.description,
                    url: url, infoHash: nil,
                    behaviorHints: entry.stream.behaviorHints
                )
                let resolvedEntry = StreamEntry(addonName: "P2P · \(entry.addonName)", stream: resolved)
                viewModel.recordLastLink(resolvedEntry)
                onSelect(resolvedEntry, all)
            case .notConfigured:
                resolveError = "Turn on P2P and set a TorrServer URL in Settings → Integrations."
            case .failed(let message):
                resolveError = message
            }
        }
    }

    private var streamCountLabel: String {
        guard viewModel.totalAddons > 0 else { return "Searching addons" }
        return "Searching addons \(viewModel.finishedAddons)/\(viewModel.totalAddons)"
    }

    private var backdrop: some View {
        GeometryReader { geo in
            ZStack {
                RemoteImage(url: viewModel.meta.background ?? viewModel.meta.poster)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.5)
                HeroGradient(background: theme.palette.background, fullBleed: true)
            }
        }
        .ignoresSafeArea()
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.xs) {
            Text(viewModel.meta.name)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
            if let video = viewModel.video {
                Text("\(video.seasonEpisodeCode)\(video.title.map { " • \($0)" } ?? "")")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }
            if viewModel.isLoading && !viewModel.groups.isEmpty {
                Text(streamCountLabel)
                    .font(.system(size: 21))
                    .foregroundStyle(theme.palette.textTertiary)
            }
        }
    }

    private var streamList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: NuvioSpacing.xl) {
                ForEach(viewModel.groups) { group in
                    VStack(alignment: .leading, spacing: NuvioSpacing.md) {
                        // Level 1: addon.
                        Text(group.addonName.uppercased())
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(theme.palette.textPrimary)
                            .padding(.leading, 4)
                        ForEach(group.sections) { section in
                            VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
                                // Level 2: resolution (hidden when untiered).
                                if !section.title.isEmpty {
                                    Text(section.title.uppercased())
                                        .font(.system(size: 20, weight: .heavy))
                                        .foregroundStyle(theme.palette.secondary)
                                        .padding(.leading, 8)
                                        .padding(.top, 2)
                                }
                                ForEach(section.entries) { entry in
                                    sourceRow(entry)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, NuvioSpacing.lg)
        }
        .onChange(of: viewModel.groups.count) { _, _ in
            // Only grab focus on the FIRST results arriving — otherwise changing
            // the addon filter (which rebuilds groups) would yank focus off the
            // chip you just picked and down into the list.
            guard !didInitialFocus, focusedEntry == nil,
                  let first = viewModel.groups.first?.entries.first else { return }
            focusedEntry = first.id
            didInitialFocus = true
        }
    }

    private func sourceRow(_ entry: StreamEntry) -> some View {
        Button {
            handleSelection(entry, viewModel.allEntries)
        } label: {
            StreamRowView(
                entry: entry,
                debridShortName: entry.stream.isTorrent ? debrid.resolverProvider?.shortName : nil,
                badges: streamBadges.badges(for: entry)
            )
        }
        .buttonStyle(PlainCardButtonStyle())
        .focused($focusedEntry, equals: entry.id)
        // Hold Select → context actions.
        .contextMenu {
            // Download for offline. Direct links download straight away;
            // torrents resolve via debrid/P2P first, then download the result.
            Button {
                downloadSelection(entry)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            if entry.stream.isPlayable, let streamURL = entry.stream.url,
               ExternalPlayers.isInfuseInstalled {
                Button {
                    ExternalPlayers.openInInfuse(urlString: streamURL)
                } label: {
                    Label("Play in Infuse", systemImage: "arrow.up.forward.app.fill")
                }
            }
        }
    }

    /// Save a source to disk for offline viewing. Direct links start now;
    /// torrents are resolved (debrid preferred, then P2P) into a direct URL
    /// first — the same resolution used for playback.
    private func downloadSelection(_ entry: StreamEntry) {
        if entry.stream.isPlayable {
            downloads.start(meta: viewModel.meta, video: viewModel.video, stream: entry.stream, addonName: entry.addonName)
            return
        }
        // Torrent → resolve, then download the resolved direct stream.
        if let provider = debrid.resolverProvider {
            resolving = true
            Task {
                let result = await DebridService.resolve(
                    stream: entry.stream, provider: provider, apiKey: debrid.key(for: provider),
                    season: viewModel.video?.season, episode: viewModel.video?.episode
                )
                resolving = false
                if case .success(let url, let filename) = result {
                    let resolved = Stream(name: entry.stream.name, title: filename ?? entry.stream.title,
                                          description: entry.stream.description, url: url, infoHash: nil,
                                          behaviorHints: entry.stream.behaviorHints)
                    downloads.start(meta: viewModel.meta, video: viewModel.video, stream: resolved, addonName: entry.addonName)
                } else {
                    resolveError = "Couldn't resolve this source to download it."
                }
            }
        } else if torrent.settings.isConfigured,
                  let magnet = entry.stream.magnetURI ?? entry.stream.infoHash.map({ "magnet:?xt=urn:btih:\($0)" }) {
            resolving = true
            Task {
                let result = await TorrServerService.resolve(
                    magnet: magnet, settings: torrent.settings,
                    season: viewModel.video?.season, episode: viewModel.video?.episode
                )
                resolving = false
                if case .success(let url, let filename) = result {
                    let resolved = Stream(name: entry.stream.name, title: filename ?? entry.stream.title,
                                          description: entry.stream.description, url: url, infoHash: nil,
                                          behaviorHints: entry.stream.behaviorHints)
                    downloads.start(meta: viewModel.meta, video: viewModel.video, stream: resolved, addonName: entry.addonName)
                } else {
                    resolveError = "Couldn't resolve this source to download it."
                }
            }
        } else {
            resolveError = "Add a debrid key or enable P2P to download torrent sources."
        }
    }
}

struct StreamRowView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused

    let entry: StreamEntry
    var debridShortName: String?
    /// Badger badge chips matched for this link (see StreamBadgeStore).
    var badges: [StreamBadge] = []

    var body: some View {
        HStack(spacing: NuvioSpacing.lg) {
            Image(systemName: entry.stream.isTorrent ? "bolt.horizontal.circle.fill" : "play.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(isFocused ? theme.palette.secondary : theme.palette.textTertiary)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
                if !entry.displayDetail.isEmpty {
                    Text(entry.displayDetail)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                }
                if !badges.isEmpty {
                    StreamBadgeChips(badges: badges)
                        .padding(.top, 2)
                }
            }

            Spacer()

            // Debrid-cached torrent → instant play; worth calling out since
            // cached links sort first.
            if entry.stream.isTorrent, entry.isInstant {
                MetaBadge(
                    text: "⚡︎ Cached",
                    tint: NuvioPrimitives.success.opacity(0.22),
                    textColor: NuvioPrimitives.success
                )
            }

            if let debridShortName {
                MetaBadge(
                    text: debridShortName,
                    tint: NuvioPrimitives.success.opacity(0.22),
                    textColor: NuvioPrimitives.success
                )
            }

            // Resolution over file size, stacked in the same badge form:
            //   [2160p]
            //   [55.3 GB]
            if entry.resolutionLabel != nil || entry.fileSizeLabel != nil {
                VStack(alignment: .trailing, spacing: 5) {
                    if let resolution = entry.resolutionLabel {
                        MetaBadge(
                            text: resolution,
                            tint: theme.palette.secondary.opacity(0.22),
                            textColor: theme.palette.secondary
                        )
                    }
                    if let size = entry.fileSizeLabel {
                        MetaBadge(
                            text: size,
                            tint: Color.white.opacity(0.12),
                            textColor: .white.opacity(0.85)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, NuvioSpacing.lg)
        .padding(.vertical, NuvioSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Opaque card fill: translucent rows over the panel over the
            // backdrop meant three blended layers per pixel during scroll.
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .fill(isFocused ? theme.palette.focusBackground : theme.palette.backgroundCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 2.5)
        )
        // No focus scale: scaling a row forces offscreen re-composition of
        // the whole card every focus move mid-scroll (stutter on the A10X);
        // the fill + ring change is plenty of focus affordance.
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A pill in the addon filter bar. Fills with the accent when it's the active
/// filter; focus adds the ring, matching every other Nuvio control.
private struct AddonFilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AddonFilterChipLabel(title: title, selected: selected)
        }
        .buttonStyle(PlainCardButtonStyle())
    }
}

private struct AddonFilterChipLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, NuvioSpacing.lg)
            .padding(.vertical, NuvioSpacing.sm)
            .background(Capsule().fill(background))
            .overlay(
                Capsule().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.05 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isFocused)
    }

    private var foreground: Color {
        if isFocused { return theme.palette.onSecondary }
        if selected { return theme.palette.secondary }
        return theme.palette.textSecondary
    }

    private var background: Color {
        if isFocused { return theme.palette.secondary }
        if selected { return theme.palette.secondary.opacity(0.22) }
        return theme.palette.backgroundCard.opacity(0.85)
    }
}
