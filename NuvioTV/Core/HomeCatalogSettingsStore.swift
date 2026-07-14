import Foundation

// MARK: - Home layout

/// Home screen presentation style, mirroring Android's `HomeLayout`.
/// - modern: large hero backdrop that follows focus + horizontal rows.
/// - classic: full-bleed focus-gradient backdrop + horizontal rows, no hero panel.
/// - grid: each catalog wrapped as a vertical poster grid.
enum HomeLayout: String, CaseIterable, Identifiable, Codable {
    // Order matches the APK's Home Layout picker: Modern, Grid, Classic.
    case modern, grid, classic
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modern: return "Modern View"
        case .classic: return "Classic View"
        case .grid: return "Grid View"
        }
    }

    var summary: String {
        switch self {
        case .modern: return "Cinematic hero that follows focus, with rows below"
        case .classic: return "Traditional rows with a subtle focus backdrop"
        case .grid: return "Dense poster grids for fast browsing"
        }
    }
}

/// Poster card size — drives the portrait card width everywhere it renders.
enum PosterSize: String, CaseIterable, Identifiable, Codable {
    case small, medium, large
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    /// Portrait poster width (points). Height is width × 3/2.
    var posterWidth: CGFloat {
        switch self {
        case .small: return 180
        case .medium: return 220
        case .large: return 264
        }
    }
}

// MARK: - Sync payload (matches Android SyncHomeCatalogPayload exactly)

struct SyncCatalogItem: Codable, Hashable {
    var addonID: String = ""
    var type: String = ""
    var catalogID: String = ""
    var enabled: Bool = true
    var order: Int = 0
    var customTitle: String = ""
    var isCollection: Bool = false
    var collectionID: String = ""

    private enum CodingKeys: String, CodingKey {
        case addonID = "addon_id"
        case type
        case catalogID = "catalog_id"
        case enabled
        case order
        case customTitle = "custom_title"
        case isCollection = "is_collection"
        case collectionID = "collection_id"
    }

    init(addonID: String = "", type: String = "", catalogID: String = "",
         enabled: Bool = true, order: Int = 0, customTitle: String = "",
         isCollection: Bool = false, collectionID: String = "") {
        self.addonID = addonID
        self.type = type
        self.catalogID = catalogID
        self.enabled = enabled
        self.order = order
        self.customTitle = customTitle
        self.isCollection = isCollection
        self.collectionID = collectionID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addonID = try c.decodeIfPresent(String.self, forKey: .addonID) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        catalogID = try c.decodeIfPresent(String.self, forKey: .catalogID) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle) ?? ""
        isCollection = try c.decodeIfPresent(Bool.self, forKey: .isCollection) ?? false
        collectionID = try c.decodeIfPresent(String.self, forKey: .collectionID) ?? ""
    }

    var key: String {
        isCollection
            ? HomeCatalogSettingsStore.collectionKey(collectionID)
            : HomeCatalogSettingsStore.catalogKey(addonID: addonID, type: type, catalogID: catalogID)
    }
}

struct SyncHomeCatalogPayload: Codable, Hashable {
    var hideUnreleasedContent: Bool = false
    var items: [SyncCatalogItem] = []

    private enum CodingKeys: String, CodingKey {
        case hideUnreleasedContent = "hide_unreleased_content"
        case items
    }

    init(hideUnreleasedContent: Bool = false, items: [SyncCatalogItem] = []) {
        self.hideUnreleasedContent = hideUnreleasedContent
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideUnreleasedContent = try c.decodeIfPresent(Bool.self, forKey: .hideUnreleasedContent) ?? false
        items = try c.decodeIfPresent([SyncCatalogItem].self, forKey: .items) ?? []
    }
}

// MARK: - Store

