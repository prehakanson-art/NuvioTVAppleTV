import Foundation

// MARK: - Providers

/// A debrid provider. All four authenticate here with a user-supplied API
/// key/token (from the provider's account page). Device-code login (as the
/// Android app uses for TorBox/Premiumize) is a future enhancement.
enum DebridProvider: String, CaseIterable, Identifiable, Codable {
    case realDebrid, premiumize, torbox, allDebrid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realDebrid: return "Real-Debrid"
        case .premiumize: return "Premiumize"
        case .torbox: return "TorBox"
        case .allDebrid: return "AllDebrid"
        }
    }

    var shortName: String {
        switch self {
        case .realDebrid: return "RD"
        case .premiumize: return "PM"
        case .torbox: return "TB"
        case .allDebrid: return "AD"
        }
    }

    /// Where the user finds their API key, shown in Settings.
    var keyHint: String {
        switch self {
        case .realDebrid: return "real-debrid.com/apitoken"
        case .premiumize: return "premiumize.me/account"
        case .torbox: return "torbox.app → Settings → API"
        case .allDebrid: return "alldebrid.com/apikeys"
        }
    }
}

// MARK: - Store

/// Per-provider API keys + preferred provider, persisted locally.
@MainActor
final class DebridStore: ObservableObject {
    @Published private(set) var keys: [DebridProvider: String] = [:]
    @Published var preferred: DebridProvider? {
        didSet {
            guard preferred != oldValue else { return }
            saveMeta()
            if !applyingRemote { onLocalChange?() }
        }
    }

    /// Fired on a local key/preferred change so account sync can push. Guarded
    /// during a remote apply so a pull never echoes back as a push.
    var onLocalChange: (() -> Void)?
    private var applyingRemote = false

    private static let keysKey = "nuvio.debrid.keys.v1"
    private static let preferredKey = "nuvio.debrid.preferred.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.keysKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            keys = Dictionary(uniqueKeysWithValues: decoded.compactMap { raw in
                DebridProvider(rawValue: raw.key).map { ($0, raw.value) }
            })
        }
        if let raw = UserDefaults.standard.string(forKey: Self.preferredKey) {
            preferred = DebridProvider(rawValue: raw)
        }
    }

    var configuredProviders: [DebridProvider] {
        DebridProvider.allCases.filter { !(keys[$0] ?? "").isEmpty }
    }

    var hasAnyConfigured: Bool { !configuredProviders.isEmpty }

    func key(for provider: DebridProvider) -> String { keys[provider] ?? "" }

    func setKey(_ key: String, for provider: DebridProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { keys.removeValue(forKey: provider) } else { keys[provider] = trimmed }
        if preferred == nil, !trimmed.isEmpty { preferred = provider }
        if preferred != nil, keys[preferred!] == nil { preferred = configuredProviders.first }
        saveKeys()
        if !applyingRemote { onLocalChange?() }
    }

    // MARK: Sync

    /// Provider keys + preferred, as a syncable snapshot.
    struct DebridSnapshot: Codable, Equatable {
        var keys: [String: String] = [:]
        var preferred: String?
    }

    var snapshot: DebridSnapshot {
        DebridSnapshot(
            keys: Dictionary(uniqueKeysWithValues: keys.map { ($0.key.rawValue, $0.value) }),
            preferred: preferred?.rawValue
        )
    }

    /// Apply keys pulled from the account without echoing them back up. Merges:
    /// remote keys win, but a locally-entered key the remote lacks is kept.
    func applyRemote(_ s: DebridSnapshot) {
        applyingRemote = true
        defer { applyingRemote = false }
        var merged = keys
        for (raw, value) in s.keys {
            guard let provider = DebridProvider(rawValue: raw), !value.isEmpty else { continue }
            merged[provider] = value
        }
        if merged != keys { keys = merged; saveKeys() }
        if let raw = s.preferred, let provider = DebridProvider(rawValue: raw),
           configuredProviders.contains(provider), preferred != provider {
            preferred = provider
        }
    }

    /// The provider to try first for resolution.
    var resolverProvider: DebridProvider? {
        if let preferred, configuredProviders.contains(preferred) { return preferred }
        return configuredProviders.first
    }

    private func saveKeys() {
        let raw = Dictionary(uniqueKeysWithValues: keys.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.keysKey)
        }
    }

    private func saveMeta() {
        UserDefaults.standard.set(preferred?.rawValue, forKey: Self.preferredKey)
    }
}

