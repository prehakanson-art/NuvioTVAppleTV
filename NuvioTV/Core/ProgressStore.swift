import Foundation

struct WatchProgress: Codable, Identifiable, Hashable {
    let id: String
    let metaID: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let season: Int?
    let episode: Int?
    let episodeTitle: String?
    /// Episode still image, so Continue Watching can show it instead of the
    /// show poster. Optional → old saves without it decode to nil.
    var episodeThumbnail: String? = nil
    var positionSeconds: Double
    var durationSeconds: Double
    var streamURL: String?
    var updatedAt: Date

    var fraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }
}

@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var items: [String: WatchProgress] = [:]

    /// Called after a local progress change so account sync can push. Not
    /// fired while merging remote data (guarded by `suppressChange`).
    var onLocalUpdate: (() -> Void)?
    /// Called when a title/episode crosses the "finished" threshold, so it can
    /// be recorded in watched history.
    var onFinished: ((MetaItem, MetaVideo?) -> Void)?
    /// Called with the progress keys of entries the user explicitly deleted, so
    /// account sync can delete them server-side too — otherwise they'd
    /// resurrect on the next pull.
    var onRemove: (([String]) -> Void)?
    private var suppressChange = false

    /// Active profile scope. Profile 1 uses the original (unsuffixed) key so
    /// existing data is preserved; other profiles get a suffixed namespace.
    private var profileID = 1
    private var storageKey: String {
        profileID == 1 ? "nuvio.progress.v1" : "nuvio.progress.v1.p\(profileID)"
    }

    init() {
        load()
    }

    /// Switch to another profile's data: the current profile is already
    /// persisted, so just re-point storage and reload.
    func setProfile(_ id: Int) {
        guard id != profileID else { return }
        profileID = id
        suppressChange = true
        items = [:]
        load()
        suppressChange = false
    }

    /// All entries, for a full push to the account backend.
    func allForSync() -> [WatchProgress] { Array(items.values) }

    /// Merges entries pulled from the account, keeping whichever side was
    /// updated more recently. Never triggers a push back.
    /// Grace window protecting a just-created local row from deletion
    /// reconciliation. A row's own push fires immediately on change but takes a
    /// round-trip to land; if a pull's server snapshot was captured before that
    /// push arrived, the row is legitimately absent from `remote` yet must NOT
    /// be treated as deleted. Anything older than this is safe to reconcile.
    private static let deletionGrace: TimeInterval = 120

    /// Merge a FULL remote snapshot for the profile. Two-way: newer remote rows
    /// are upserted, AND local rows the server no longer has are removed — so a
    /// removal made on another device (or a prior session) propagates the same
    /// way an addition does. Without the delete half, `mergeRemote` was
    /// additive-only: adds synced, removes never did.
    func mergeRemote(_ remote: [WatchProgress]) {
        suppressChange = true
        defer { suppressChange = false }
        var changed = false

        // ── Reconcile deletions ── remove local rows absent from the server
        // snapshot, except ones updated within the grace window (their own push
        // may still be in flight). This runs from a successful pull only, so an
        // empty snapshot genuinely means "the account has no Continue Watching."
        let remoteIDs = Set(remote.map(\.id))
        let cutoff = Date().addingTimeInterval(-Self.deletionGrace)
        // Collect first, then remove — mutating `items` mid-iteration is unsafe.
        let staleIDs = items.compactMap { id, local in
            (!remoteIDs.contains(id) && local.updatedAt < cutoff) ? id : nil
        }
        for id in staleIDs {
            items.removeValue(forKey: id)
            changed = true
        }

        for entry in remote {
            if let local = items[entry.id], local.updatedAt >= entry.updatedAt { continue }
            // Remote wins on position/timestamps, but synced rows arrive bare
            // (the backend stores no title/artwork/stream URL) and enrichment
            // is best-effort — so keep whatever presentation fields the local
            // entry already has instead of blanking the card. The remembered
            // stream URL carries over only for the same episode, so instant
            // resume keeps working after a pull.
            var merged = entry
            if let local = items[entry.id] {
                merged = WatchProgress(
                    id: entry.id,
                    metaID: entry.metaID,
                    type: entry.type,
                    name: entry.name.isEmpty ? local.name : entry.name,
                    poster: entry.poster ?? local.poster,
                    background: entry.background ?? local.background,
                    logo: entry.logo ?? local.logo,
                    season: entry.season,
                    episode: entry.episode,
                    episodeTitle: entry.episodeTitle
                        ?? (local.season == entry.season && local.episode == entry.episode ? local.episodeTitle : nil),
                    episodeThumbnail: entry.episodeThumbnail
                        ?? (local.season == entry.season && local.episode == entry.episode ? local.episodeThumbnail : nil),
                    positionSeconds: entry.positionSeconds,
                    durationSeconds: entry.durationSeconds,
                    streamURL: entry.streamURL
                        ?? (local.season == entry.season && local.episode == entry.episode ? local.streamURL : nil),
                    updatedAt: entry.updatedAt
                )
            }
            items[entry.id] = merged
            changed = true
        }
        if changed { save() }
    }

    /// Items that should appear in the Continue Watching row.
    ///
    /// A title shows up as soon as *any* progress is recorded (no minimum
    /// watched fraction) so an episode you barely started still appears. Series
    /// are collapsed to a single card per show (`metaID`) — the most recently
    /// watched episode — so starting a new episode replaces the old card
    /// instead of stacking a second entry for the same series.
    var continueWatching: [WatchProgress] {
        continueWatching(sortMode: .recentlyWatched)
    }

    /// Continue Watching, ordered per the chosen sort mode.
    /// - recentlyWatched: most recently played first.
    /// - streamingStyle: titles you're mid-episode on (2–95%) first, each by
    ///   recency, then barely-started ones — so you resume what you're actually
    ///   in the middle of.
    func continueWatching(sortMode: ContinueWatchingSortMode) -> [WatchProgress] {
        var latestPerShow: [String: WatchProgress] = [:]
        for item in items.values where item.fraction < 0.95 {
            if let existing = latestPerShow[item.metaID], existing.updatedAt >= item.updatedAt { continue }
            latestPerShow[item.metaID] = item
        }
        let byRecency = latestPerShow.values.sorted { $0.updatedAt > $1.updatedAt }
        switch sortMode {
        case .recentlyWatched:
            return byRecency
        case .streamingStyle:
            let inProgress = byRecency.filter { $0.fraction >= 0.02 }
            let fresh = byRecency.filter { $0.fraction < 0.02 }
            return inProgress + fresh
        }
    }

    func progress(for key: String) -> WatchProgress? {
        items[key]
    }

    static func key(metaID: String, video: MetaVideo?) -> String {
        guard let video else { return metaID }
        return video.id
    }

    func update(
        meta: MetaItem,
        video: MetaVideo?,
        streamURL: String?,
        position: Double,
        duration: Double
    ) {
        guard duration > 60, position > 0 else { return }
        let key = Self.key(metaID: meta.id, video: video)
        if position / duration >= 0.95 {
            items.removeValue(forKey: key)
            if !suppressChange { onFinished?(meta, video) }
        } else {
            items[key] = WatchProgress(
                id: key,
                metaID: meta.id,
                type: meta.type,
                name: meta.name,
                poster: meta.poster,
                background: meta.background,
                logo: meta.logo,
                season: video?.season,
                episode: video?.episode,
                episodeTitle: video?.title,
                episodeThumbnail: video?.thumbnail,
                positionSeconds: position,
                durationSeconds: duration,
                streamURL: streamURL,
                updatedAt: Date()
            )
        }
        save()
        if !suppressChange { onLocalUpdate?() }
    }

    /// Periodic in-playback save: persists to disk (crash safety) WITHOUT
    /// touching the published `items` — publishing re-rendered the whole Home
    /// screen sitting behind the player on every save, a periodic playback
    /// hiccup. The player's teardown/exit paths call the normal `update`,
    /// which publishes once and brings the UI up to date.
    func updateTransient(
        meta: MetaItem,
        video: MetaVideo?,
        streamURL: String?,
        position: Double,
        duration: Double
    ) {
        guard duration > 60, position > 0, position / duration < 0.95 else { return }
        let key = Self.key(metaID: meta.id, video: video)
        var snapshot = items
        snapshot[key] = WatchProgress(
            id: key,
            metaID: meta.id,
            type: meta.type,
            name: meta.name,
            poster: meta.poster,
            background: meta.background,
            logo: meta.logo,
            season: video?.season,
            episode: video?.episode,
            episodeTitle: video?.title,
            episodeThumbnail: video?.thumbnail,
            positionSeconds: position,
            durationSeconds: duration,
            streamURL: streamURL,
            updatedAt: Date()
        )
        let storage = storageKey
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            UserDefaults.standard.set(data, forKey: storage)
        }
    }

    func remove(id: String) {
        guard items.removeValue(forKey: id) != nil else { return }
        save()
        if !suppressChange {
            onRemove?([id])
            onLocalUpdate?()
        }
    }

    /// Rewrite a progress entry's identifiers to their canonical IMDb (`tt`)
    /// form, preserving position/timestamps. Used when resuming a TMDB-sourced
    /// item whose stored `tmdb:` key can't be served by Cinemeta/Torrentio —
    /// without this the migrated playback would save under the new key and
    /// leave the old `tmdb:` entry behind as a duplicate Continue Watching card.
    func recanonicalize(oldID: String, newID: String, newMetaID: String) {
        guard oldID != newID, let existing = items[oldID] else { return }
        items.removeValue(forKey: oldID)
        items[newID] = WatchProgress(
            id: newID, metaID: newMetaID, type: existing.type, name: existing.name,
            poster: existing.poster, background: existing.background, logo: existing.logo,
            season: existing.season, episode: existing.episode, episodeTitle: existing.episodeTitle,
            positionSeconds: existing.positionSeconds, durationSeconds: existing.durationSeconds,
            streamURL: existing.streamURL, updatedAt: existing.updatedAt
        )
        save()
        if !suppressChange {
            onRemove?([oldID])   // delete the stale tmdb: key server-side
            onLocalUpdate?()     // push the canonical entry
        }
    }

    /// Removes every stored entry for a show (all episodes), the way "Remove
    /// from Continue Watching" works on Netflix/Hulu. Deleting just the visible
    /// episode would leave the show's other episodes behind, so the card would
    /// immediately reappear with a different episode.
    func removeShow(metaID: String) {
        let removedKeys = items.values.filter { $0.metaID == metaID }.map(\.id)
        guard !removedKeys.isEmpty else { return }
        for key in removedKeys { items.removeValue(forKey: key) }
        save()
        if !suppressChange {
            onRemove?(removedKeys)
            onLocalUpdate?()
        }
    }

    // MARK: - Cheap poster lookups

    /// metaID → latest unfinished fraction. Maintained on every mutation so
    /// poster cards can look their progress up in O(1) — computing
    /// `continueWatching` (scan + sort) per card per render was measurable
    /// jank on the A10X.
    private(set) var continueFractions: [String: Double] = [:]

    private func rebuildContinueFractions() {
        var latest: [String: (Date, Double)] = [:]
        for item in items.values where item.fraction < 0.95 {
            if let existing = latest[item.metaID], existing.0 >= item.updatedAt { continue }
            latest[item.metaID] = (item.updatedAt, item.fraction)
        }
        continueFractions = latest.mapValues { $0.1 }
    }

    private func load() {
        defer {
            rebuildContinueFractions()
            // Refresh the Top Shelf snapshot on launch/profile switch so the
            // tvOS home shelf reflects existing Continue Watching immediately
            // (save() only fires during playback).
            let shelf = TopShelfExporter.entries(from: continueWatching)
            Task.detached(priority: .utility) { TopShelfExporter.write(shelf) }
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: WatchProgress].self, from: data) else {
            items = [:]
            return
        }
        items = decoded
    }

    private func save() {
        rebuildContinueFractions()
        // Encode + persist OFF the main thread: serializing the whole history
        // and writing UserDefaults on main was part of the periodic playback
        // hiccup (this runs every 30s while a video plays).
        let snapshot = items
        let key = storageKey
        // Top Shelf mirrors the Continue Watching row — snapshot the entries
        // here (cheap) and write them in the same background hop.
        let shelf = TopShelfExporter.entries(from: continueWatching)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            UserDefaults.standard.set(data, forKey: key)
            TopShelfExporter.write(shelf)
        }
    }
}
