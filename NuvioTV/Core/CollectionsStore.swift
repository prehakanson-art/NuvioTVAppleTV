import Foundation

/// Decodes `T` if possible, otherwise nil — so a single malformed element in
/// an array (a collection / folder / source written by another platform or a
/// newer app version) doesn't throw and drop the ENTIRE array. Used for the
/// synced collections blob so every valid custom catalog still comes through.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Models
//
// These mirror the Android app's Gson-serialized collection shape exactly
// (CollectionsDataStore.SerializableCollection et al) so the JSON blob synced
// through `sync_push/pull_collections` round-trips between platforms without
// loss. TMDB/Trakt sources are carried through untouched even though tvOS
// can't render them yet (they need the #4 integrations).

struct CollectionSourceDTO: Codable, Hashable {
    var provider: String = "addon"
    // addon provider
    var addonId: String?
    var type: String?
    var catalogId: String?
    var genre: String?
    // tmdb provider (preserved, not yet rendered on tvOS)
    var tmdbSourceType: String?
    var title: String?
    var tmdbId: Int?
    // trakt provider (preserved, not yet rendered on tvOS)
    var traktListId: Int64?
    // shared tmdb/trakt fields
    var mediaType: String?
    var sortBy: String?
    var sortHow: String?
    var filters: TmdbFiltersDTO?

    var isAddonSource: Bool { provider.lowercased() == "addon" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "addon"
        addonId = try c.decodeIfPresent(String.self, forKey: .addonId)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        catalogId = try c.decodeIfPresent(String.self, forKey: .catalogId)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        tmdbSourceType = try c.decodeIfPresent(String.self, forKey: .tmdbSourceType)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        tmdbId = try c.decodeIfPresent(Int.self, forKey: .tmdbId)
        traktListId = try c.decodeIfPresent(Int64.self, forKey: .traktListId)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        sortBy = try c.decodeIfPresent(String.self, forKey: .sortBy)
        sortHow = try c.decodeIfPresent(String.self, forKey: .sortHow)
        filters = try c.decodeIfPresent(TmdbFiltersDTO.self, forKey: .filters)
    }

    init(addonId: String, type: String, catalogId: String, genre: String? = nil) {
        self.provider = "addon"
        self.addonId = addonId
        self.type = type
        self.catalogId = catalogId
        self.genre = genre
    }

    // Gson omits nulls; match that so the blob compares stable across pushes.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider)
        try c.encodeIfPresent(addonId, forKey: .addonId)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(catalogId, forKey: .catalogId)
        try c.encodeIfPresent(genre, forKey: .genre)
        try c.encodeIfPresent(tmdbSourceType, forKey: .tmdbSourceType)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(tmdbId, forKey: .tmdbId)
        try c.encodeIfPresent(traktListId, forKey: .traktListId)
        try c.encodeIfPresent(mediaType, forKey: .mediaType)
        try c.encodeIfPresent(sortBy, forKey: .sortBy)
        try c.encodeIfPresent(sortHow, forKey: .sortHow)
        try c.encodeIfPresent(filters, forKey: .filters)
    }

    private enum CodingKeys: String, CodingKey {
        case provider, addonId, type, catalogId, genre, tmdbSourceType, title
        case tmdbId, traktListId, mediaType, sortBy, sortHow, filters
    }
}

struct TmdbFiltersDTO: Codable, Hashable {
    var withGenres: String?
    var releaseDateGte: String?
    var releaseDateLte: String?
    var voteAverageGte: Double?
    var voteAverageLte: Double?
    var voteCountGte: Int?
    var withOriginalLanguage: String?
    var withOriginCountry: String?
    var withKeywords: String?
    var withCompanies: String?
    var withNetworks: String?
    var year: Int?
    var watchRegion: String?
    var withWatchProviders: String?
}