// MARK: - Resolution

enum DebridResult {
    case success(url: String, filename: String?)
    case missingKey
    case notCached
    case failed(String)
}

/// Resolves torrent streams to direct HTTP links via a debrid provider.
/// Mirrors the Android DirectDebridResolver flows for each service.
enum DebridService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private static let videoExtensions = ["mkv", "mp4", "avi", "mov", "m4v", "wmv", "flv", "ts", "webm"]

    /// Resolve a torrent stream to a direct URL using the given provider+key.
    static func resolve(
        stream: Stream,
        provider: DebridProvider,
        apiKey: String,
        season: Int?,
        episode: Int?
    ) async -> DebridResult {
        guard !apiKey.isEmpty else { return .missingKey }
        guard let magnet = stream.magnetURI, let infoHash = stream.infoHash else {
            return .failed("Not a torrent stream")
        }
        do {
            switch provider {
            case .realDebrid:
                return try await resolveRealDebrid(magnet: magnet, apiKey: apiKey, season: season, episode: episode)
            case .premiumize:
                return try await resolvePremiumize(magnet: magnet, apiKey: apiKey, season: season, episode: episode)
            case .torbox:
                return try await resolveTorbox(magnet: magnet, apiKey: apiKey, season: season, episode: episode)
            case .allDebrid:
                return try await resolveAllDebrid(magnet: magnet, infoHash: infoHash, apiKey: apiKey, season: season, episode: episode)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Validate a key by hitting the provider's account endpoint.
    static func validate(provider: DebridProvider, apiKey: String) async -> Bool {
        guard !apiKey.isEmpty else { return false }
        let request: URLRequest
        switch provider {
        case .realDebrid:
            request = bearerRequest("https://api.real-debrid.com/rest/1.0/user", key: apiKey)
        case .premiumize:
            request = bearerRequest("https://www.premiumize.me/api/account/info", key: apiKey)
        case .torbox:
            request = bearerRequest("https://api.torbox.app/v1/api/user/me", key: apiKey)
        case .allDebrid:
            var comps = URLComponents(string: "https://api.alldebrid.com/v4/user")!
            comps.queryItems = [.init(name: "agent", value: "nuvio"), .init(name: "apikey", value: apiKey)]
            request = URLRequest(url: comps.url!)
        }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    // MARK: File selection

    /// Pick the best video file: for series match SxxExx, else the largest.
    private static func selectFile<F>(
        _ files: [F], season: Int?, episode: Int?,
        path: (F) -> String, size: (F) -> Int64
    ) -> F? {
        let videos = files.filter { f in
            let ext = (path(f) as NSString).pathExtension.lowercased()
            return videoExtensions.contains(ext)
        }
        let pool = videos.isEmpty ? files : videos
        if let season, let episode {
            let patterns = [
                String(format: "s%02de%02d", season, episode),
                String(format: "%dx%02d", season, episode)
            ]
            if let match = pool.first(where: { f in
                let name = path(f).lowercased()
                return patterns.contains { name.contains($0) }
            }) { return match }
        }
        return pool.max { size($0) < size($1) }
    }

    // MARK: Real-Debrid

    private static func resolveRealDebrid(magnet: String, apiKey: String, season: Int?, episode: Int?) async throws -> DebridResult {
        struct AddResult: Decodable { let id: String }
        struct TorrentInfo: Decodable {
            let status: String
            let links: [String]?
            let files: [TorrentFile]?
        }
        struct TorrentFile: Decodable { let id: Int; let path: String; let bytes: Int64 }
        struct Unrestrict: Decodable { let download: String; let filename: String? }

        let add: AddResult = try await form("https://api.real-debrid.com/rest/1.0/torrents/addMagnet", key: apiKey, fields: ["magnet": magnet])
        let torrentID = add.id
        var resolved = false
        defer {
            if !resolved {
                Task { _ = try? await self.delete("https://api.real-debrid.com/rest/1.0/torrents/delete/\(torrentID)", key: apiKey) }
            }
        }
        let info1: TorrentInfo = try await bearerGET("https://api.real-debrid.com/rest/1.0/torrents/info/\(torrentID)", key: apiKey)
        guard let file = selectFile(info1.files ?? [], season: season, episode: episode, path: \.path, size: \.bytes) else {
            return .notCached
        }
        try? await formIgnore("https://api.real-debrid.com/rest/1.0/torrents/selectFiles/\(torrentID)", key: apiKey, fields: ["files": String(file.id)])
        let info2: TorrentInfo = try await bearerGET("https://api.real-debrid.com/rest/1.0/torrents/info/\(torrentID)", key: apiKey)
        guard info2.status.lowercased() == "downloaded", let link = info2.links?.first else {
            return .notCached
        }
        let unrestrict: Unrestrict = try await form("https://api.real-debrid.com/rest/1.0/unrestrict/link", key: apiKey, fields: ["link": link])
        guard !unrestrict.download.isEmpty else { return .notCached }
        resolved = true
        return .success(url: unrestrict.download, filename: unrestrict.filename)
    }

    // MARK: Premiumize

    private static func resolvePremiumize(magnet: String, apiKey: String, season: Int?, episode: Int?) async throws -> DebridResult {
        struct DirectDL: Decodable {
            let status: String?
            let content: [Content]?
        }
        struct Content: Decodable { let path: String?; let link: String?; let size: Int64? }
        let result: DirectDL = try await form("https://www.premiumize.me/api/transfer/directdl", key: apiKey, fields: ["src": magnet])
        if result.status?.lowercased() == "error" { return .notCached }
        let contents = result.content ?? []
        guard let file = selectFile(contents, season: season, episode: episode,
                                    path: { $0.path ?? "" }, size: { $0.size ?? 0 }),
              let link = file.link, !link.isEmpty else {
            return .notCached
        }
        return .success(url: link, filename: (file.path as NSString?)?.lastPathComponent)
    }

    // MARK: TorBox

    private static func resolveTorbox(magnet: String, apiKey: String, season: Int?, episode: Int?) async throws -> DebridResult {
        struct Envelope<T: Decodable>: Decodable { let success: Bool?; let data: T? }
        struct CreateData: Decodable { let torrent_id: Int?; let id: Int? }
        struct TorrentData: Decodable { let files: [TorrentFile]? }
        struct TorrentFile: Decodable { let id: Int; let name: String; let size: Int64? }
        struct LinkData: Decodable { let data: String? }

        // createtorrent is multipart; add_only_if_cached=true → 409 when not cached.
        let create: Envelope<CreateData> = try await multipart(
            "https://api.torbox.app/v1/api/torrents/createtorrent", key: apiKey,
            parts: ["magnet": magnet, "add_only_if_cached": "true", "allow_zip": "false"]
        )
        guard let torrentID = create.data?.torrent_id ?? create.data?.id else { return .notCached }
        var comps = URLComponents(string: "https://api.torbox.app/v1/api/torrents/mylist")!
        comps.queryItems = [.init(name: "id", value: String(torrentID)), .init(name: "bypass_cache", value: "true")]
        let list: Envelope<TorrentData> = try await decode(bearerRequest(comps.url!.absoluteString, key: apiKey))
        guard let file = selectFile(list.data?.files ?? [], season: season, episode: episode, path: \.name, size: { $0.size ?? 0 }) else {
            return .notCached
        }
        var linkComps = URLComponents(string: "https://api.torbox.app/v1/api/torrents/requestdl")!
        linkComps.queryItems = [
            .init(name: "token", value: apiKey),
            .init(name: "torrent_id", value: String(torrentID)),
            .init(name: "file_id", value: String(file.id))
        ]
        let link: LinkData = try await decode(bearerRequest(linkComps.url!.absoluteString, key: apiKey))
        guard let url = link.data, !url.isEmpty else { return .notCached }
        return .success(url: url, filename: file.name)
    }

    // MARK: AllDebrid (public v4 API)

    private static func resolveAllDebrid(magnet: String, infoHash: String, apiKey: String, season: Int?, episode: Int?) async throws -> DebridResult {
        // Upload magnet → get id, then poll status for ready links, then unlock.
        struct UploadResponse: Decodable { let data: UploadData? }
        struct UploadData: Decodable { let magnets: [UploadMagnet]? }
        struct UploadMagnet: Decodable { let id: Int?; let ready: Bool? }
        struct StatusResponse: Decodable { let data: StatusData? }
        struct StatusData: Decodable { let magnets: StatusMagnet? }
        struct StatusMagnet: Decodable { let status: String?; let links: [StatusLink]? }
        struct StatusLink: Decodable { let link: String?; let filename: String?; let size: Int64? }
        struct UnlockResponse: Decodable { let data: UnlockData? }
        struct UnlockData: Decodable { let link: String? }

        let upload: UploadResponse = try await adGET("magnet/upload", apiKey: apiKey, query: ["magnets[]": magnet])
        guard let id = upload.data?.magnets?.first?.id else { return .notCached }
        let status: StatusResponse = try await adGET("magnet/status", apiKey: apiKey, query: ["id": String(id)])
        guard status.data?.magnets?.status?.lowercased() == "ready",
              let links = status.data?.magnets?.links, !links.isEmpty else {
            return .notCached
        }
        let chosen = selectFile(links, season: season, episode: episode,
                                path: { $0.filename ?? "" }, size: { $0.size ?? 0 })
        guard let protectedLink = chosen?.link else { return .notCached }
        let unlock: UnlockResponse = try await adGET("link/unlock", apiKey: apiKey, query: ["link": protectedLink])
        guard let url = unlock.data?.link, !url.isEmpty else { return .notCached }
        return .success(url: url, filename: chosen?.filename)
    }

    // MARK: - HTTP helpers

    private static func bearerRequest(_ url: String, key: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func bearerGET<T: Decodable>(_ url: String, key: String) async throws -> T {
        try await decode(bearerRequest(url, key: key))
    }

    private static func form<T: Decodable>(_ url: String, key: String, fields: [String: String]) async throws -> T {
        var request = bearerRequest(url, key: key)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        return try await decode(request)
    }

    /// POST a form body and ignore the response (used for RD selectFiles).
    private static func formIgnore(_ url: String, key: String, fields: [String: String]) async throws {
        var request = bearerRequest(url, key: key)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        _ = try await session.data(for: request)
    }

    @discardableResult
    private static func delete(_ url: String, key: String) async throws -> Data {
        var request = bearerRequest(url, key: key)
        request.httpMethod = "DELETE"
        let (data, _) = try await session.data(for: request)
        return data
    }

    private static func multipart<T: Decodable>(_ url: String, key: String, parts: [String: String]) async throws -> T {
        var request = bearerRequest(url, key: key)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        for (name, value) in parts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return try await decode(request)
    }

    private static func adGET<T: Decodable>(_ path: String, apiKey: String, query: [String: String]) async throws -> T {
        var comps = URLComponents(string: "https://api.alldebrid.com/v4/\(path)")!
        var items = [URLQueryItem(name: "agent", value: "nuvio"), URLQueryItem(name: "apikey", value: apiKey)]
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items
        var request = URLRequest(url: comps.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decode(request)
    }
}
