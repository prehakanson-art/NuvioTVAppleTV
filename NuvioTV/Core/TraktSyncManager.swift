import Combine
import Foundation

/// Two-way sync between the app and Trakt: watch history / watched badges
/// (WatchedStore ↔ Trakt history) and Continue Watching (Trakt playback
/// progress → ProgressStore). Local scrobbling already pushes playback the
/// other way. Sits alongside NuvioSyncManager (the account backend) — Trakt is
/// a separate, opt-in destination.
@MainActor
final class TraktSyncManager: ObservableObject {
    private let trakt: TraktStore
    private let watched: WatchedStore
    private let progress: ProgressStore
    private let addonManager: AddonManager

    private var cancellables = Set<AnyCancellable>()
    private var syncTask: Task<Void, Never>?
    /// Throttle full syncs so foreground + timer + sign-in don't stack up.
    private var lastFullSync = Date.distantPast

    init(trakt: TraktStore, watched: WatchedStore, progress: ProgressStore, addonManager: AddonManager) {
        self.trakt = trakt
        self.watched = watched
        self.progress = progress
        self.addonManager = addonManager

        // LOCAL → TRAKT: a mark / un-mark pushes to Trakt history immediately.
        watched.onTraktMark = { [weak self] item in self?.pushMark(item) }
        watched.onTraktRemove = { [weak self] items in self?.pushRemove(items) }
        // Toggling a Trakt sync setting on kicks a full sync.
        trakt.onTraktSettingChange = { [weak self] in self?.syncNow(force: true) }
    }

    // MARK: - Full sync

    /// Run a full two-way sync (debounced). `force` bypasses the throttle
    /// (sign-in, manual "Sync now", a setting flip).
    func syncNow(force: Bool = false) {
        guard trakt.isSignedIn else { return }
        if !force, Date().timeIntervalSince(lastFullSync) < 60 { return }
        lastFullSync = Date()
        syncTask?.cancel()
        syncTask = Task { [weak self] in await self?.runSync() }
    }

    private func runSync() async {
        guard let token = await validToken() else {
            trakt.setSyncStatus("Trakt session expired — sign in again")
            return
        }
        var parts: [String] = []
        if trakt.syncWatchHistory {
            let n = await syncWatchHistory(token: token)
            parts.append("\(n) history")
        }
        if trakt.syncPlayback {
            let n = await pullPlayback(token: token)
            if n > 0 { parts.append("\(n) in-progress") }
        }
        trakt.setSyncStatus(parts.isEmpty ? "Trakt: nothing to sync" : "Trakt synced (\(parts.joined(separator: ", ")))")
    }

    /// Two-way watch history. Pull Trakt → add missing locally; push local
    /// items Trakt doesn't have. Returns the count pulled.
    private func syncWatchHistory(token: String) async -> Int {
        let remote = await TraktService.watchedHistory(accessToken: token)
        let remoteItems = remote.compactMap(watchedItem(from:))
        // Add Trakt items missing locally (additive — never delete local
        // history from a partial Trakt response).
        if !remoteItems.isEmpty { watched.mergeRemote(remoteItems, reconcile: false) }

        // Push anything local that Trakt is missing.
        let remoteKeys = Set(remoteItems.map(\.key))
        let localOnly = watched.allForSync().filter { !remoteKeys.contains($0.key) }
        let pushable = localOnly.compactMap(syncItem(from:))
        if !pushable.isEmpty {
            _ = await TraktService.addToHistory(pushable, accessToken: token)
        }
        return remoteItems.count
    }

