import SwiftUI

@main
struct NuvioTVApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var addonManager = AddonManager()
    @StateObject private var progressStore = ProgressStore()
    @StateObject private var account = NuvioAccountManager()
    @StateObject private var library = LibraryStore()
    @StateObject private var watched = WatchedStore()
    @StateObject private var profiles = ProfileStore()
    @StateObject private var collections = CollectionsStore()
    @StateObject private var homeCatalogSettings = HomeCatalogSettingsStore()
    @StateObject private var tmdbSettings = TMDBSettingsStore()
    @StateObject private var mdblistSettings = MDBListSettingsStore()
    @StateObject private var debrid = DebridStore()
    @StateObject private var trakt = TraktStore()
    @StateObject private var playerSettings = PlayerSettingsStore()
    @StateObject private var streamBadges = StreamBadgeStore()
    @StateObject private var plugins = PluginStore()
    @StateObject private var torrent = TorrentSettingsStore()
    @StateObject private var downloads = DownloadManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(theme.font.design)   // app-wide font family
                .environmentObject(theme)
                .environmentObject(addonManager)
                .environmentObject(progressStore)
                .environmentObject(account)
                .environmentObject(library)
                .environmentObject(watched)
                .environmentObject(profiles)
                .environmentObject(collections)
                .environmentObject(homeCatalogSettings)
                .environmentObject(tmdbSettings)
                .environmentObject(mdblistSettings)
                .environmentObject(debrid)
                .environmentObject(trakt)
                .environmentObject(playerSettings)
                .environmentObject(streamBadges)
                .environmentObject(plugins)
                .environmentObject(torrent)
                .environmentObject(downloads)
                .preferredColorScheme(.dark)
        }
    }
}

enum Route: Hashable {
    case detail(MetaItem)
    case streams(MetaItem, MetaVideo?)
    /// Source picker that plays from 0:00 (the Detail page's Start Over).
    case streamsFromStart(MetaItem, MetaVideo?)
    case collection(NuvioCollection)
    case person(id: Int, name: String)
    case tmdbCompany(id: Int, name: String)
    case catalogSeeAll(addon: InstalledAddon, catalog: ManifestCatalog, title: String)
    case discover
    case cloudLibrary
    case downloads
}