struct NuvioCollectionFolder: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var coverImageUrl: String?
    var focusGifUrl: String?
    var focusGifEnabled: Bool?
    var coverEmoji: String?
    var tileShape: String = "SQUARE"   // SQUARE | POSTER | LANDSCAPE
    var hideTitle: Bool = false
    var sources: [CollectionSourceDTO]?
    var catalogSources: [CollectionSourceDTO]?   // legacy field, addon-only shape
    var heroBackdropUrl: String?
    var heroVideoUrl: String?
    var titleLogoUrl: String?

    /// Effective sources: modern `sources` wins, legacy `catalogSources` as fallback.
    var effectiveSources: [CollectionSourceDTO] {
        if let sources, !sources.isEmpty { return sources }
        return catalogSources ?? []
    }

    var addonSources: [CollectionSourceDTO] {
        effectiveSources.filter { $0.isAddonSource }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        coverImageUrl = try c.decodeIfPresent(String.self, forKey: .coverImageUrl)
        focusGifUrl = try c.decodeIfPresent(String.self, forKey: .focusGifUrl)
        focusGifEnabled = try c.decodeIfPresent(Bool.self, forKey: .focusGifEnabled)
        coverEmoji = try c.decodeIfPresent(String.self, forKey: .coverEmoji)
        tileShape = try c.decodeIfPresent(String.self, forKey: .tileShape) ?? "SQUARE"
        hideTitle = try c.decodeIfPresent(Bool.self, forKey: .hideTitle) ?? false
        // Lenient element decode: a bad source doesn't drop the folder.
        sources = try c.decodeIfPresent([Lenient<CollectionSourceDTO>].self, forKey: .sources)?.compactMap(\.value)
        catalogSources = try c.decodeIfPresent([Lenient<CollectionSourceDTO>].self, forKey: .catalogSources)?.compactMap(\.value)
        heroBackdropUrl = try c.decodeIfPresent(String.self, forKey: .heroBackdropUrl)
        heroVideoUrl = try c.decodeIfPresent(String.self, forKey: .heroVideoUrl)
        titleLogoUrl = try c.decodeIfPresent(String.self, forKey: .titleLogoUrl)
    }

    init(id: String, title: String, sources: [CollectionSourceDTO]) {
        self.id = id
        self.title = title
        self.sources = sources
        self.catalogSources = sources.filter { $0.isAddonSource }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(coverImageUrl, forKey: .coverImageUrl)
        try c.encodeIfPresent(focusGifUrl, forKey: .focusGifUrl)
        try c.encodeIfPresent(focusGifEnabled, forKey: .focusGifEnabled)
        try c.encodeIfPresent(coverEmoji, forKey: .coverEmoji)
        try c.encode(tileShape, forKey: .tileShape)
        try c.encode(hideTitle, forKey: .hideTitle)
        // Android always writes both `sources` and the legacy `catalogSources`.
        try c.encode(effectiveSources, forKey: .sources)
        try c.encode(addonSources.map { source in
            CollectionSourceDTO(
                addonId: source.addonId ?? "",
                type: source.type ?? "",
                catalogId: source.catalogId ?? "",
                genre: source.genre
            )
        }, forKey: .catalogSources)
        try c.encodeIfPresent(heroBackdropUrl, forKey: .heroBackdropUrl)
        try c.encodeIfPresent(heroVideoUrl, forKey: .heroVideoUrl)
        try c.encodeIfPresent(titleLogoUrl, forKey: .titleLogoUrl)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, coverImageUrl, focusGifUrl, focusGifEnabled, coverEmoji
        case tileShape, hideTitle, sources, catalogSources
        case heroBackdropUrl, heroVideoUrl, titleLogoUrl
    }
}