/// Home layout customization: which catalog rows show, their order, and custom
/// titles — plus collection rows interleaved. Keys match Android's
/// HomeCatalogSyncSupport: `{addonId}_{type}_{catalogId}` for addon catalogs
/// (addonId = manifest id, NOT the manifest URL) and `collection_{id}` for
/// collections, so settings sync cross-platform via
/// `sync_push/pull_home_catalog_settings`.
@MainActor
final class HomeCatalogSettingsStore: ObservableObject {
    @Published private(set) var orderKeys: [String] = []
    @Published private(set) var disabledKeys: Set<String> = []
    @Published private(set) var customTitles: [String: String] = [:]
    @Published var hideUnreleasedContent: Bool = false {
        didSet {
            guard hideUnreleasedContent != oldValue else { return }
            save()
            notifyLocalChange()
        }
    }
    /// Presentation style. Device-local (not part of the cross-platform sync
    /// payload — Android keeps layout local too).
    @Published var homeLayout: HomeLayout = .modern {
        didSet {
            guard homeLayout != oldValue else { return }
            save()
        }
    }
    /// Modern-view cards: portrait (false) or landscape (true), like the APK's
    /// "Landscape Posters" toggle.
    @Published var landscapePosters: Bool = false {
        didSet { guard landscapePosters != oldValue else { return }; save() }
    }
    /// Whether the home hero backdrop fills the screen (APK "Fullscreen Hero Backdrop").
    @Published var fullscreenHero: Bool = true {
        didSet { guard fullscreenHero != oldValue else { return }; save() }
    }
    /// Poster card size across all grids/rows.
    @Published var posterSize: PosterSize = .medium {
        didSet { guard posterSize != oldValue else { return }; save() }
    }
    /// Show the title label beneath poster cards.
    @Published var showPosterLabels: Bool = true {
        didSet { guard showPosterLabels != oldValue else { return }; save() }
    }

    var onLocalChange: (() -> Void)?
    private var suppressChange = false
    private var profileID = 1

    private static let baseKey = "nuvio.homecatalog.v1"

    nonisolated static func catalogKey(addonID: String, type: String, catalogID: String) -> String {
        "\(addonID)_\(type)_\(catalogID)"
    }

    nonisolated static func collectionKey(_ collectionID: String) -> String {
        "collection_\(collectionID)"
    }

    private var storageKey: String {
        profileID == 1 ? Self.baseKey : "\(Self.baseKey).p\(profileID)"
    }

    init() {
        load()
    }

    func setProfile(_ id: Int) {
        guard id != profileID else { return }
        profileID = id
        load()
    }

    // MARK: Queries

    func isEnabled(key: String) -> Bool { !disabledKeys.contains(key) }

    func customTitle(for key: String) -> String? {
        customTitles[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Merge saved order with the currently-available keys, exactly like
    /// Android's buildHomeCatalogSyncPayload: saved keys that still exist keep
    /// their positions; new catalog keys append, then new collection keys.
    func mergedOrder(catalogKeys: [String], collectionKeys: [String]) -> [String] {
        let available = Set(catalogKeys + collectionKeys)
        var seen = Set<String>()
        let savedValid = orderKeys.filter { available.contains($0) && seen.insert($0).inserted }
        let savedSet = Set(savedValid)
        return savedValid
            + catalogKeys.filter { !savedSet.contains($0) }
            + collectionKeys.filter { !savedSet.contains($0) }
    }

    // MARK: Mutations (UI)

    func setOrder(_ keys: [String]) {
        guard keys != orderKeys else { return }
        orderKeys = keys
        save()
        notifyLocalChange()
    }

    func move(key: String, up: Bool, within allKeys: [String]) {
        var keys = mergedOrder(catalogKeys: allKeys.filter { !$0.hasPrefix("collection_") },
                               collectionKeys: allKeys.filter { $0.hasPrefix("collection_") })
        guard let index = keys.firstIndex(of: key) else { return }
        let target = up ? index - 1 : index + 1
        guard keys.indices.contains(target) else { return }
        keys.swapAt(index, target)
        setOrder(keys)
    }

    func setEnabled(_ enabled: Bool, key: String) {
        if enabled { disabledKeys.remove(key) } else { disabledKeys.insert(key) }
        save()
        notifyLocalChange()
    }

    func setCustomTitle(_ title: String?, key: String) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            customTitles.removeValue(forKey: key)
        } else {
            customTitles[key] = trimmed
        }
        save()
        notifyLocalChange()
    }