struct RootView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var account: NuvioAccountManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var watched: WatchedStore
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var collections: CollectionsStore
    @EnvironmentObject private var homeCatalogSettings: HomeCatalogSettingsStore
    @EnvironmentObject private var trakt: TraktStore
    @EnvironmentObject private var playerSettings: PlayerSettingsStore
    @EnvironmentObject private var streamBadges: StreamBadgeStore
    @EnvironmentObject private var tmdbSettings: TMDBSettingsStore
    @EnvironmentObject private var debrid: DebridStore
    @EnvironmentObject private var plugins: PluginStore
    @EnvironmentObject private var torrent: TorrentSettingsStore

    // One navigation stack per tab (tvOS expects TabView at the top level with
    // an independent NavigationStack inside each tab; a shared stack under one
    // NavigationStack makes the tab bar hard to reach and focus feel stuck).
    @State private var homePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    // Persisted here (not inside HomeView) so switching tabs and coming back
    // doesn't rebuild it and re-trigger the catalog load / loading spinner.
    @StateObject private var homeViewModel = HomeViewModel()
    // Persisted here (not inside SearchView) so leaving the Search tab and
    // coming back keeps the query and results instead of clearing them.
    @StateObject private var searchViewModel = SearchViewModel()
    @State private var playback: PlaybackRequest?
    @State private var sync: NuvioSyncManager?
    @State private var showProfileGate = false
    @State private var selectedTab = 0
    /// When Home last popped back from a pushed screen — used to swallow the
    /// stray Menu that otherwise opens the sidebar right after backing out.
    @State private var lastHomePopAt: Date?
    @FocusState private var sidebarFocus: Int?
    /// The sidebar is briefly non-focusable at launch so initial focus lands in
    /// the CONTENT (the APK boots with the sidebar collapsed and a card focused).
    @State private var sidebarEnabled = false

    var body: some View {
        content
            .onOpenURL { handleDeepLink($0) }
            .onAppear {
                NSLog("[NuvioPlayer] RootView content onAppear")
                startPlayerDemoIfRequested()
                startDetailDemoIfRequested()
            }
            .task {
                if sync == nil {
                    // Finishing a title records it in watched history.
                    progressStore.onFinished = { [weak watched] meta, video in
                        watched?.mark(meta: meta, video: video)
                    }
                    sync = NuvioSyncManager(
                        account: account,
                        addonManager: addonManager,
                        progressStore: progressStore,
                        libraryStore: library,
                        watchedStore: watched,
                        profileStore: profiles,
                        collectionsStore: collections,
                        homeCatalogSettings: homeCatalogSettings,
                        streamBadges: streamBadges,
                        playerSettings: playerSettings,
                        tmdbSettings: tmdbSettings,
                        themeManager: theme,
                        debridStore: debrid,
                        pluginStore: plugins,
                        torrentSettings: torrent
                    )
                    sync?.enrichContinueWatchingEnabled = { [tmdbSettings] in
                        tmdbSettings.settings.enrichContinueWatching
                    }
                    // "Who's watching?" gate on cold launch when 2+ profiles.
                    // Skipped in the demo modes so the screen isn't covered.
                    let args = ProcessInfo.processInfo.arguments
                    let demoArgs = ["-detailDemo", "-homeDemo", "-settingsDemo", "-searchDemo", "-libraryDemo", "-discoverDemo", "-traktQRDemo", "-accountDemo"]
                    let demoMode = demoArgs.contains { args.contains($0) }
                    showProfileGate = profiles.profiles.count >= 2 && !demoMode
                    if args.contains("-settingsDemo") { selectedTab = 3 }
                    if args.contains("-searchDemo") { selectedTab = 1 }
                    if args.contains("-libraryDemo") { selectedTab = 2 }
                    if args.contains("-discoverDemo") {
                        selectedTab = 1
                        searchPath.append(Route.discover)
                    }
                }
            }
            .fullScreenCover(isPresented: $showProfileGate) {
                // The gate now only SELECTS a profile; account + Manage Profiles
                // live in Settings → Account.
                ProfileGateView(
                    onSelected: {
                        showProfileGate = false
                        deferSidebarAfterProfileGate()
                    }
                )
                .environmentObject(theme)
                .environmentObject(profiles)
                .environmentObject(account)
            }
    }

    /// The sidebar's cold-launch fallback timers (3s in SidebarNav, 800ms from
    /// Home's onContentReady) keep running while the profile gate covers the
    /// screen, so by the time the user finishes picking a profile — which
    /// usually takes longer than that — `sidebarEnabled` is often already
    /// true. Without this, the instant the gate dismisses the focus engine
    /// lands on the nearest focusable view for the newly-revealed screen,
    /// which is the sidebar rail, popping it open instead of landing on Home.
    /// Briefly disable it again and re-enable after a beat, same pattern as
    /// the cold-launch path, so focus goes to Home's content first.
    private func deferSidebarAfterProfileGate() {
        sidebarEnabled = false
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            sidebarEnabled = true
        }
    }

    /// Dev-only: `-playerDemo` opens the player with Apple's public HLS test
    /// stream (`-playerDemoMKV` uses an MKV sample to exercise the FFmpeg
    /// engine) so playback UI can be verified without a stream addon.
    private func startPlayerDemoIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        let wantsMKV = args.contains("-playerDemoMKV")
        guard wantsMKV || args.contains("-playerDemo") else { return }
        let meta = MetaItem(
            id: "tt0111161", type: "movie", name: wantsMKV ? "Demo Stream (MKV)" : "Demo Stream (HLS)"
        )
        let stream = Stream(
            name: wantsMKV ? "MKV Sample\n1080p" : "Apple HLS\n1080p",
            title: wantsMKV ? "Big Buck Bunny MKV sample" : "BipBop advanced fMP4 example",
            description: nil,
            url: wantsMKV
                ? "https://test-videos.co.uk/vids/bigbuckbunny/mkv/1080/Big_Buck_Bunny_1080_10s_5MB.mkv"
                : "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8",
            infoHash: nil, behaviorHints: nil
        )
        playback = PlaybackRequest(
            meta: meta, video: nil,
            entry: StreamEntry(addonName: "Demo", stream: stream),
            allEntries: [], resumePosition: nil
        )
    }

    /// Dev-only: `-detailDemo` jumps straight to a Detail screen for a known
    /// title so TMDB/Trakt enrichment (cast, trailers, more-like-this, comments)
    /// can be verified without navigating there by remote.
    private func startDetailDemoIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-detailDemo") else { return }
        let meta = MetaItem(id: "tt0111161", type: "movie", name: "The Shawshank Redemption")
        if homePath.isEmpty { homePath.append(Route.detail(meta)) }
    }

    private var content: some View {
        // Dev-only: `-settingsDemo` renders Settings full-screen (no sidebar) so
        // the settings chrome can be screenshotted cleanly in the sim.
        if ProcessInfo.processInfo.arguments.contains("-settingsDemo") {
            return AnyView(
                SettingsView()
                    .background(theme.palette.background.ignoresSafeArea())
            )
        }
        if ProcessInfo.processInfo.arguments.contains("-accountDemo") {
            return AnyView(
                ZStack { theme.palette.background.ignoresSafeArea(); AccountView() }
            )
        }
        if ProcessInfo.processInfo.arguments.contains("-traktQRDemo") {
            return AnyView(
                ZStack {
                    theme.palette.background.ignoresSafeArea()
                    TraktConnectPage(
                        code: TraktDeviceCode(deviceCode: "d", userCode: "AB12CD34",
                                              verificationURL: "https://trakt.tv/activate",
                                              interval: 5, expiresIn: 600),
                        expiresAt: Date().addingTimeInterval(600)
                    )
                }
                .environmentObject(theme)
            )
        }
        return AnyView(mainContent)
    }

    /// Whether the current tab is at its root grid (no pushed screen). When a
    /// Detail/Streams/etc. is pushed, the sidebar hides so that screen is
    /// full-bleed, exactly like the APK.
    private var showSidebar: Bool {
        switch selectedTab {
        case 0: return homePath.isEmpty
        case 1: return searchPath.isEmpty
        case 2: return libraryPath.isEmpty
        default: return true   // Settings keeps the rail
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarNav(selected: $selectedTab, focusBinding: $sidebarFocus,
                           onProfileTap: { showProfileGate = true },
                           onTabSelected: { newTab in selectTab(newTab) })
                    .focusSection()
                    .disabled(!sidebarEnabled)
                    // Back while IN the sidebar collapses it into content
                    // instead of falling through to the system (which quit the
                    // app). Exit the app with the Siri remote's TV/Home button.
                    // NOT the same helper as picking a tab: nothing is being
                    // freshly mounted here (you're just closing the panel on
                    // the tab you're already on), so this always uses the fast
                    // fixed-delay re-enable — never waits on onContentReady,
                    // which wouldn't fire again since Home isn't reloading.
                    .onExitCommand { collapseSidebarFromExit() }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    // The sidebar stays non-focusable until Home has content to
                    // hold initial focus (onContentReady) — otherwise the app
                    // boots with the sidebar expanded over an empty screen. The
                    // timer is only a fallback if Home never loads (or another
                    // tab is the demo entry point).
                    .task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        sidebarEnabled = true
                    }
            }

            contentColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    // Dim the content while the sidebar is expanded/focused (APK
                    // behavior). The dim STARTS at the sidebar's own tone right
                    // at the seam and eases into the dim over the first sliver,
                    // so there's no hard bright/dark two-tone line at the edge.
                    // Always mounted with an animated opacity (not an insert
                    // transition) so it fades in IN LOCKSTEP with the sidebar's
                    // width expansion instead of popping in ahead of it.
                    LinearGradient(
                        stops: [
                            .init(color: theme.palette.backgroundElevated, location: 0),
                            .init(color: .black.opacity(0.55), location: 0.09),
                            .init(color: .black.opacity(0.55), location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(sidebarFocus != nil && showSidebar ? 1 : 0)
                }
                .focusSection()
        }
        // Matches SidebarNav's own expand spring so the width change, the
        // content reflow, and the dim all move together as one motion.
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showSidebar)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: sidebarFocus != nil)
        .background(theme.palette.background)
        .fullScreenCover(item: $playback) { request in
            PlayerScreen(
                request: request,
                addonManager: addonManager,
                progressStore: progressStore,
                playerSettings: playerSettings.settings
            ) {
                playback = nil
            }
        }
        .onChange(of: playback?.id) { _, _ in scrobbleForPlaybackChange() }
    }

    /// Handles tapping a sidebar tab. Two things happen together:
    /// 1. Clear `sidebarFocus` — this collapses the panel (expanded and the dim
    ///    both key off it) and stops the still-set focus state from yanking
    ///    focus back to the sidebar when it re-enables. Clearing it ALONE just
    ///    re-lands focus on the nearest sidebar item (an icon / the profile
    ///    button), so also:
    /// 2. Make the whole sidebar momentarily unfocusable, so the focus engine
    ///    is forced onto the only remaining candidates — the tab's content.
    ///
    /// `newTab` arrives BEFORE `selectedTab` is mutated (SidebarNav fires this
    /// first), so `selectedTab` here still holds the tab we're coming FROM —
    /// that's what lets us tell a genuine tab change apart from re-tapping the
    /// tab already on screen (see the comment below on why that distinction
    /// matters).
    private func selectTab(_ newTab: Int) {
        let enteringHomeFresh = selectedTab != 0 && newTab == 0
        selectedTab = newTab
        sidebarFocus = nil
        sidebarEnabled = false

        // Switching TO Home FROM another tab rebuilds HomeView from scratch
        // (the switch in `selectedContent` tears it down when you're on
        // another tab), and its rows/hero backdrop can take a beat longer to
        // lay out and become focusable than a blind fixed-delay guess —
        // especially right after a full rebuild. If a timer re-enabled the
        // sidebar before Home's content is actually focusable, the sidebar is
        // the only focusable thing left and reclaims focus.
        //
        // Home already reports real readiness via `onContentReady` (fired
        // after its reload completes, with its own grace period) — so ONLY
        // for a genuine transition into Home, skip the timer and let that be
        // the sole re-enabler.
        //
        // Critically, this must NOT apply when Home was already on screen
        // (e.g. re-tapping the Home icon just to close the panel): HomeView
        // isn't reloading in that case, so `onContentReady` will never fire
        // again and `sidebarEnabled` would be stuck `false` forever — the
        // sidebar would become permanently unreachable. That's why this reads
        // `enteringHomeFresh`, captured before the mutation above, rather than
        // just checking `selectedTab == 0`.
        guard enteringHomeFresh else {
            scheduleSidebarReenable()
            return
        }
    }

    /// Closes the panel when Back is pressed WHILE IT'S the one focused —
    /// i.e. you opened it but didn't pick anything. No tab change happens
    /// here and nothing is being freshly mounted, so this always uses the
    /// fast fixed-delay re-enable regardless of which tab is active — it must
    /// NOT defer to Home's `onContentReady`, which won't fire again since
    /// nothing is reloading (this was the bug behind "I can no longer get
    /// into the side panel" after a few Back presses: relying on Home's
    /// reload signal here latched `sidebarEnabled` false with nothing left to
    /// ever flip it back true).
    private func collapseSidebarFromExit() {
        sidebarFocus = nil
        sidebarEnabled = false
        scheduleSidebarReenable()
    }

    private func scheduleSidebarReenable() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            sidebarEnabled = true
        }
    }

    /// The sidebar-opening Back handler is attached to each tab's ROOT screen
    /// (see `selectedContent`), NOT here — wrapping the whole NavigationStack
    /// made `onExitCommand` swallow Back at every depth, so a pushed screen
    /// (e.g. a detail opened from Discovery) could never pop.
    private var contentColumn: some View {
        selectedContent
    }

    /// The screen for the selected sidebar tab, each in its own NavigationStack
    /// so per-tab back-stacks stay independent.
    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case 1:
            NavigationStack(path: $searchPath) {
                SearchView(
                    viewModel: searchViewModel,
                    onSelect: { searchPath.append(Route.detail($0)) },
                    onOpenDiscover: { searchPath.append(Route.discover) }
                )
                // Back at the tab ROOT opens the sidebar; when a screen is
                // pushed, focus is in that screen (not here) so the
                // NavigationStack pops instead.
                .onExitCommand { sidebarFocus = 1 }
                .navigationDestination(for: Route.self) { destination(for: $0, path: $searchPath) }
            }
        case 2:
            NavigationStack(path: $libraryPath) {
                LibraryView(
                    onSelect: { libraryPath.append(Route.detail($0)) },
                    onOpenCloud: { libraryPath.append(Route.cloudLibrary) },
                    onOpenDownloads: { libraryPath.append(Route.downloads) }
                )
                    .onExitCommand { sidebarFocus = 2 }
                    .navigationDestination(for: Route.self) { destination(for: $0, path: $libraryPath) }
            }
        case 3:
            SettingsView()
                .onExitCommand { sidebarFocus = 3 }
        default:
            NavigationStack(path: $homePath) {
                HomeView(
                    viewModel: homeViewModel,
                    onSelect: { homePath.append(Route.detail($0)) },
                    onResume: { resume($0) },
                    onResumeFromStart: { resume($0, fromBeginning: true) },
                    onPlayManually: { meta, video in playManually(meta, video) },
                    onOpenCollection: { homePath.append(Route.collection($0)) },
                    onSeeAll: { addon, catalog, title in
                        homePath.append(Route.catalogSeeAll(addon: addon, catalog: catalog, title: title))
                    },
                    onContentReady: {
                        // Give the freshly-loaded rows a beat to render and
                        // take initial focus before the sidebar becomes
                        // focusable, or the focus engine grabs the top-left
                        // (sidebar) and boots the app with it expanded.
                        Task {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            sidebarEnabled = true
                        }
                    }
                )
                .onExitCommand {
                    // Ignore a Menu press that lands right after popping back
                    // from a pushed screen (detail / streams). tvOS sometimes
                    // delivers a lingering second Menu to Home after the pop,
                    // which would spuriously open the sidebar.
                    if let popped = lastHomePopAt, Date().timeIntervalSince(popped) < 0.7 { return }
                    sidebarFocus = 0
                }
                .onChange(of: homePath.count) { oldCount, newCount in
                    if newCount < oldCount { lastHomePopAt = Date() }
                }
                .navigationDestination(for: Route.self) { destination(for: $0, path: $homePath) }
            }
        }
    }

    /// Shared navigation destinations. `path` is the binding for whichever
    /// tab's stack is presenting, so nested pushes stay within that tab.
    @ViewBuilder
    private func destination(for route: Route, path: Binding<NavigationPath>) -> some View {
        switch route {
        case .detail(let item):
            DetailView(
                item: item,
                onPlay: { meta, video in path.wrappedValue.append(Route.streams(meta, video)) },
                onPlayFromBeginning: { meta, video in path.wrappedValue.append(Route.streamsFromStart(meta, video)) },
                onSelectItem: { path.wrappedValue.append(Route.detail($0)) },
                onSelectPerson: { id, name in path.wrappedValue.append(Route.person(id: id, name: name)) },
                onSelectCompany: { id, name in path.wrappedValue.append(Route.tmdbCompany(id: id, name: name)) }
            )
        case .collection(let collection):
            CollectionView(collection: collection) { path.wrappedValue.append(Route.detail($0)) }
        case .person(let id, let name):
            CastDetailView(personID: id, personName: name) { path.wrappedValue.append(Route.detail($0)) }
        case .tmdbCompany(let id, let name):
            TMDBBrowseView(companyID: id, title: name) { path.wrappedValue.append(Route.detail($0)) }
        case .catalogSeeAll(let addon, let catalog, let title):
            CatalogSeeAllView(addon: addon, catalog: catalog, title: title) { path.wrappedValue.append(Route.detail($0)) }
        case .discover:
            DiscoverView { path.wrappedValue.append(Route.detail($0)) }
        case .cloudLibrary:
            CloudLibraryView { meta, entry in
                startPlayback(PlaybackRequest(
                    meta: meta, video: nil, entry: entry,
                    allEntries: [entry], resumePosition: nil
                ))
            }
        case .downloads:
            DownloadsView { meta, entry in
                startPlayback(PlaybackRequest(
                    meta: meta, video: nil, entry: entry,
                    allEntries: [entry], resumePosition: nil
                ))
            }
        case .streams(let meta, let video):
            StreamsView(meta: meta, video: video) { entry, all in
                let key = ProgressStore.key(metaID: meta.id, video: video)
                startPlayback(PlaybackRequest(
                    meta: meta,
                    video: video,
                    entry: entry,
                    allEntries: all,
                    resumePosition: progressStore.progress(for: key)?.positionSeconds
                ))
            }
        case .streamsFromStart(let meta, let video):
            // Same picker, but playback ignores any saved progress (Start Over).
            StreamsView(meta: meta, video: video) { entry, all in
                startPlayback(PlaybackRequest(
                    meta: meta,
                    video: video,
                    entry: entry,
                    allEntries: all,
                    resumePosition: nil
                ))
            }
        }
    }

    /// Trakt scrobble on the playback lifecycle: `start` when a title begins,
    /// `stop` with the last known progress when it ends. Best-effort and
    /// gated on sign-in + the scrobble toggle; only tt… ids scrobble.
    @State private var scrobblingItem: (meta: MetaItem, video: MetaVideo?)?

    private func scrobbleForPlaybackChange() {
        guard trakt.isSignedIn, trakt.scrobbleEnabled, let token = trakt.accessToken else {
            scrobblingItem = nil
            return
        }
        if let request = playback {
            // Playback started.
            scrobblingItem = (request.meta, request.video)
            let fraction = request.resumePosition.flatMap { pos -> Double? in
                let key = ProgressStore.key(metaID: request.meta.id, video: request.video)
                guard let duration = progressStore.progress(for: key)?.durationSeconds, duration > 0 else { return nil }
                return pos / duration * 100
            } ?? 0
            Task {
                await TraktService.scrobble(
                    action: .start, imdbID: request.meta.id, type: request.meta.type,
                    season: request.video?.season, episode: request.video?.episode,
                    progress: fraction, accessToken: token
                )
            }
        } else if let item = scrobblingItem {
            // Playback ended — report final progress.
            scrobblingItem = nil
            let key = ProgressStore.key(metaID: item.meta.id, video: item.video)
            let fraction = (progressStore.progress(for: key)?.fraction ?? 0) * 100
            Task {
                await TraktService.scrobble(
                    action: .stop, imdbID: item.meta.id, type: item.meta.type,
                    season: item.video?.season, episode: item.video?.episode,
                    progress: fraction, accessToken: token
                )
            }
        }
    }

    /// Resume from Continue Watching. Items saved on this device carry the
    /// stream URL and replay directly; items pulled from the account have no
    /// URL (the backend doesn't store it), so we route to source selection.
    /// Single entry point for starting playback. External-app engine hands
    /// the stream straight to the chosen player (Infuse etc.) instead of
    /// opening Nuvio's own player; if the chosen app was uninstalled, any
    /// other installed one is used; none installed → play internally.
    private func startPlayback(_ request: PlaybackRequest) {
        if playerSettings.settings.playerEngine == .external,
           let urlString = request.entry.stream.url {
            let chosen = ExternalPlayers.player(id: playerSettings.settings.externalPlayerID)
            let target = (chosen?.isInstalled == true ? chosen : nil) ?? ExternalPlayers.installed.first
            if let target {
                if playerSettings.settings.externalPlayerForwardSubtitles {
                    // Fetch a preferred-language subtitle, then hand off (async).
                    Task {
                        let sub = await externalSubtitleURL(for: request)
                        target.open(streamURL: urlString, subtitleURL: sub)
                    }
                } else {
                    target.open(streamURL: urlString)
                }
                return
            }
        }
        playback = request
    }

    /// Best subtitle URL from the installed subtitle addons for this playback,
    /// preferring the user's subtitle language. nil when none is found.
    private func externalSubtitleURL(for request: PlaybackRequest) async -> String? {
        let providers = addonManager.subtitleAddons
        guard !providers.isEmpty else { return nil }
        let id = request.video?.id ?? request.meta.id
        let type = request.meta.type
        let preferred = playerSettings.settings.preferredSubtitleLanguage.lowercased()
        var firstAny: String?
        for addon in providers {
            let subs = (try? await StremioAPI.subtitles(addon: addon, type: type, id: id)) ?? []
            if firstAny == nil { firstAny = subs.first?.url }
            if !preferred.isEmpty,
               let match = subs.first(where: { ($0.lang ?? "").lowercased().hasPrefix(preferred) }) {
                return match.url
            }
        }
        return firstAny
    }

    /// Route an incoming `nuvio://` / `stremio://` deep link.
    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLinkService.parse(url) else { return }
        switch link {
        case .meta(let type, let id):
            // Open the title on the Home tab. DetailView fetches full meta +
            // canonicalizes tmdb→tt from this id.
            let meta = MetaItem(id: id, type: type, name: "")
            selectedTab = 0
            homePath.append(Route.detail(meta))
        case .addonInstall(let manifestURL):
            Task { try? await addonManager.install(manifestURL: manifestURL) }
        }
    }

    private func resume(_ progress: WatchProgress, fromBeginning: Bool = false) {
        Task { await resumeResolved(progress, fromBeginning: fromBeginning) }
    }

    /// Resolve a `tmdb:<n>` meta/episode identity to canonical IMDb `tt` ids so
    /// Cinemeta/Torrentio can serve it. Returns the pair unchanged when it's
    /// not a tmdb id or the lookup fails. Shared by every Continue Watching /
    /// catalog entry point that bypasses DetailView's own resolve.
    @MainActor
    private func canonicalIdentity(_ meta: MetaItem, _ video: MetaVideo?) async -> (MetaItem, MetaVideo?) {
        guard meta.id.hasPrefix("tmdb:"), let n = Int(meta.id.dropFirst("tmdb:".count)),
              let tt = await TMDBService.imdbID(tmdbID: n, isMovie: meta.type != "series")
        else { return (meta, video) }
        let newMeta = MetaItem(
            id: tt, type: meta.type, name: meta.name,
            poster: meta.poster, background: meta.background, logo: meta.logo
        )
        let newVideo = video.map { v -> MetaVideo in
            let eid = (v.season != nil && v.episode != nil) ? "\(tt):\(v.season!):\(v.episode!)" : tt
            return MetaVideo(id: eid, title: v.title, season: v.season, episode: v.episode)
        }
        return (newMeta, newVideo)
    }

    /// Route to the Sources page, resolving a tmdb: identity first.
    private func playManually(_ meta: MetaItem, _ video: MetaVideo?) {
        Task {
            let (m, v) = await canonicalIdentity(meta, video)
            homePath.append(Route.streams(m, v))
        }
    }

    /// Continue Watching resume. TMDB-sourced items are stored as `tmdb:<n>`
    /// (and episodes as `tmdb:<n>:<s>:<e>`), but Cinemeta and Torrentio only
    /// speak IMDb `tt` ids — so resuming one directly found no metadata and no
    /// streams (the "metadata not found" a show hit that had never been opened
    /// through its Detail page, which is where this same resolve normally
    /// happens). Canonicalize to the `tt` id first, then migrate the stored
    /// entry so the card doesn't fork into a duplicate under the new key.
    @MainActor
    private func resumeResolved(_ progress: WatchProgress, fromBeginning: Bool) async {
        var metaID = progress.metaID
        // TMDB-sourced ids can't be served by Cinemeta/Torrentio — resolve to
        // the IMDb tt id (DetailView does the same).
        if metaID.hasPrefix("tmdb:"), let n = Int(metaID.dropFirst("tmdb:".count)),
           let tt = await TMDBService.imdbID(tmdbID: n, isMovie: progress.type != "series") {
            metaID = tt
        }

        // Reconstruct the CANONICAL Stremio episode id (`showId:season:episode`)
        // from the parts rather than trusting `progress.id`. Synced entries key
        // episodes by the backend's `video_id`, which falls back to the bare
        // SHOW id when the backend didn't send one — so resuming a synced
        // episode used to fetch show-level streams (none for a series) and fail
        // with "no sources", while opening via Details (which builds the id
        // correctly) worked. Only for tt-based shows; leave exotic id schemes
        // (kitsu: etc.) and movies alone.
        var episodeID = progress.id
        if metaID.hasPrefix("tt"), let season = progress.season, let episode = progress.episode {
            episodeID = "\(metaID):\(season):\(episode)"
        } else if metaID != progress.metaID {
            // tmdb → tt movie (no episode): the id is just the show/movie id.
            episodeID = metaID
        }

        // Migrate the stored entry if the identity changed, so the corrected
        // key doesn't fork a duplicate Continue Watching card.
        if episodeID != progress.id || metaID != progress.metaID {
            progressStore.recanonicalize(oldID: progress.id, newID: episodeID, newMetaID: metaID)
        }

        let meta = MetaItem(
            id: metaID,
            type: progress.type,
            name: progress.name,
            poster: progress.poster,
            background: progress.background,
            logo: progress.logo
        )
        // Rebuild the episode identity so progress keeps saving under the
        // episode key instead of forking a second entry under the show.
        let video: MetaVideo? = progress.season != nil || progress.episode != nil
            ? MetaVideo(
                id: episodeID,
                title: progress.episodeTitle,
                season: progress.season,
                episode: progress.episode
            )
            : nil
        guard let url = progress.streamURL else {
            homePath.append(Route.streams(meta, video))
            return
        }
        let stream = Stream(
            name: "Resume",
            title: nil,
            description: nil,
            url: url,
            infoHash: nil,
            behaviorHints: nil
        )
        startPlayback(PlaybackRequest(
            meta: meta,
            video: video,
            entry: StreamEntry(addonName: "Continue Watching", stream: stream),
            allEntries: [],
            resumePosition: fromBeginning ? 0 : progress.positionSeconds
        ))
    }
}
