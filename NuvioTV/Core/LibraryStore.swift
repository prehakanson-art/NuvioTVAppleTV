import Foundation

/// A movie/show the user saved to their library. Mirrors the Android
/// `SavedLibraryItem` so it round-trips through `sync_push/pull_library`.
struct SavedLibraryItem: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let posterShape: String
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: Double?
    let genres: [String]
    let addonBaseURL: String?
    let addedAt: Date

    /// Stable storage key (a title can exist as both movie and series).
    var key: String { "\(type)|\(id)" }

    init(
        id: String, type: String, name: String,
        poster: String? = nil, posterShape: String = "POSTER",
        background: String? = nil, description: String? = nil,
        releaseInfo: String? = nil, imdbRating: Double? = nil,
        genres: [String] = [], addonBaseURL: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
        self.posterShape = posterShape
        self.background = background
        self.description = description
        self.releaseInfo = releaseInfo
        self.imdbRating = imdbRating
        self.genres = genres
        self.addonBaseURL = addonBaseURL
        self.addedAt = addedAt
    }

    init(meta: MetaItem) {
        self.init(
            id: meta.id,
            type: meta.type,
            name: meta.name,
            poster: meta.poster,
            posterShape: "POSTER",
            background: meta.background,
            description: meta.description,
            releaseInfo: meta.releaseInfo,
            imdbRating: meta.imdbRating.flatMap { Double($0) },
            genres: meta.genres ?? [],
            addonBaseURL: nil,
            addedAt: Date()
        )
    }

    /// Reconstruct a `MetaItem` good enough to open the detail page.
    var metaItem: MetaItem {
        MetaItem(
            id: id, type: type, name: name,
            poster: poster, background: background,
            description: description, releaseInfo: releaseInfo,
            imdbRating: imdbRating.map { String(format: "%.1f", $0) },
            genres: genres.isEmpty ? nil : genres
        )
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [String: SavedLibraryItem] = [:]

    /// Called after a local change so account sync can push. Suppressed while
    /// merging remote data.
    var onLocalChange: (() -> Void)?
    /// Trakt watchlist hooks (separate owner from account-sync): fired on a
    /// genuine local add / remove so the Trakt manager can push to the watchlist.
    var onTraktAdd: ((SavedLibraryItem) -> Void)?
    var onTraktRemove: ((SavedLibraryItem) -> Void)?
    private var suppressChange = false

    /// Recently-removed keys → removal time. The library push is full-replace
    /// (no per-item delete RPC), so between removing an item and that push
    /// landing, a pull's snapshot still contains it — without this the 30s
    /// Home poll (which also pulls library) would resurrect the row the user
    /// just removed, and the next push would re-add it to the account.
    private var tombstones: [String: Date] = [:]
    private static let tombstoneGrace: TimeInterval = 180
    /// Grace protecting a freshly-added row whose replace-push is still in
    /// flight from the deletion reconcile below.
    private static let deletionGrace: TimeInterval = 120

    private func pruneTombstones() {
        let cutoff = Date().addingTimeInterval(-Self.tombstoneGrace)
        tombstones = tombstones.filter { $0.value >= cutoff }
    }

    private var profileID = 1
    private var storageKey: String {
        profileID == 1 ? "nuvio.library.v1" : "nuvio.library.v1.p\(profileID)"
    }

    init() { load() }

    func setProfile(_ id: Int) {
        guard id != profileID else { return }
        profileID = id
        suppressChange = true
        items = [:]
        load()
        suppressChange = false
    }

    /// Saved items, newest first — the order the Library grid renders in.
    var sorted: [SavedLibraryItem] {
        items.values.sorted { $0.addedAt > $1.addedAt }
    }

    func contains(id: String, type: String) -> Bool {
        items["\(type)|\(id)"] != nil
    }

    func contains(_ meta: MetaItem) -> Bool { contains(id: meta.id, type: meta.type) }

    func toggle(_ meta: MetaItem) {
        if contains(meta) {
            remove(id: meta.id, type: meta.type)
        } else {
            add(SavedLibraryItem(meta: meta))
        }
    }

    func add(_ item: SavedLibraryItem) {
        // Re-saving something you'd removed clears its tombstone so the fresh
        // row survives the next pull's reconcile.
        tombstones.removeValue(forKey: item.key)
        let isNew = items[item.key] == nil
        items[item.key] = item
        save()
        if !suppressChange {
            if isNew { onTraktAdd?(item) }
            onLocalChange?()
        }
    }

    func remove(id: String, type: String) {
        let key = "\(type)|\(id)"
        guard let removed = items.removeValue(forKey: key) else { return }
        tombstones[key] = Date()
        save()
        if !suppressChange {
            onTraktRemove?(removed)
            onLocalChange?()
        }
    }

    // MARK: - Sync bridge

    func allForSync() -> [SavedLibraryItem] { Array(items.values) }

    /// Merge a FULL remote snapshot. Two-way, mirroring Progress/Watched: rows
    /// from the account are added AND (when `reconcile`) local rows the server
    /// no longer has are removed — otherwise a removal made on another device
    /// resurrects here on the next pull, and this device's replace-push re-adds
    /// it to the account (the remove/re-add ping-pong). Freshly-added rows
    /// (grace) and tombstoned rows (removal's push still in flight) are
    /// protected. `reconcile: false` = additive union — used for the FIRST pull
    /// of a profile, so items saved locally before ever signing in survive and
    /// get pushed up rather than treated as remote deletions.
    func mergeRemote(_ remote: [SavedLibraryItem], reconcile: Bool = true) {
        suppressChange = true
        defer { suppressChange = false }
        var changed = false
        pruneTombstones()

        // ── Reconcile deletions ──
        if reconcile {
            let remoteKeys = Set(remote.map(\.key))
            let cutoff = Date().addingTimeInterval(-Self.deletionGrace)
            let staleKeys = items.compactMap { key, local in
                (!remoteKeys.contains(key) && local.addedAt < cutoff) ? key : nil
            }
            for key in staleKeys {
                items.removeValue(forKey: key)
                changed = true
            }
        }

        for item in remote where items[item.key] == nil {
            if let tomb = tombstones[item.key] {
                if item.addedAt > tomb {
                    tombstones.removeValue(forKey: item.key)   // re-saved elsewhere
                } else {
                    continue
                }
            }
            items[item.key] = item
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: SavedLibraryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
