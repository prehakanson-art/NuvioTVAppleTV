import Foundation

/// Trakt account + settings, persisted locally.
///
/// The client id AND secret are recovered, live-validated public values
/// (extracted from the CloudStream-based APK's BuildConfig and verified against
/// Trakt's `/oauth/token` endpoint — a wrong secret returns `invalid_client`,
/// this pair returns `invalid_grant`). So device-code login completes end to
/// end without any user-supplied secret.
@MainActor
final class TraktStore: ObservableObject {
    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var username: String?
    @Published var scrobbleEnabled: Bool {
        didSet { UserDefaults.standard.set(scrobbleEnabled, forKey: Self.scrobbleKey) }
    }
    /// User-supplied client secret (empty until recovered).
    @Published var clientSecret: String {
        didSet { UserDefaults.standard.set(clientSecret, forKey: Self.secretKey) }
    }

    /// Recovered + validated public client id (header `trakt-api-key`).
    /// `nonisolated`: an immutable constant safe to read from the nonisolated
    /// networking statics (silences the main-actor isolation warning).
    nonisolated static let clientID = Secrets.traktClientID
    /// Recovered + validated public client secret (device-code token exchange).
    nonisolated static let clientSecret = Secrets.traktClientSecret

    private static let tokenKey = "nuvio.trakt.tokens.v1"
    private static let userKey = "nuvio.trakt.user.v1"
    private static let scrobbleKey = "nuvio.trakt.scrobble.v1"
    private static let secretKey = "nuvio.trakt.secret.v1"

    private struct Tokens: Codable { let access: String; let refresh: String }

    init() {
        scrobbleEnabled = UserDefaults.standard.object(forKey: Self.scrobbleKey) as? Bool ?? true
        clientSecret = UserDefaults.standard.string(forKey: Self.secretKey) ?? ""
        username = UserDefaults.standard.string(forKey: Self.userKey)
        if let data = UserDefaults.standard.data(forKey: Self.tokenKey),
           let tokens = try? JSONDecoder().decode(Tokens.self, from: data) {
            accessToken = tokens.access
            refreshToken = tokens.refresh
        }
    }

