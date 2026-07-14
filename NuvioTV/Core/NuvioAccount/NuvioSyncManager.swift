import Combine
import Foundation

/// Two-way sync of the account's data with the Nuvio Supabase backend.
///
/// v1 covers the two local stores that already exist on tvOS: installed addons
/// and watch progress. On sign-in it pulls remote → local, then pushes local →
/// remote so both sides converge; afterwards it pushes on local changes.
///
/// All calls carry the login Bearer token (sync RPCs are `SECURITY DEFINER`
/// and enforce `auth.uid()` server-side). RPC names / payloads mirror the
/// Android `AddonSyncService` and `WatchProgressSyncService`.
@MainActor
final class NuvioSyncManager: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncError: String?

    private let account: NuvioAccountManager
    private let addonManager: AddonManager
    private let progressStore: ProgressStore
    private let libraryStore: LibraryStore
    private let watchedStore: WatchedStore
    private let profileStore: ProfileStore
    private let collectionsStore: CollectionsStore
    private let homeCatalogSettings: HomeCatalogSettingsStore
    private let streamBadges: StreamBadgeStore?
    /// App-preference stores synced together as one own-feature blob
    /// (`nuvio_tvos_preferences`): player, TMDB, and theme settings.
    private let playerSettings: PlayerSettingsStore?
    private let tmdbSettings: TMDBSettingsStore?
    private let themeManager: ThemeManager?
    private let debridStore: DebridStore?
    private let pluginStore: PluginStore?
    private let torrentSettings: TorrentSettingsStore?
    /// Reads the "Enrich Continue Watching" TMDB setting (the store lives
    /// outside this manager). nil → enrich (default).
    var enrichContinueWatchingEnabled: (() -> Bool)?

    private var cancellables = Set<AnyCancellable>()
    private var pushAddonsTask: Task<Void, Never>?
    private var pushLibraryTask: Task<Void, Never>?
    private var pushWatchedTask: Task<Void, Never>?
    private var pushProfilesTask: Task<Void, Never>?
    private var pushCollectionsTask: Task<Void, Never>?
    private var pushHomeCatalogTask: Task<Void, Never>?
    private var pushBadgeSettingsTask: Task<Void, Never>?
    private var pushAppPreferencesTask: Task<Void, Never>?
    private var avatarCatalogCache: [AvatarCatalogItem] = []
    private var wasSignedIn = false

    /// The active profile scopes all personal-data sync. Addons stay global
    /// (profile 1) so the same sources are available on every profile.
    private var pid: Int { profileStore.activeProfileID }

    /// Stable per-device id so the backend can avoid echoing our own writes.
    private let clientID: String = {
        let key = "nuvio.sync.client.v1"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config)
    }()

    private enum RPC {
        static func url(_ name: String) -> String { "/rest/v1/rpc/\(name)" }
        static let pushAddons = "sync_push_addons"
        static let pushWatchProgress = "sync_push_watch_progress"
        static let pullWatchProgress = "sync_pull_watch_progress"
        static let deleteWatchProgress = "sync_delete_watch_progress"
        static let pushLibrary = "sync_push_library"
        static let pullLibrary = "sync_pull_library"
        static let pushWatchedItems = "sync_push_watched_items"
        static let pullWatchedItems = "sync_pull_watched_items"
        static let pushProfiles = "sync_push_profiles"
        static let pullProfiles = "sync_pull_profiles"
        static let pullProfileLocks = "sync_pull_profile_locks"
        static let setProfilePin = "set_profile_pin"
        static let verifyProfilePin = "verify_profile_pin"
        static let clearProfilePin = "clear_profile_pin"
        static let pushCollections = "sync_push_collections"
        static let pullCollections = "sync_pull_collections"
        static let pushHomeCatalogSettings = "sync_push_home_catalog_settings"
        static let pullHomeCatalogSettings = "sync_pull_home_catalog_settings"
        static let pushProfileSettingsBlob = "sync_push_profile_settings_blob"
        static let pullProfileSettingsBlob = "sync_pull_profile_settings_blob"
    }

    /// Platform tag the Android TV app uses for the profile-settings blob —
    /// badge configs (Badger/Fusion) live inside that blob, so we read/write
    /// the same rows.
    private static let settingsBlobPlatform = "tv"

    /// Platform tags for home catalog settings rows (mirrors Android).
    private enum HomeCatalogPlatform {
        static let shared = "home_catalog_shared"
        static let legacy = ["tv", "mobile"]
    }

    init(
        account: NuvioAccountManager,
        addonManager: AddonManager,
        progressStore: ProgressStore,
        libraryStore: LibraryStore,
        watchedStore: WatchedStore,
        profileStore: ProfileStore,
        collectionsStore: CollectionsStore,
        homeCatalogSettings: HomeCatalogSettingsStore,
        streamBadges: StreamBadgeStore? = nil,
        playerSettings: PlayerSettingsStore? = nil,
        tmdbSettings: TMDBSettingsStore? = nil,
        themeManager: ThemeManager? = nil,
        debridStore: DebridStore? = nil,
        pluginStore: PluginStore? = nil,
        torrentSettings: TorrentSettingsStore? = nil
    ) {
        self.account = account
        self.addonManager = addonManager
        self.progressStore = progressStore
        self.libraryStore = libraryStore
        self.watchedStore = watchedStore
        self.profileStore = profileStore
        self.collectionsStore = collectionsStore
        self.homeCatalogSettings = homeCatalogSettings
        self.streamBadges = streamBadges
        self.playerSettings = playerSettings
        self.tmdbSettings = tmdbSettings
        self.themeManager = themeManager
        self.debridStore = debridStore
        self.pluginStore = pluginStore
        self.torrentSettings = torrentSettings

        // Sync whenever we transition into a signed-in state.
        account.$authState
            .sink { [weak self] state in self?.handleAuthChange(state) }
            .store(in: &cancellables)

        // Push local changes upward (debounced for addons/library/watched/profiles, immediate for progress).
        addonManager.onLocalChange = { [weak self] in self?.scheduleAddonPush() }
        // "Refresh Add-ons" → PULL ONLY. Bring in addons added on the account
        // elsewhere; never push here. A push replaces the account's addon list
        // with the local one, so if the pull couldn't materialize an addon (a
        // manifest that failed to fetch), pushing would delete it from the
        // account. Device→account changes still sync via onLocalChange.
        addonManager.onSyncRequested = { [weak self] in
            guard let self, account.accessToken != nil else { return }
            try? await pullAddons()
        }
        progressStore.onLocalUpdate = { [weak self] in self?.pushWatchProgress() }
        progressStore.onRemove = { [weak self] keys in self?.deleteWatchProgress(keys: keys) }
        libraryStore.onLocalChange = { [weak self] in self?.scheduleLibraryPush() }
        watchedStore.onLocalChange = { [weak self] in self?.scheduleWatchedPush() }
        profileStore.onLocalChange = { [weak self] in self?.scheduleProfilePush() }
        profileStore.onSwitch = { [weak self] id in self?.handleProfileSwitch(id) }
        collectionsStore.onLocalChange = { [weak self] in
            self?.scheduleCollectionsPush()
            // Collections appear as home rows, so their add/remove also
            // changes the catalog-settings payload.
            self?.scheduleHomeCatalogPush()
        }
        homeCatalogSettings.onLocalChange = { [weak self] in self?.scheduleHomeCatalogPush() }
        streamBadges?.onLocalChange = { [weak self] in self?.scheduleBadgeSettingsPush() }
        streamBadges?.remoteSync = { [weak self] in
            await self?.pullBadgeSettings() ?? "Account sync isn't ready yet"
        }
        // App preferences (player / TMDB / theme) share one own-feature blob.
        playerSettings?.onLocalChange = { [weak self] in self?.scheduleAppPreferencesPush() }
        tmdbSettings?.onLocalChange = { [weak self] in self?.scheduleAppPreferencesPush() }
        themeManager?.onLocalChange = { [weak self] in self?.scheduleAppPreferencesPush() }
        debridStore?.onLocalChange = { [weak self] in self?.scheduleAppPreferencesPush() }
        pluginStore?.onLocalChange = { [weak self] in self?.scheduleAppPreferencesPush() }
        torrentSettings?.onLocalChange = { [weak self] in self?.scheduleAppPreferencesPush() }
        homeCatalogSettings.onPresentationChange = { [weak self] in self?.scheduleAppPreferencesPush() }

        // Authed operations the profile UI needs (require the access token).
        profileStore.avatarCatalogLoader = { [weak self] in
            (try? await self?.loadAvatarCatalog()) ?? []
        }
        profileStore.pinVerifier = { [weak self] id, pin in
            (try? await self?.verifyProfilePin(id: id, pin: pin))
                ?? PinVerifyOutcome(unlocked: false, retryAfterSeconds: 0)
        }
        profileStore.pinSetter = { [weak self] id, pin, current in
            await self?.setProfilePin(id: id, pin: pin, currentPin: current) ?? .failure("Not signed in.")
        }
        profileStore.pinClearer = { [weak self] id, current in
            (try? await self?.clearProfilePin(id: id, currentPin: current)) ?? false
        }

        // Scope local stores to the persisted active profile at startup (no-op
        // for profile 1); works offline before any sync happens.
        applyActiveProfileScope()
    }

    private func handleAuthChange(_ state: NuvioAuthState) {
        switch state {
        case .signedIn:
            profileStore.accountAvailable = true
            guard !wasSignedIn else { return }
            wasSignedIn = true
            Task { await syncNow() }
        case .signedOut:
            wasSignedIn = false
            profileStore.accountAvailable = false
        case .loading:
            break
        }
    }

    // MARK: - Full sync

    func syncNow() async {
        guard account.accessToken != nil else { return }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }
        do {
            // Learn the profile list first, then scope the personal-data stores
            // to the active profile before pulling its data.
            try await pullProfiles()
            applyActiveProfileScope()
            // Pull first so remote wins on first login, then push the merged set.
            try await pullAddons()
            try await pullWatchProgress()
            try await pullLibrary()
            try await pullWatchedItems()
            try await pullCollections()
            try await pullHomeCatalogSettings()
            await pullBadgeSettings()   // best-effort; badge chips are cosmetic
            await pullAppPreferences()  // best-effort; player/TMDB/theme prefs
            try await pushProfiles()
            try await pushAddons()
            try await pushWatchProgressAll()
            try await pushLibrary()
            try await pushWatchedItems()
            try await pushCollections()
            try await pushHomeCatalogSettings()
            await pushAppPreferences()
        } catch {
            lastSyncError = describe(error)
        }
    }

    private func applyActiveProfileScope() {
        progressStore.setProfile(pid)
        libraryStore.setProfile(pid)
        watchedStore.setProfile(pid)
        collectionsStore.setProfile(pid)
        homeCatalogSettings.setProfile(pid)
    }

    // MARK: - Addons

    private func scheduleAddonPush() {
        pushAddonsTask?.cancel()
        pushAddonsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            try? await self?.pushAddons()
        }
    }

    private func pushAddons() async throws {
        guard account.accessToken != nil else { return }
        let entries: [[String: Any]] = addonManager.addons.enumerated().map { index, addon in
            var obj: [String: Any] = [
                "url": addon.manifestURL,
                "sort_order": index,
                "enabled": true
            ]
            if !addon.manifest.name.isEmpty { obj["name"] = addon.manifest.name }
            return obj
        }
        let body: [String: Any] = [
            "p_addons": entries,
            "p_profile_id": 1,
            "p_origin_client_id": clientID
        ]
        _ = try await authedPost(RPC.url(RPC.pushAddons), body: body)
    }

    private func pullAddons() async throws {
        guard let userID = account.currentUserID else { return }
        // PostgREST select, filtered to our rows for the default profile.
        let path = "/rest/v1/addons?user_id=eq.\(userID)&profile_id=eq.1&select=url,sort_order,enabled,name"
        let data = try await authedGet(path)
        let rows = try JSONDecoder().decode([SupabaseAddon].self, from: data)
        let orderedURLs = rows.sorted { $0.sortOrder < $1.sortOrder }.map(\.url)
        guard !orderedURLs.isEmpty else { return }
        await addonManager.applyRemote(urls: orderedURLs)
    }

    // MARK: - Watch progress

    private func pushWatchProgress() {
        Task { [weak self] in try? await self?.pushWatchProgressAll() }
    }

    /// Delete watch-progress entries server-side so a removed Continue Watching
    /// title doesn't come back on the next pull. Keys are the progress keys
    /// (video_id / progress_key) captured before local deletion.
    private func deleteWatchProgress(keys: [String]) {
        let trimmed = keys.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty, account.accessToken != nil else { return }
        let profileID = pid
        Task { [weak self] in
            guard let self else { return }
            let body: [String: Any] = [
                "p_keys": trimmed,
                "p_profile_id": profileID,
                "p_origin_client_id": clientID
            ]
            _ = try? await self.authedPost(RPC.url(RPC.deleteWatchProgress), body: body)
        }
    }

    private func pushWatchProgressAll() async throws {
        guard account.accessToken != nil else { return }
        // Serialize OFF the main actor: this runs on every periodic progress
        // save during playback, and building dictionaries + JSON for the whole
        // history on main was a measurable playback hiccup.
        let snapshot = progressStore.allForSync()
        let profileID = pid
        let client = clientID
        let payload = await Task.detached(priority: .utility) {
            Self.encodeWatchProgressBody(snapshot, pid: profileID, clientID: client)
        }.value
        guard let payload else { return }
        _ = try await send(endpoint: RPC.url(RPC.pushWatchProgress), method: "POST", body: payload)
    }

    private nonisolated static func encodeWatchProgressBody(
        _ items: [WatchProgress], pid: Int, clientID: String
    ) -> Data? {
        let entries: [[String: Any]] = items.compactMap { wp in
            guard wp.durationSeconds > 0 else { return nil }
            var obj: [String: Any] = [
                "content_id": wp.metaID,
                "content_type": wp.type,
                "video_id": wp.id,
                "position": Int((wp.positionSeconds * 1000).rounded()),
                "duration": Int((wp.durationSeconds * 1000).rounded()),
                "last_watched": Int(wp.updatedAt.timeIntervalSince1970 * 1000),
                "progress_key": wp.id
            ]
            if let season = wp.season { obj["season"] = season }
            if let episode = wp.episode { obj["episode"] = episode }
            return obj
        }
        guard !entries.isEmpty else { return nil }
        let body: [String: Any] = [
            "p_entries": entries,
            "p_profile_id": pid,
            "p_origin_client_id": clientID
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    private func pullWatchProgress() async throws {
        guard account.accessToken != nil else { return }
        let data = try await authedPost(RPC.url(RPC.pullWatchProgress), body: ["p_profile_id": pid])
        let rows = try JSONDecoder().decode([SupabaseWatchProgress].self, from: data)
        guard !rows.isEmpty else { return }

        var pulled: [WatchProgress] = rows.map { row in
            WatchProgress(
                id: row.progressKey,
                metaID: row.contentID,
                type: row.contentType,
                name: "",
                poster: nil,
                background: nil,
                logo: nil,
                season: row.season,
                episode: row.episode,
                episodeTitle: nil,
                positionSeconds: Double(row.position) / 1000.0,
                durationSeconds: Double(row.duration) / 1000.0,
                streamURL: nil,
                updatedAt: Date(timeIntervalSince1970: Double(row.lastWatched) / 1000.0)
            )
        }
        pulled = await enrichMetadata(pulled)
        progressStore.mergeRemote(pulled)
    }

    /// The backend stores no titles/artwork with progress, so pulled Continue
    /// Watching rows arrive bare. Fill them in from a meta addon (Cinemeta) so
    /// the cards render, best-effort and capped.
    private func enrichMetadata(_ entries: [WatchProgress]) async -> [WatchProgress] {
        // Gated by the "Enrich Continue Watching" setting: when off, synced
        // rows keep whatever title/art they arrived with (leaner, no extra
        // meta-addon calls). Locally-watched rows already carry name + art.
        guard enrichContinueWatchingEnabled?() ?? true else { return entries }
        // Match ProgressStore.continueWatching: any started, unfinished item is
        // visible (no lower bound), so all of them need title/artwork.
        let visible = entries.filter { $0.fraction < 0.95 }
        let ids = Array(Set(visible.map { ($0.metaID, $0.type) }.map { "\($0.0)|\($0.1)" })).prefix(30)
        var metaByID: [String: MetaItem] = [:]
        for token in ids {
            let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let addon = addonManager.metaAddon(for: parts[1], id: parts[0]) else { continue }
            if let meta = try? await StremioAPI.meta(addon: addon, type: parts[1], id: parts[0]) {
                metaByID[parts[0]] = meta
            }
        }
        guard !metaByID.isEmpty else { return entries }
        return entries.map { wp in
            guard let meta = metaByID[wp.metaID] else { return wp }
            return WatchProgress(
                id: wp.id,
                metaID: wp.metaID,
                type: wp.type,
                name: meta.name,
                poster: meta.poster,
                background: meta.background,
                logo: meta.logo,
                season: wp.season,
                episode: wp.episode,
                episodeTitle: wp.episodeTitle,
                positionSeconds: wp.positionSeconds,
                durationSeconds: wp.durationSeconds,
                streamURL: wp.streamURL,
                updatedAt: wp.updatedAt
            )
        }
    }

    // MARK: - Library

    private func scheduleLibraryPush() {
        pushLibraryTask?.cancel()
        pushLibraryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            try? await self?.pushLibrary()
        }
    }

    private func pushLibrary() async throws {
        guard account.accessToken != nil else { return }
        let items = libraryStore.allForSync()
        guard !items.isEmpty else { return }
        let entries: [[String: Any]] = items.map { item in
            var obj: [String: Any] = [
                "content_id": item.id,
                "content_type": item.type,
                "name": item.name,
                "poster_shape": item.posterShape,
                "genres": item.genres,
                "added_at": Int(item.addedAt.timeIntervalSince1970 * 1000)
            ]
            if let poster = item.poster { obj["poster"] = poster }
            if let background = item.background { obj["background"] = background }
            if let description = item.description { obj["description"] = description }
            if let releaseInfo = item.releaseInfo { obj["release_info"] = releaseInfo }
            if let rating = item.imdbRating { obj["imdb_rating"] = rating }
            if let base = item.addonBaseURL { obj["addon_base_url"] = base }
            return obj
        }
        let body: [String: Any] = [
            "p_items": entries,
            "p_profile_id": pid,
            "p_origin_client_id": clientID
        ]
        _ = try await authedPost(RPC.url(RPC.pushLibrary), body: body)
    }

    private func pullLibrary() async throws {
        guard account.accessToken != nil else { return }
        var offset = 0
        let pageSize = 500
        var collected: [SavedLibraryItem] = []
        while true {
            let data = try await authedPost(
                RPC.url(RPC.pullLibrary),
                body: ["p_profile_id": pid, "p_limit": pageSize, "p_offset": offset]
            )
            let page = try JSONDecoder().decode([SupabaseLibraryItem].self, from: data)
            collected.append(contentsOf: page.map { row in
                SavedLibraryItem(
                    id: row.contentID,
                    type: row.contentType,
                    name: row.name,
                    poster: row.poster,
                    posterShape: row.posterShape,
                    background: row.background,
                    description: row.description,
                    releaseInfo: row.releaseInfo,
                    imdbRating: row.imdbRating,
                    genres: row.genres,
                    addonBaseURL: row.addonBaseURL,
                    addedAt: Date(timeIntervalSince1970: Double(row.addedAt) / 1000.0)
                )
            })
            if page.count < pageSize { break }
            offset += pageSize
        }
        guard !collected.isEmpty else { return }
        libraryStore.mergeRemote(collected)
    }

    // MARK: - Watched items

    private func scheduleWatchedPush() {
        pushWatchedTask?.cancel()
        pushWatchedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            try? await self?.pushWatchedItems()
        }
    }

    private func pushWatchedItems() async throws {
        guard account.accessToken != nil else { return }
        let items = watchedStore.allForSync()
        guard !items.isEmpty else { return }
        let entries: [[String: Any]] = items.map { item in
            var obj: [String: Any] = [
                "content_id": item.contentID,
                "content_type": item.contentType,
                "title": item.title,
                "watched_at": Int(item.watchedAt.timeIntervalSince1970 * 1000),
                "season": item.season as Any,
                "episode": item.episode as Any
            ]
            if item.season == nil { obj["season"] = NSNull() }
            if item.episode == nil { obj["episode"] = NSNull() }
            return obj
        }
        let body: [String: Any] = [
            "p_items": entries,
            "p_profile_id": pid,
            "p_origin_client_id": clientID
        ]
        _ = try await authedPost(RPC.url(RPC.pushWatchedItems), body: body)
    }

    private func pullWatchedItems() async throws {
        guard account.accessToken != nil else { return }
        var page = 1
        let pageSize = 900
        var collected: [WatchedItem] = []
        while true {
            let data = try await authedPost(
                RPC.url(RPC.pullWatchedItems),
                body: ["p_profile_id": pid, "p_page": page, "p_page_size": pageSize]
            )
            let rows = try JSONDecoder().decode([SupabaseWatchedItem].self, from: data)
            collected.append(contentsOf: rows.map { row in
                WatchedItem(
                    contentID: row.contentID,
                    contentType: row.contentType,
                    title: row.title,
                    season: row.season,
                    episode: row.episode,
                    watchedAt: Date(timeIntervalSince1970: Double(row.watchedAt) / 1000.0)
                )
            })
            if rows.count < pageSize { break }
            page += 1
        }
        guard !collected.isEmpty else { return }
        watchedStore.mergeRemote(collected)
    }

    // MARK: - Profiles

    private func scheduleProfilePush() {
        pushProfilesTask?.cancel()
        pushProfilesTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            try? await self?.pushProfiles()
        }
    }

    private func pushProfiles() async throws {
        guard account.accessToken != nil else { return }
        let profiles = profileStore.allForSync()
        guard !profiles.isEmpty else { return }
        let entries: [[String: Any]] = profiles.map { p in
            var obj: [String: Any] = [
                "profile_index": p.id,
                "name": p.name,
                "avatar_color_hex": p.avatarColorHex,
                "uses_primary_addons": p.usesPrimaryAddons,
                "uses_primary_plugins": p.usesPrimaryPlugins
            ]
            obj["avatar_id"] = p.avatarID ?? NSNull()
            obj["avatar_url"] = p.avatarURL ?? NSNull()
            return obj
        }
        let body: [String: Any] = [
            "p_client_max_profiles": ProfileStore.maxProfiles,
            "p_profiles": entries,
            "p_origin_client_id": clientID
        ]
        _ = try await authedPost(RPC.url(RPC.pushProfiles), body: body)
    }

    private func pullProfiles() async throws {
        guard account.accessToken != nil else { return }
        let data = try await authedPost(RPC.url(RPC.pullProfiles), body: [:])
        let rows = try JSONDecoder().decode([SupabaseProfile].self, from: data)
        if !rows.isEmpty {
            profileStore.replaceRemote(rows.map { row in
                UserProfile(
                    id: row.profileIndex,
                    name: row.name,
                    avatarColorHex: row.avatarColorHex,
                    usesPrimaryAddons: row.usesPrimaryAddons,
                    usesPrimaryPlugins: row.usesPrimaryPlugins,
                    avatarID: row.avatarID,
                    avatarURL: row.avatarURL
                )
            })
        }
        // PIN lock states are a separate table; failures here are non-fatal.
        if let lockData = try? await authedPost(RPC.url(RPC.pullProfileLocks), body: [:]),
           let locks = try? JSONDecoder().decode([SupabaseProfileLockState].self, from: lockData) {
            profileStore.applyLockStates(
                Dictionary(locks.map { ($0.profileIndex, $0.pinEnabled) }, uniquingKeysWith: { $1 })
            )
        }
    }

    /// Re-scope the personal-data stores to the newly-selected profile and pull
    /// its cloud data. Local scoping happens even when signed out.
    private func handleProfileSwitch(_ id: Int) {
        progressStore.setProfile(id)
        libraryStore.setProfile(id)
        watchedStore.setProfile(id)
        collectionsStore.setProfile(id)
        homeCatalogSettings.setProfile(id)
        guard account.accessToken != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await pullWatchProgress()
                try await pullLibrary()
                try await pullWatchedItems()
                try await pullCollections()
                try await pullHomeCatalogSettings()
                await pullBadgeSettings()
                await pullAppPreferences()
            } catch {
                lastSyncError = describe(error)
            }
        }
    }

    // MARK: - Collections

    private func scheduleCollectionsPush() {
        pushCollectionsTask?.cancel()
        pushCollectionsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            try? await self?.pushCollections()
        }
    }

    private func pushCollections() async throws {
        guard account.accessToken != nil else { return }
        // The RPC replaces the whole blob; ship the JSON array as-is.
        let json = collectionsStore.exportJSON()
        let collectionsValue = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) ?? []
        let body: [String: Any] = [
            "p_profile_id": pid,
            "p_collections_json": collectionsValue,
            "p_origin_client_id": clientID
        ]
        _ = try await authedPost(RPC.url(RPC.pushCollections), body: body)
    }

    private func pullCollections() async throws {
        guard account.accessToken != nil else { return }
        let data = try await authedPost(RPC.url(RPC.pullCollections), body: ["p_profile_id": pid])
        let rows = try JSONDecoder().decode([SupabaseCollectionsBlob].self, from: data)
        guard let blob = rows.first else { return }   // no remote row: keep local
        collectionsStore.applyRemote(json: blob.collectionsJSON)
    }

    // MARK: - Home catalog settings

    private func scheduleHomeCatalogPush() {
        pushHomeCatalogTask?.cancel()
        pushHomeCatalogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            try? await self?.pushHomeCatalogSettings()
        }
    }

    private func pushHomeCatalogSettings() async throws {
        guard account.accessToken != nil else { return }
        let payload = homeCatalogSettings.exportPayload(
            addons: addonManager.catalogAddons,
            collections: collectionsStore.collections
        )
        guard let encoded = try? JSONEncoder().encode(payload),
              let localJSON = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }

        // Android merges the remote row's keys under the local payload so
        // settings other platforms store in this blob survive our push.
        var merged = localJSON
        if let remote = try? await fetchHomeCatalogBlob(platform: HomeCatalogPlatform.shared),
           let remoteJSON = try? JSONSerialization.jsonObject(with: Data(remote.settingsJSON.utf8)) as? [String: Any] {
            merged = remoteJSON.merging(localJSON) { _, local in local }
        }

        let body: [String: Any] = [
            "p_profile_id": pid,
            "p_settings_json": merged,
            "p_platform": HomeCatalogPlatform.shared,
            "p_origin_client_id": clientID
        ]
        _ = try await authedPost(RPC.url(RPC.pushHomeCatalogSettings), body: body)
    }

    private func pullHomeCatalogSettings() async throws {
        guard account.accessToken != nil else { return }
        // Prefer the shared row; fall back to newest non-empty legacy row
        // (Android clients that predate the shared platform tag).
        var best: SyncHomeCatalogPayload?
        if let blob = try? await fetchHomeCatalogBlob(platform: HomeCatalogPlatform.shared),
           let payload = decodeHomeCatalogPayload(blob), !payload.items.isEmpty {
            best = payload
        } else {
            var newest: (payload: SyncHomeCatalogPayload, updatedAt: String)?
            for platform in HomeCatalogPlatform.legacy {
                guard let blob = try? await fetchHomeCatalogBlob(platform: platform),
                      let payload = decodeHomeCatalogPayload(blob), !payload.items.isEmpty else { continue }
                let stamp = blob.updatedAt ?? ""
                if newest == nil || stamp > newest!.updatedAt {
                    newest = (payload, stamp)
                }
            }
            best = newest?.payload
        }
        guard let payload = best else { return }   // nothing remote: keep local
        homeCatalogSettings.applyRemote(payload)
    }

    private func fetchHomeCatalogBlob(platform: String) async throws -> SupabaseHomeCatalogSettingsBlob? {
        let data = try await authedPost(
            RPC.url(RPC.pullHomeCatalogSettings),
            body: ["p_profile_id": pid, "p_platform": platform]
        )
        return try JSONDecoder().decode([SupabaseHomeCatalogSettingsBlob].self, from: data).first
    }

    private func decodeHomeCatalogPayload(_ blob: SupabaseHomeCatalogSettingsBlob) -> SyncHomeCatalogPayload? {
        try? JSONDecoder().decode(SyncHomeCatalogPayload.self, from: Data(blob.settingsJSON.utf8))
    }

    // MARK: - Avatars & PIN

    private func loadAvatarCatalog() async throws -> [AvatarCatalogItem] {
        if !avatarCatalogCache.isEmpty { return avatarCatalogCache }
        guard account.accessToken != nil else { return [] }
        let data = try await authedPost(RPC.url("get_avatar_catalog"), body: [:])
        let rows = try JSONDecoder().decode([SupabaseAvatarCatalogItem].self, from: data)
        let base = NuvioConfig.avatarPublicBaseURL.hasSuffix("/")
            ? String(NuvioConfig.avatarPublicBaseURL.dropLast()) : NuvioConfig.avatarPublicBaseURL
        let catalog = rows.map { row in
            AvatarCatalogItem(
                id: row.id,
                displayName: row.displayName,
                imageURL: base + "/" + row.storagePath,
                category: row.category,
                sortOrder: row.sortOrder,
                bgColor: row.bgColor
            )
        }
        avatarCatalogCache = catalog
        return catalog
    }

    private func verifyProfilePin(id: Int, pin: String) async throws -> PinVerifyOutcome {
        let data = try await authedPost(RPC.url(RPC.verifyProfilePin), body: ["p_profile_id": id, "p_pin": pin])
        let rows = try JSONDecoder().decode([PinVerifyRow].self, from: data)
        if let row = rows.first {
            return PinVerifyOutcome(unlocked: row.unlocked, retryAfterSeconds: row.retryAfterSeconds)
        }
        return PinVerifyOutcome(unlocked: false, retryAfterSeconds: 0)
    }

    private func setProfilePin(id: Int, pin: String, currentPin: String?) async -> PinSetOutcome {
        var body: [String: Any] = ["p_profile_id": id, "p_pin": pin]
        if let currentPin, !currentPin.isEmpty { body["p_current_pin"] = currentPin }
        do {
            _ = try await authedPost(RPC.url(RPC.setProfilePin), body: body)
            return .success
        } catch NuvioAuthError.http(_, let responseBody) {
            if responseBody.localizedCaseInsensitiveContains("current pin is required") {
                return .currentPinRequired
            }
            return .failure("Couldn't set PIN.")
        } catch {
            return .failure("Couldn't set PIN.")
        }
    }

    private func clearProfilePin(id: Int, currentPin: String?) async throws -> Bool {
        var body: [String: Any] = ["p_profile_id": id]
        if let currentPin, !currentPin.isEmpty { body["p_current_pin"] = currentPin }
        _ = try await authedPost(RPC.url(RPC.clearProfilePin), body: body)
        return true
    }

    // MARK: - Networking

    // MARK: - Badge settings (profile settings blob, Android-compatible)

    /// Platform tags other Nuvio apps may have pushed their settings blob
    /// under. Badges configured in the MOBILE app (Fusion) live in that
    /// platform's blob, not the TV one — check them all, TV first.
    private static let settingsBlobPlatforms = ["tv", "mobile", "fusion", "ios", "desktop", "web"]

    /// Pull the profile settings blob(s) and apply the
    /// `stream_badge_settings` feature — the Badger/Fusion badge pack
    /// configured on any device. Returns a human-readable status for the
    /// Settings card's manual sync button.
    @discardableResult
    private func pullBadgeSettings() async -> String {
        guard let streamBadges else { return "Badge store unavailable" }
        guard account.accessToken != nil else { return "Sign in to your Nuvio account first" }
        var sawAnyBlob = false
        for platform in Self.settingsBlobPlatforms {
            guard let data = try? await authedPost(
                RPC.url(RPC.pullProfileSettingsBlob),
                body: ["p_profile_id": pid, "p_platform": platform]
            ) else { continue }
            guard let blob = Self.settingsBlob(from: data) else { continue }
            sawAnyBlob = true
            guard let features = blob["features"] as? [String: Any],
                  let badgeFeature = features["stream_badge_settings"] as? [String: Any],
                  let rulesJSON = Self.preferenceString(badgeFeature["stream_badge_rules"])
            else { continue }
            NSLog("[NuvioBadges] found badge rules in '%@' settings blob", platform)
            streamBadges.applyRemoteRules(rulesJSON)
            if streamBadges.isConfigured {
                return "Synced \(streamBadges.filterCount) badge filters (\(platform) settings)"
            }
        }
        NSLog("[NuvioBadges] no badge rules in any settings blob (sawAnyBlob=%d)", sawAnyBlob ? 1 : 0)
        return sawAnyBlob
            ? "Your account has settings, but no badge config — import one in any Nuvio app first"
            : "No synced settings found on this account"
    }

    /// Rows may arrive as an array or a bare object; settings_json may be an
    /// object or a double-encoded JSON string. Accept all of it.
    private static func settingsBlob(from data: Data) -> [String: Any]? {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let row: [String: Any]?
        if let rows = parsed as? [[String: Any]] {
            row = rows.first
        } else {
            row = parsed as? [String: Any]
        }
        guard let row else { return nil }
        if let blob = row["settings_json"] as? [String: Any] { return blob }
        if let text = row["settings_json"] as? String,
           let data = text.data(using: .utf8),
           let blob = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return blob
        }
        // Row IS the blob (RPC returned the jsonb directly).
        if row["features"] != nil { return row }
        return nil
    }

    /// A blob preference is usually {type,value}; tolerate a bare string too.
    private static func preferenceString(_ entry: Any?) -> String? {
        if let dict = entry as? [String: Any], let value = dict["value"] as? String { return value }
        return entry as? String
    }

    private func scheduleBadgeSettingsPush() {
        pushBadgeSettingsTask?.cancel()
        pushBadgeSettingsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.pushBadgeSettings()
        }
    }

    /// Push our badge config into the account. READ-MERGE-WRITE: fetch the
    /// current blob, replace only the stream_badge_settings feature, push the
    /// whole thing back — never clobbers the other features Android put there.
    private func pushBadgeSettings() async {
        guard let streamBadges, account.accessToken != nil,
              let rulesJSON = streamBadges.syncRulesJSON() else { return }

        var blob: [String: Any] = ["version": 1, "features": [String: Any]()]
        if let data = try? await authedPost(
            RPC.url(RPC.pullProfileSettingsBlob),
            body: ["p_profile_id": pid, "p_platform": Self.settingsBlobPlatform]
        ),
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let existing = rows.first?["settings_json"] as? [String: Any] {
            blob = existing
        }
        var features = blob["features"] as? [String: Any] ?? [:]
        var badgeFeature = features["stream_badge_settings"] as? [String: Any] ?? [:]
        badgeFeature["stream_badge_rules"] = ["type": "string", "value": rulesJSON]
        features["stream_badge_settings"] = badgeFeature
        blob["features"] = features
        if blob["version"] == nil { blob["version"] = 1 }

        let body: [String: Any] = [
            "p_profile_id": pid,
            "p_settings_json": blob,
            "p_platform": Self.settingsBlobPlatform,
            "p_origin_client_id": clientID,
        ]
        _ = try? await authedPost(RPC.url(RPC.pushProfileSettingsBlob), body: body)
    }

    // MARK: - App preferences (player / TMDB / theme)

    /// Own-feature key inside the profile settings blob. tvOS-specific — Android
    /// ignores it — so pushing it can never clobber the app's shared features.
    private static let appPrefsFeatureKey = "nuvio_tvos_preferences"

    /// The synced slice of local app preferences.
    private struct AppPreferencesSnapshot: Codable {
        var version = 1
        var player: PlayerSettings
        var tmdb: TMDBSettings
        var theme: ThemeSnapshot
        /// Home/Continue-Watching presentation prefs. Optional so blobs written
        /// before this field decode cleanly.
        var home: HomePresentationSnapshot?
        /// Debrid provider keys + preferred. Optional for backward-compat.
        var debrid: DebridStore.DebridSnapshot?
        /// Installed plugin repository URLs. Optional for backward-compat.
        var plugins: PluginStore.PluginSyncSnapshot?
        /// P2P / TorrServer settings. Optional for backward-compat.
        var torrent: TorrentSettings?
    }

    private func scheduleAppPreferencesPush() {
        pushAppPreferencesTask?.cancel()
        pushAppPreferencesTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.pushAppPreferences()
        }
    }

    /// Pull the tvOS preferences feature (if present) and apply it to the three
    /// stores. Best-effort: any decode failure leaves local settings untouched.
    private func pullAppPreferences() async {
        guard account.accessToken != nil,
              let playerSettings, let tmdbSettings, let themeManager else { return }
        guard let data = try? await authedPost(
            RPC.url(RPC.pullProfileSettingsBlob),
            body: ["p_profile_id": pid, "p_platform": Self.settingsBlobPlatform]
        ),
            let blob = Self.settingsBlob(from: data),
            let features = blob["features"] as? [String: Any],
            let feature = features[Self.appPrefsFeatureKey] as? [String: Any],
            let json = Self.preferenceString(feature["value"]),
            let snapshot = try? JSONDecoder().decode(
                AppPreferencesSnapshot.self, from: Data(json.utf8)
            )
        else { return }
        playerSettings.applyRemote(snapshot.player)
        tmdbSettings.applyRemote(snapshot.tmdb)
        themeManager.applyRemote(snapshot.theme)
        if let home = snapshot.home { homeCatalogSettings.applyRemotePresentation(home) }
        if let debrid = snapshot.debrid { debridStore?.applyRemote(debrid) }
        if let plugins = snapshot.plugins, let pluginStore {
            Task { await pluginStore.applyRemote(plugins) }
        }
        if let torrent = snapshot.torrent { torrentSettings?.applyRemote(torrent) }
    }

    /// READ-MERGE-WRITE: fetch the blob, replace only our own feature key, push
    /// it all back so the badge feature and Android's features survive intact.
    private func pushAppPreferences() async {
        guard account.accessToken != nil,
              let playerSettings, let tmdbSettings, let themeManager else { return }
        let snapshot = AppPreferencesSnapshot(
            player: playerSettings.settings,
            tmdb: tmdbSettings.settings,
            theme: themeManager.snapshot,
            home: homeCatalogSettings.presentationSnapshot,
            debrid: debridStore?.snapshot,
            plugins: pluginStore?.snapshot,
            torrent: torrentSettings?.settings
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }

        var blob: [String: Any] = ["version": 1, "features": [String: Any]()]
        if let existingData = try? await authedPost(
            RPC.url(RPC.pullProfileSettingsBlob),
            body: ["p_profile_id": pid, "p_platform": Self.settingsBlobPlatform]
        ),
            let rows = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]],
            let existing = rows.first?["settings_json"] as? [String: Any] {
            blob = existing
        }
        var features = blob["features"] as? [String: Any] ?? [:]
        features[Self.appPrefsFeatureKey] = ["type": "string", "value": json]
        blob["features"] = features
        if blob["version"] == nil { blob["version"] = 1 }

        let body: [String: Any] = [
            "p_profile_id": pid,
            "p_settings_json": blob,
            "p_platform": Self.settingsBlobPlatform,
            "p_origin_client_id": clientID,
        ]
        _ = try? await authedPost(RPC.url(RPC.pushProfileSettingsBlob), body: body)
    }

    private func authedPost(_ endpoint: String, body: [String: Any]) async throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: body)
        return try await send(endpoint: endpoint, method: "POST", body: payload)
    }

    private func authedGet(_ endpoint: String) async throws -> Data {
        try await send(endpoint: endpoint, method: "GET", body: nil)
    }

    private func send(endpoint: String, method: String, body: Data?, isRetry: Bool = false) async throws -> Data {
        guard let token = account.accessToken else { throw NuvioAuthError.message("Not signed in.") }
        let base = NuvioConfig.supabaseURL.hasSuffix("/")
            ? String(NuvioConfig.supabaseURL.dropLast()) : NuvioConfig.supabaseURL
        guard let url = URL(string: base + endpoint) else { throw NuvioAuthError.message("Bad sync URL.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(NuvioConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NuvioAuthError.message("No response from sync server.")
        }
        if http.statusCode == 401 && !isRetry {
            // Access token likely expired — refresh once and retry.
            if await account.refreshSession() {
                return try await send(endpoint: endpoint, method: method, body: body, isRetry: true)
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NuvioAuthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case NuvioAuthError.http(let code, _): return "Sync failed (HTTP \(code))."
        case NuvioAuthError.message(let m): return m
        default: return "Sync failed."
        }
    }
}