    /// Pull Trakt playback progress into Continue Watching (additive), enriched
    /// with meta for artwork + runtime. Returns count added/updated.
    private func pullPlayback(token: String) async -> Int {
        let items = await TraktService.playbackProgress(accessToken: token)
            .filter { ($0.progress ?? 0) > 1 && ($0.progress ?? 0) < 95 }
        guard !items.isEmpty else { return 0 }
        var rows: [WatchProgress] = []
        var enriched = 0
        for s in items {
            guard let metaID = localID(from: s) else { continue }
            let key: String
            if s.type == "series", let sea = s.season, let ep = s.episode {
                key = "\(metaID):\(sea):\(ep)"
            } else { key = metaID }

            var name = s.title
            var poster: String?
            var background: String?
            var runtimeMin: Int?
            if enriched < 25, let addon = addonManager.metaAddon(for: s.type, id: metaID),
               let meta = try? await StremioAPI.meta(addon: addon, type: s.type, id: metaID) {
                enriched += 1
                if !meta.name.isEmpty { name = meta.name }
                poster = meta.poster
                background = meta.background
                runtimeMin = Self.parseRuntimeMinutes(meta.runtime)
            }
            let dur = Double((runtimeMin ?? (s.type == "series" ? 45 : 100)) * 60)
            let pos = dur * (s.progress ?? 0) / 100
            rows.append(WatchProgress(
                id: key, metaID: metaID, type: s.type, name: name,
                poster: poster, background: background, logo: nil,
                season: s.season, episode: s.episode, episodeTitle: nil,
                positionSeconds: pos, durationSeconds: dur, streamURL: nil,
                updatedAt: s.watchedAt ?? Date()))
        }
        progress.mergeExternal(rows)
        return rows.count
    }

    // MARK: - Immediate mark/un-mark push

    private func pushMark(_ item: WatchedItem) {
        guard trakt.isSignedIn, trakt.syncWatchHistory, let token = trakt.accessToken,
              let s = syncItem(from: item) else { return }
        Task { _ = await TraktService.addToHistory([s], accessToken: token) }
    }

    private func pushRemove(_ items: [WatchedItem]) {
        guard trakt.isSignedIn, trakt.syncWatchHistory, let token = trakt.accessToken else { return }
        let syncItems = items.compactMap(syncItem(from:))
        guard !syncItems.isEmpty else { return }
        Task { _ = await TraktService.removeFromHistory(syncItems, accessToken: token) }
    }

    // MARK: - Token health

    /// A valid access token, refreshing once if the current one is rejected.
    private func validToken() async -> String? {
        guard let token = trakt.accessToken else { return nil }
        if await TraktService.fetchUsername(accessToken: token) != nil { return token }
        guard let refresh = trakt.refreshToken,
              let fresh = await TraktService.refreshToken(refresh) else { return nil }
        trakt.store(access: fresh.access, refresh: fresh.refresh)
        return fresh.access
    }

    // MARK: - ID mapping

    private func syncItem(from w: WatchedItem) -> TraktService.SyncItem? {
        let (imdb, tmdb) = Self.ids(from: w.contentID)
        guard imdb != nil || tmdb != nil else { return nil }
        return TraktService.SyncItem(
            imdb: imdb, tmdb: tmdb, type: w.contentType, title: w.title,
            season: w.season, episode: w.episode, progress: nil, watchedAt: w.watchedAt)
    }

    private func watchedItem(from s: TraktService.SyncItem) -> WatchedItem? {
        guard let cid = localID(from: s) else { return nil }
        return WatchedItem(
            contentID: cid, contentType: s.type, title: s.title,
            season: s.season, episode: s.episode, watchedAt: s.watchedAt ?? Date())
    }

    private func localID(from s: TraktService.SyncItem) -> String? {
        if let imdb = s.imdb, imdb.hasPrefix("tt") { return imdb }
        if let tmdb = s.tmdb { return "tmdb:\(tmdb)" }
        return nil
    }

    private static func ids(from contentID: String) -> (imdb: String?, tmdb: Int?) {
        if contentID.hasPrefix("tt") { return (contentID, nil) }
        if contentID.hasPrefix("tmdb:"), let n = Int(contentID.dropFirst("tmdb:".count)) { return (nil, n) }
        return (nil, nil)
    }

    /// "120 min" / "1h 30min" / "45min" → minutes.
    static func parseRuntimeMinutes(_ raw: String?) -> Int? {
        guard let raw = raw?.lowercased() else { return nil }
        var minutes = 0
        if let h = raw.range(of: #"(\d+)\s*h"#, options: .regularExpression),
           let n = Int(raw[h].filter(\.isNumber)) { minutes += n * 60 }
        if let m = raw.range(of: #"(\d+)\s*m"#, options: .regularExpression),
           let n = Int(raw[m].filter(\.isNumber)) { minutes += n }
        if minutes == 0, let only = Int(raw.filter(\.isNumber)), only > 0, only < 1000 { minutes = only }
        return minutes > 0 ? minutes : nil
    }
}