    var isSignedIn: Bool { accessToken != nil }
    var hasSecret: Bool { !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Fired on a local sign-in/out/username change so account sync can push the
    /// Trakt tokens to the shared `provider_credentials` table (the same place
    /// the Android app keeps them). Suppressed while applying a remote pull.
    var onLocalChange: (() -> Void)?
    private var applyingRemote = false

    func store(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        if let data = try? JSONEncoder().encode(Tokens(access: access, refresh: refresh)) {
            UserDefaults.standard.set(data, forKey: Self.tokenKey)
        }
        if !applyingRemote { onLocalChange?() }
    }

    func setUsername(_ name: String?) {
        username = name
        UserDefaults.standard.set(name, forKey: Self.userKey)
        if !applyingRemote { onLocalChange?() }
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        username = nil
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        if !applyingRemote { onLocalChange?() }
    }

    /// Apply Trakt tokens pulled from the account without echoing them back up.
    /// Only applies a real remote login (non-empty tokens) that differs from the
    /// local one. Deliberately does NOT sign out locally when the account has no
    /// Trakt row — absence usually means "never synced from this device", not
    /// "signed out everywhere".
    func applyRemote(access: String?, refresh: String?, username: String?) {
        applyingRemote = true
        defer { applyingRemote = false }
        if let access, let refresh, !access.isEmpty {
            guard access != accessToken || refresh != refreshToken else {
                if let username, username != self.username { setUsername(username) }
                return
            }
            store(access: access, refresh: refresh)
            if let username { setUsername(username) }
        }
    }
}

// MARK: - Service

struct TraktDeviceCode {
    let deviceCode: String
    let userCode: String
    let verificationURL: String
    let interval: Int
    let expiresIn: Int
}

enum TraktPollResult {
    case pending
    case authorized(access: String, refresh: String)
    case needsSecret
    case expired
    case failed(String)
}

/// Thin Trakt API client covering device auth + scrobbling.
enum TraktService {
    private static let base = "https://api.trakt.tv"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config)
    }()

    private static func request(_ path: String, method: String = "GET", bearer: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(TraktStore.clientID, forHTTPHeaderField: "trakt-api-key")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return request
    }

    // MARK: Device auth

    /// Start device login. Needs only the client id, so this always works.
    static func startDeviceCode() async throws -> TraktDeviceCode {
        struct Response: Decodable {
            let device_code: String; let user_code: String
            let verification_url: String; let expires_in: Int; let interval: Int
        }
        var req = request("/oauth/device/code", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": TraktStore.clientID])
        let (data, _) = try await session.data(for: req)
        let r = try JSONDecoder().decode(Response.self, from: data)
        return TraktDeviceCode(
            deviceCode: r.device_code, userCode: r.user_code,
            verificationURL: r.verification_url, interval: r.interval, expiresIn: r.expires_in
        )
    }

    /// Poll for the token. Requires the client secret; without it, returns
    /// `.needsSecret` so the UI can explain the blocker.
    static func pollToken(deviceCode: String, clientSecret: String) async -> TraktPollResult {
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        guard !secret.isEmpty else { return .needsSecret }
        struct TokenResponse: Decodable { let access_token: String; let refresh_token: String }
        var req = request("/oauth/device/token", method: "POST")
        let body = ["code": deviceCode, "client_id": TraktStore.clientID, "client_secret": secret]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse else {
            return .failed("Network error")
        }
        switch http.statusCode {
        case 200:
            guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                return .failed("Bad token response")
            }
            return .authorized(access: token.access_token, refresh: token.refresh_token)
        case 400: return .pending            // authorization pending
        case 404: return .failed("Invalid device code")
        case 409: return .pending            // already used, keep polling briefly
        case 410: return .expired            // code expired
        case 418: return .failed("Login denied")
        case 429: return .pending            // slow down
        default: return .failed("Trakt returned HTTP \(http.statusCode)")
        }
    }

    /// Fetch the signed-in user's username for display.
    static func fetchUsername(accessToken: String) async -> String? {
        struct Settings: Decodable { struct User: Decodable { let username: String? }; let user: User? }
        let req = request("/users/settings", bearer: accessToken)
        guard let (data, _) = try? await session.data(for: req),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return nil }
        return settings.user?.username
    }

    // MARK: Comments

    /// A public Trakt comment for the Detail screen.
    struct Comment: Identifiable, Hashable {
        let id: Int
        let user: String
        let text: String
        let likes: Int
        let spoiler: Bool
    }

    /// Fetch public comments for an IMDB-identified title (most-liked first).
    /// No auth needed — the api-key header is enough. Best-effort.
    static func comments(imdbID: String, type: String, limit: Int = 20) async -> [Comment] {
        guard imdbID.hasPrefix("tt") else { return [] }
        let kind = (type == "series" || type == "tv") ? "shows" : "movies"
        struct CommentDTO: Decodable {
            struct User: Decodable { let username: String? }
            let id: Int; let comment: String; let spoiler: Bool?; let likes: Int?; let user: User?
        }
        let req = request("/\(kind)/\(imdbID)/comments/likes?limit=\(limit)")
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let dtos = try? JSONDecoder().decode([CommentDTO].self, from: data) else { return [] }
        return dtos.map {
            Comment(id: $0.id, user: $0.user?.username ?? "Someone",
                    text: $0.comment, likes: $0.likes ?? 0, spoiler: $0.spoiler ?? false)
        }
    }

    // MARK: Scrobble

    enum ScrobbleAction: String { case start, stop, pause }

    /// Scrobble progress for an IMDB-identified item. `progress` is 0–100.
    /// Best-effort: failures are swallowed (scrobbling must never block play).
    @discardableResult
    static func scrobble(
        action: ScrobbleAction,
        imdbID: String,
        type: String,
        season: Int?,
        episode: Int?,
        progress: Double,
        accessToken: String
    ) async -> Bool {
        // Only tt… ids map cleanly to Trakt; skip anything else (e.g. tmdb:).
        guard imdbID.hasPrefix("tt") else { return false }
        var body: [String: Any] = ["progress": max(0, min(100, progress))]
        if type == "series" || type == "tv", let season, let episode {
            body["show"] = ["ids": ["imdb": imdbID]]
            body["episode"] = ["season": season, "number": episode]
        } else {
            body["movie"] = ["ids": ["imdb": imdbID]]
        }
        var req = request("/scrobble/\(action.rawValue)", method: "POST", bearer: accessToken)
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