struct NuvioCollection: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var backdropImageUrl: String?
    var pinToTop: Bool = false
    var focusGlowEnabled: Bool?
    var viewMode: String = "TABBED_GRID"
    var showAllTab: Bool = true
    var folders: [NuvioCollectionFolder] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        backdropImageUrl = try c.decodeIfPresent(String.self, forKey: .backdropImageUrl)
        pinToTop = try c.decodeIfPresent(Bool.self, forKey: .pinToTop) ?? false
        focusGlowEnabled = try c.decodeIfPresent(Bool.self, forKey: .focusGlowEnabled)
        viewMode = try c.decodeIfPresent(String.self, forKey: .viewMode) ?? "TABBED_GRID"
        showAllTab = try c.decodeIfPresent(Bool.self, forKey: .showAllTab) ?? true
        // Lenient element decode: a bad folder doesn't drop the collection.
        folders = (try c.decodeIfPresent([Lenient<NuvioCollectionFolder>].self, forKey: .folders) ?? []).compactMap(\.value)
    }

    init(id: String, title: String, folders: [NuvioCollectionFolder] = []) {
        self.id = id
        self.title = title
        self.folders = folders
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(backdropImageUrl, forKey: .backdropImageUrl)
        try c.encode(pinToTop, forKey: .pinToTop)
        try c.encodeIfPresent(focusGlowEnabled, forKey: .focusGlowEnabled)
        try c.encode(viewMode, forKey: .viewMode)
        try c.encode(showAllTab, forKey: .showAllTab)
        try c.encode(folders, forKey: .folders)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, backdropImageUrl, pinToTop, focusGlowEnabled
        case viewMode, showAllTab, folders
    }
}

// MARK: - Store

/// Per-profile collections, persisted locally and synced as a whole-profile
/// JSON blob (matching Android's CollectionsDataStore + CollectionSyncService).
@MainActor
final class CollectionsStore: ObservableObject {
    @Published private(set) var collections: [NuvioCollection] = []

    /// Fired after a user-initiated change so account sync can push. Not
    /// fired while applying remote data (guarded by `suppressChange`).
    var onLocalChange: (() -> Void)?
    private var suppressChange = false
    private var profileID = 1

    private static let baseKey = "nuvio.collections.v1"

    private var storageKey: String {
        profileID == 1 ? Self.baseKey : "\(Self.baseKey).p\(profileID)"
    }

    init() {
        load()
    }

    /// Re-scope local storage to a profile. Profile 1 keeps the unsuffixed key.
    func setProfile(_ id: Int) {
        guard id != profileID else { return }
        profileID = id
        load()
    }

    func add(_ collection: NuvioCollection) {
        collections.append(collection)
        save()
        notifyLocalChange()
    }

    func update(_ collection: NuvioCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index] = collection
        save()
        notifyLocalChange()
    }

    func remove(id: String) {
        collections.removeAll { $0.id == id }
        save()
        notifyLocalChange()
    }

    func generateID() -> String { UUID().uuidString }

    // MARK: Sync plumbing

    /// The JSON array blob pushed to `sync_push_collections`.
    func exportJSON() -> String {
        guard !collections.isEmpty,
              let data = try? JSONEncoder().encode(collections),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    /// Apply a remote blob. Mirrors Android: remote-empty-while-local-has-data
    /// preserves local; identical JSON is a no-op. Returns true when applied.
    @discardableResult
    func applyRemote(json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        // Lenient element decode so one malformed collection (from another
        // platform / newer version) can't drop every other custom catalog.
        guard let lenient = try? JSONDecoder().decode([Lenient<NuvioCollection>].self, from: data) else { return false }
        return applyRemote(collections: lenient.compactMap(\.value))
    }

    /// Apply already-decoded remote collections (from the tvOS preferences
    /// blob). Same empty-preserve / no-op-on-identical rules as the JSON path.
    @discardableResult
    func applyRemote(collections remote: [NuvioCollection]) -> Bool {
        if remote.isEmpty && !collections.isEmpty { return false }
        guard remote != collections else { return false }
        suppressChange = true
        defer { suppressChange = false }
        collections = remote
        save()
        return true
    }

    // MARK: Persistence

    private func notifyLocalChange() {
        guard !suppressChange else { return }
        onLocalChange?()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([NuvioCollection].self, from: data) else {
            collections = []
            return
        }
        collections = decoded
    }

    private func save() {
        if collections.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(collections) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