    // MARK: Sync plumbing

    /// Build the push payload from currently-available addons + collections.
    func exportPayload(addons: [InstalledAddon], collections: [NuvioCollection]) -> SyncHomeCatalogPayload {
        var entries: [String: SyncCatalogItem] = [:]
        var catalogKeys: [String] = []
        var collectionKeys: [String] = []

        for addon in addons {
            for catalog in (addon.manifest.catalogs ?? []) where !catalog.requiresExtra {
                let key = Self.catalogKey(addonID: addon.manifest.id, type: catalog.type, catalogID: catalog.id)
                guard entries[key] == nil else { continue }
                catalogKeys.append(key)
                entries[key] = SyncCatalogItem(
                    addonID: addon.manifest.id,
                    type: catalog.type,
                    catalogID: catalog.id
                )
            }
        }
        for collection in collections {
            let key = Self.collectionKey(collection.id)
            guard entries[key] == nil else { continue }
            collectionKeys.append(key)
            entries[key] = SyncCatalogItem(isCollection: true, collectionID: collection.id)
        }

        let order = mergedOrder(catalogKeys: catalogKeys, collectionKeys: collectionKeys)
        let items: [SyncCatalogItem] = order.enumerated().compactMap { index, key in
            guard var item = entries[key] else { return nil }
            item.enabled = !disabledKeys.contains(key)
            item.order = index
            item.customTitle = customTitles[key] ?? ""
            return item
        }
        return SyncHomeCatalogPayload(hideUnreleasedContent: hideUnreleasedContent, items: items)
    }

    /// Apply a remote payload (pull). Suppresses the local-change push echo.
    func applyRemote(_ payload: SyncHomeCatalogPayload) {
        suppressChange = true
        defer { suppressChange = false }
        let sorted = payload.items.sorted { $0.order < $1.order }
        orderKeys = sorted.map(\.key)
        disabledKeys = Set(sorted.filter { !$0.enabled }.map(\.key))
        customTitles = Dictionary(
            sorted.compactMap { $0.customTitle.isEmpty ? nil : ($0.key, $0.customTitle) },
            uniquingKeysWith: { $1 }
        )
        hideUnreleasedContent = payload.hideUnreleasedContent
        save()
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var orderKeys: [String]
        var disabledKeys: [String]
        var customTitles: [String: String]
        var hideUnreleasedContent: Bool
        var homeLayout: HomeLayout?
        var landscapePosters: Bool?
        var fullscreenHero: Bool?
        var posterSize: PosterSize?
        var showPosterLabels: Bool?
    }

    private func notifyLocalChange() {
        guard !suppressChange else { return }
        onLocalChange?()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            orderKeys = []
            disabledKeys = []
            customTitles = [:]
            suppressChange = true
            hideUnreleasedContent = false
            homeLayout = .modern
            suppressChange = false
            return
        }
        orderKeys = decoded.orderKeys
        disabledKeys = Set(decoded.disabledKeys)
        customTitles = decoded.customTitles
        suppressChange = true
        hideUnreleasedContent = decoded.hideUnreleasedContent
        homeLayout = decoded.homeLayout ?? .modern
        landscapePosters = decoded.landscapePosters ?? false
        fullscreenHero = decoded.fullscreenHero ?? true
        posterSize = decoded.posterSize ?? .medium
        showPosterLabels = decoded.showPosterLabels ?? true
        suppressChange = false
    }

    private func save() {
        let persisted = Persisted(
            orderKeys: orderKeys,
            disabledKeys: Array(disabledKeys),
            customTitles: customTitles,
            hideUnreleasedContent: hideUnreleasedContent,
            homeLayout: homeLayout,
            landscapePosters: landscapePosters,
            fullscreenHero: fullscreenHero,
            posterSize: posterSize,
            showPosterLabels: showPosterLabels
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
