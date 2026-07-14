import Foundation

/// TMDB settings, mirroring the Android `TmdbSettings`. Persisted locally;
/// governs metadata enrichment and whether TMDB collection sources resolve.
struct TMDBSettings: Codable, Equatable {
    var enabled: Bool = false
    var enrichContinueWatching: Bool = true
    var language: String = "en"
    // Granular enrichment toggles (mirror Android's per-section TMDB switches).
    var useCredits: Bool = true
    var useTrailers: Bool = true
    var useMoreLikeThis: Bool = true

    static let `default` = TMDBSettings()
}

@MainActor
final class TMDBSettingsStore: ObservableObject {
    @Published var settings: TMDBSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            TMDBService.preferredLanguage = settings.language
        }
    }

    private static let key = "nuvio.tmdb.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(TMDBSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
        // Localize every TMDB request from launch (get() reads this global).
        TMDBService.preferredLanguage = settings.language
    }

    var isEnabled: Bool { settings.enabled }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

/// Thin TMDB v3 client. The API key is a client-embedded value recovered from
/// the official app (same key the Android build ships in BuildConfig); TMDB v3
/// keys are designed to live in the client. Used to resolve TMDB collection
/// sources into MetaItems and to map TMDB ids to IMDB ids so those items flow
/// through the existing Cinemeta detail/stream pipeline.
enum TMDBService {
    /// TMDB API key — supplied via Secrets (gitignored).
    static let apiKey = Secrets.tmdbAPIKey
    private static let base = "https://api.themoviedb.org/3"
    private static let imageBase = "https://image.tmdb.org/t/p"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 128 << 20)
        return URLSession(configuration: config)
    }()

    // Cache TMDB→IMDB id lookups so repeated collection loads stay cheap.
    // Guarded by `cacheLock` — these caches are read/written from many
    // concurrent `Task`s (catalog rows map items in parallel), and a plain
    // Swift Dictionary is not thread-safe (concurrent mutation → EXC_BAD_ACCESS).
    private static let cacheLock = NSLock()
    private static var imdbCache: [String: String] = [:]

    private static func cachedIMDB(_ key: String) -> String? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return imdbCache[key]
    }
    private static func storeIMDB(_ value: String, for key: String) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        imdbCache[key] = value
    }
    private static func cachedFind(_ key: String) -> (Int, Bool)? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return findCache[key]
    }
    private static func storeFind(_ value: (Int, Bool), for key: String) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        findCache[key] = value
    }

    enum TMDBError: LocalizedError {
        case badResponse(Int)
        case missing
        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "TMDB returned HTTP \(code)"
            case .missing: return "TMDB item not found"
            }
        }
    }

    /// Preferred content language (ISO-639-1), kept in sync with the TMDB
    /// language setting so EVERY request is localized — not just the calls
    /// that happened to thread a `language:` argument. Set once at launch and
    /// on change by TMDBSettingsStore.
    nonisolated(unsafe) static var preferredLanguage = "en"

    private static func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(string: base + path)!
        var items = [URLQueryItem(name: "api_key", value: apiKey)]
        // Localize any request that didn't specify a language explicitly.
        if query["language"] == nil, preferredLanguage != "en" {
            items.append(URLQueryItem(name: "language", value: preferredLanguage))
        }
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items
        var request = URLRequest(url: comps.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TMDBError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func imageURL(_ path: String?, size: String) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return "\(imageBase)/\(size)\(path)"
    }

    // MARK: - ID mapping

    /// Map a TMDB id to an IMDB tt id via /external_ids. Cached; nil on failure.
    static func imdbID(tmdbID: Int, isMovie: Bool) async -> String? {
        let cacheKey = "\(isMovie ? "m" : "t"):\(tmdbID)"
        if let hit = cachedIMDB(cacheKey) { return hit.isEmpty ? nil : hit }
        let path = isMovie ? "/movie/\(tmdbID)/external_ids" : "/tv/\(tmdbID)/external_ids"
        struct ExternalIDs: Decodable { let imdb_id: String? }
        let imdb = (try? await get(path) as ExternalIDs)?.imdb_id
        storeIMDB(imdb ?? "", for: cacheKey)
        return imdb?.isEmpty == false ? imdb : nil
    }

    // MARK: - Collection source resolution

    /// Resolve a TMDB collection source into MetaItems. Each item's id is its
    /// IMDB tt id (resolved best-effort so it plays through Cinemeta); items
    /// whose IMDB id can't be resolved fall back to a `tmdb:<id>` id and still
    /// display. `language` comes from TMDB settings (ISO-639-1).
    static func resolve(source: CollectionSourceDTO, language: String) async -> [MetaItem] {
        guard source.provider.lowercased() == "tmdb",
              let sourceType = source.tmdbSourceType?.uppercased() else { return [] }
        let mediaIsMovie = (source.mediaType ?? "movie").lowercased() != "tv"
        let raw: [TMDBRawItem]
        do {
            switch sourceType {
            case "LIST":
                raw = try await resolveList(id: source.tmdbId, language: language)
            case "COLLECTION":
                raw = try await resolveCollection(id: source.tmdbId, language: language)
            case "COMPANY", "NETWORK", "DISCOVER":
                raw = try await resolveDiscover(source: source, sourceType: sourceType, isMovie: mediaIsMovie, language: language)
            case "PERSON", "DIRECTOR":
                raw = try await resolvePerson(id: source.tmdbId, director: sourceType == "DIRECTOR", isMovie: mediaIsMovie, language: language)
            default:
                raw = []
            }
        } catch {
            return []
        }
        return await mapToMetaItems(raw)
    }

    /// A TMDB entity flattened to the fields we need before IMDB resolution.
    private struct TMDBRawItem {
        let tmdbID: Int
        let isMovie: Bool
        let name: String
        let poster: String?
        let background: String?
        let description: String?
        let releaseInfo: String?
        let rating: Double?
    }

    private static func mapToMetaItems(_ raw: [TMDBRawItem]) async -> [MetaItem] {
        // Resolve IMDB ids concurrently (capped) so the whole folder loads fast.
        var resolved: [(Int, String?)] = []
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, item) in raw.prefix(40).enumerated() {
                group.addTask {
                    (index, await imdbID(tmdbID: item.tmdbID, isMovie: item.isMovie))
                }
            }
            for await pair in group { resolved.append(pair) }
        }
        let imdbByIndex = Dictionary(resolved, uniquingKeysWith: { a, _ in a })
        return raw.enumerated().map { index, item in
            let id = imdbByIndex[index].flatMap { $0 } ?? "tmdb:\(item.tmdbID)"
            return MetaItem(
                id: id,
                type: item.isMovie ? "movie" : "series",
                name: item.name,
                poster: item.poster,
                background: item.background,
                logo: nil,
                description: item.description,
                releaseInfo: item.releaseInfo,
                imdbRating: item.rating.map { String(format: "%.1f", $0) }
            )
        }
    }

    // MARK: - Endpoint helpers

    private static func resolveList(id: Int?, language: String) async throws -> [TMDBRawItem] {
        guard let id else { throw TMDBError.missing }
        struct ListResponse: Decodable { let items: [ListItem]? }
        struct ListItem: Decodable {
            let id: Int
            let title: String?; let name: String?
            let media_type: String?
            let poster_path: String?; let backdrop_path: String?
            let overview: String?; let release_date: String?; let first_air_date: String?
            let vote_average: Double?
        }
        let body: ListResponse = try await get("/list/\(id)", query: ["language": language])
        return (body.items ?? []).compactMap { item in
            let isMovie = (item.media_type?.lowercased() ?? "movie") != "tv"
            guard let title = item.title ?? item.name, !title.isEmpty else { return nil }
            return TMDBRawItem(
                tmdbID: item.id, isMovie: isMovie, name: title,
                poster: imageURL(item.poster_path, size: "w500") ?? imageURL(item.backdrop_path, size: "w780"),
                background: imageURL(item.backdrop_path, size: "w1280"),
                description: item.overview,
                releaseInfo: (item.release_date ?? item.first_air_date).map { String($0.prefix(4)) },
                rating: item.vote_average
            )
        }
    }

    private static func resolveCollection(id: Int?, language: String) async throws -> [TMDBRawItem] {
        guard let id else { throw TMDBError.missing }
        struct CollectionResponse: Decodable { let parts: [Part]? }
        struct Part: Decodable {
            let id: Int; let title: String?
            let poster_path: String?; let backdrop_path: String?
            let overview: String?; let release_date: String?; let vote_average: Double?
        }
        let body: CollectionResponse = try await get("/collection/\(id)", query: ["language": language])
        return (body.parts ?? []).compactMap { part in
            guard let title = part.title, !title.isEmpty else { return nil }
            return TMDBRawItem(
                tmdbID: part.id, isMovie: true, name: title,
                poster: imageURL(part.poster_path, size: "w500") ?? imageURL(part.backdrop_path, size: "w780"),
                background: imageURL(part.backdrop_path, size: "w1280"),
                description: part.overview,
                releaseInfo: part.release_date.map { String($0.prefix(4)) },
                rating: part.vote_average
            )
        }
    }

    private static func resolveDiscover(source: CollectionSourceDTO, sourceType: String, isMovie: Bool, language: String) async throws -> [TMDBRawItem] {
        // NETWORK forces TV; COMPANY/DISCOVER honor the source media type.
        let useTV = sourceType == "NETWORK" ? true : !isMovie
        var query: [String: String] = [
            "language": language,
            "page": "1",
            "sort_by": source.sortBy?.isEmpty == false ? source.sortBy! : "popularity.desc"
        ]
        let f = source.filters
        if sourceType == "COMPANY", let tid = source.tmdbId { query["with_companies"] = String(tid) }
        if let v = f?.withGenres { query["with_genres"] = v }
        if let v = f?.withKeywords { query["with_keywords"] = v }
        if let v = f?.withOriginalLanguage { query["with_original_language"] = v }
        if let v = f?.voteCountGte { query["vote_count.gte"] = String(v) }
        if let v = f?.voteAverageGte { query["vote_average.gte"] = String(v) }
        if let v = f?.year { query[useTV ? "first_air_date_year" : "year"] = String(v) }

        struct DiscoverResponse: Decodable { let results: [Result]? }
        struct Result: Decodable {
            let id: Int; let title: String?; let name: String?
            let poster_path: String?; let backdrop_path: String?
            let overview: String?; let release_date: String?; let first_air_date: String?
            let vote_average: Double?
        }
        if useTV, sourceType == "NETWORK", let tid = source.tmdbId {
            query["with_networks"] = String(tid)
        }
        let path = useTV ? "/discover/tv" : "/discover/movie"
        let body: DiscoverResponse = try await get(path, query: query)
        return (body.results ?? []).compactMap { r in
            guard let title = r.title ?? r.name, !title.isEmpty else { return nil }
            return TMDBRawItem(
                tmdbID: r.id, isMovie: !useTV, name: title,
                poster: imageURL(r.poster_path, size: "w500") ?? imageURL(r.backdrop_path, size: "w780"),
                background: imageURL(r.backdrop_path, size: "w1280"),
                description: r.overview,
                releaseInfo: (r.release_date ?? r.first_air_date).map { String($0.prefix(4)) },
                rating: r.vote_average
            )
        }
    }

    private static func resolvePerson(id: Int?, director: Bool, isMovie: Bool, language: String) async throws -> [TMDBRawItem] {
        guard let id else { throw TMDBError.missing }
        struct CreditsResponse: Decodable { let cast: [Credit]?; let crew: [Credit]? }
        struct Credit: Decodable {
            let id: Int; let title: String?; let name: String?
            let media_type: String?; let job: String?
            let poster_path: String?; let backdrop_path: String?
            let overview: String?; let release_date: String?; let first_air_date: String?
            let vote_average: Double?
        }
        let body: CreditsResponse = try await get("/person/\(id)/combined_credits", query: ["language": language])
        let credits = director
            ? (body.crew ?? []).filter { $0.job?.caseInsensitiveCompare("Director") == .orderedSame }
            : (body.cast ?? [])
        let wantTV = !isMovie
        return credits.compactMap { c in
            let credIsTV = (c.media_type?.lowercased() == "tv")
            guard credIsTV == wantTV else { return nil }
            guard let title = c.title ?? c.name, !title.isEmpty else { return nil }
            return TMDBRawItem(
                tmdbID: c.id, isMovie: !credIsTV, name: title,
                poster: imageURL(c.poster_path, size: "w500") ?? imageURL(c.backdrop_path, size: "w780"),
                background: imageURL(c.backdrop_path, size: "w1280"),
                description: c.overview,
                releaseInfo: (c.release_date ?? c.first_air_date).map { String($0.prefix(4)) },
                rating: c.vote_average
            )
        }
    }

    // MARK: - Detail enrichment (cast, more-like-this, collection)

    /// A cast member with a headshot, used on the Detail screen and clickable
    /// through to a Cast Detail filmography.
    struct CastMember: Identifiable, Hashable {
        let id: Int
        let name: String
        let character: String?
        let profileURL: String?
    }

    /// A movie collection ("belongs to") reference from TMDB.
    struct CollectionRef: Hashable {
        let id: Int
        let name: String
        let backdropURL: String?
    }

    /// A production company / network with a logo.
    struct Company: Identifiable, Hashable {
        let id: Int
        let name: String
        let logoURL: String
    }

    /// Per-episode extras (rating, air date, better still) keyed by episode
    /// number, resolved from a TMDB season.
    struct EpisodeExtra: Hashable {
        let rating: Double?
        let airDate: String?
        let still: String?
    }

    /// A YouTube trailer/teaser. `youtubeKey` feeds the stream extractor.
    struct Trailer: Identifiable, Hashable {
        let id: String        // TMDB video id
        let name: String
        let youtubeKey: String
        var thumbnailURL: String { "https://img.youtube.com/vi/\(youtubeKey)/hqdefault.jpg" }
    }

    /// Everything the Detail screen pulls from TMDB in one call.
    struct Detail {
        var cast: [CastMember] = []
        var crew: [CastMember] = []      // director + writers, shown first in "Creator and Cast"
        var moreLikeThis: [MetaItem] = []
        var collection: CollectionRef?
        var companies: [Company] = []
        var trailers: [Trailer] = []
        var director: String?
        var country: String?             // primary production country name
        var language: String?            // spoken/original language, uppercased ISO (e.g. "EN")
        var releaseDate: String?         // ISO date for the localized full-date meta line
    }

    // Cache imdb→(tmdbID,isMovie) resolutions from /find.
    private static var findCache: [String: (Int, Bool)] = [:]

    /// Resolve a MetaItem id to a TMDB id. Handles `tt…` (imdb, via /find),
    /// `tmdb:<n>`, and returns nil for id schemes TMDB can't map.
    static func resolveTMDBID(from id: String, type: String) async -> (id: Int, isMovie: Bool)? {
        let wantMovie = !(type == "series" || type == "tv")
        if id.hasPrefix("tmdb:") {
            guard let n = Int(id.dropFirst("tmdb:".count)) else { return nil }
            return (n, wantMovie)
        }
        guard id.hasPrefix("tt") else { return nil }
        if let hit = cachedFind(id) { return hit }
        struct FindResponse: Decodable {
            struct M: Decodable { let id: Int }
            let movie_results: [M]?
            let tv_results: [M]?
        }
        guard let body: FindResponse = try? await get("/find/\(id)", query: ["external_source": "imdb_id"]) else { return nil }
        let result: (Int, Bool)?
        if wantMovie, let m = body.movie_results?.first { result = (m.id, true) }
        else if let t = body.tv_results?.first { result = (t.id, false) }
        else if let m = body.movie_results?.first { result = (m.id, true) }
        else { result = nil }
        if let result { storeFind(result, for: id) }
        return result
    }

    /// Pull cast (with headshots), recommendations/similar, and collection for
    /// a title in a single append_to_response call. Best-effort: returns nil on
    /// any failure so callers keep their Cinemeta fallbacks.
    static func detail(imdbID: String, type: String, language: String = preferredLanguage) async -> Detail? {
        guard let (tmdbID, isMovie) = await resolveTMDBID(from: imdbID, type: type) else { return nil }
        struct DetailResponse: Decodable {
            struct Credits: Decodable { let cast: [CastDTO]?; let crew: [CrewDTO]? }
            struct CastDTO: Decodable {
                let id: Int; let name: String; let character: String?; let profile_path: String?
            }
            struct CrewDTO: Decodable {
                let id: Int; let name: String; let job: String?; let profile_path: String?
            }
            struct RecoResponse: Decodable { let results: [RecoItem]? }
            struct RecoItem: Decodable {
                let id: Int; let title: String?; let name: String?; let media_type: String?
                let poster_path: String?; let backdrop_path: String?
                let overview: String?; let release_date: String?; let first_air_date: String?
                let vote_average: Double?
            }
            struct BelongsTo: Decodable { let id: Int; let name: String; let backdrop_path: String? }
            struct CompanyDTO: Decodable { let id: Int; let name: String; let logo_path: String? }
            struct CountryDTO: Decodable { let iso_3166_1: String?; let name: String? }
            struct Videos: Decodable { let results: [VideoDTO]? }
            struct VideoDTO: Decodable {
                let id: String; let key: String; let name: String
                let site: String?; let type: String?; let official: Bool?
            }
            let credits: Credits?
            let recommendations: RecoResponse?
            let similar: RecoResponse?
            let belongs_to_collection: BelongsTo?
            let production_companies: [CompanyDTO]?
            let production_countries: [CountryDTO]?
            let original_language: String?
            let release_date: String?
            let first_air_date: String?
            let videos: Videos?
        }
        let path = isMovie ? "/movie/\(tmdbID)" : "/tv/\(tmdbID)"
        guard let body: DetailResponse = try? await get(
            path, query: ["language": language, "append_to_response": "credits,recommendations,similar,videos"]
        ) else { return nil }

        var detail = Detail()
        detail.cast = (body.credits?.cast ?? []).prefix(24).map {
            CastMember(id: $0.id, name: $0.name, character: $0.character,
                       profileURL: imageURL($0.profile_path, size: "w300"))
        }
        // Director + writers first (shown ahead of the cast in "Creator and Cast").
        let crew = body.credits?.crew ?? []
        let importantJobs = ["Director", "Writer", "Screenplay", "Creator"]
        detail.crew = crew
            .filter { importantJobs.contains($0.job ?? "") }
            .prefix(4)
            .map { CastMember(id: $0.id, name: $0.name, character: $0.job,
                              profileURL: imageURL($0.profile_path, size: "w300")) }
        detail.director = crew.first { $0.job == "Director" }?.name
            ?? crew.first { $0.job == "Creator" }?.name
        detail.country = body.production_countries?.first?.name
        detail.language = body.original_language?.uppercased()
        detail.releaseDate = body.release_date ?? body.first_air_date
        let recoResults = (body.recommendations?.results?.isEmpty == false)
            ? body.recommendations?.results
            : body.similar?.results
        let raw = (recoResults ?? []).compactMap { r -> TMDBRawItem? in
            let itemIsTV = (r.media_type?.lowercased() == "tv") || (!isMovie && r.media_type == nil)
            guard let title = r.title ?? r.name, !title.isEmpty else { return nil }
            return TMDBRawItem(
                tmdbID: r.id, isMovie: !itemIsTV, name: title,
                poster: imageURL(r.poster_path, size: "w500") ?? imageURL(r.backdrop_path, size: "w780"),
                background: imageURL(r.backdrop_path, size: "w1280"),
                description: r.overview,
                releaseInfo: (r.release_date ?? r.first_air_date).map { String($0.prefix(4)) },
                rating: r.vote_average
            )
        }
        detail.moreLikeThis = await mapToMetaItems(raw)
        if let bt = body.belongs_to_collection {
            detail.collection = CollectionRef(id: bt.id, name: bt.name,
                                              backdropURL: imageURL(bt.backdrop_path, size: "w780"))
        }
        detail.companies = (body.production_companies ?? []).compactMap { c in
            guard let logo = imageURL(c.logo_path, size: "w300") else { return nil }
            return Company(id: c.id, name: c.name, logoURL: logo)
        }
        // YouTube trailers/teasers, official first, "Trailer" before "Teaser".
        let videos = (body.videos?.results ?? []).filter {
            ($0.site?.caseInsensitiveCompare("YouTube") == .orderedSame)
                && ["Trailer", "Teaser"].contains($0.type ?? "")
        }
        detail.trailers = videos
            .sorted { a, b in
                if (a.official ?? false) != (b.official ?? false) { return (a.official ?? false) }
                return (a.type == "Trailer" ? 0 : 1) < (b.type == "Trailer" ? 0 : 1)
            }
            .map { Trailer(id: $0.id, name: $0.name, youtubeKey: $0.key) }
        return detail
    }

    /// Per-episode extras for a season, keyed by episode number. Used to show
    /// ratings + air dates on the Detail episode row. Best-effort.
    static func seasonEpisodes(imdbID: String, type: String, season: Int) async -> [Int: EpisodeExtra] {
        guard let (tmdbID, _) = await resolveTMDBID(from: imdbID, type: type) else { return [:] }
        struct SeasonResponse: Decodable {
            struct Episode: Decodable {
                let episode_number: Int?
                let vote_average: Double?
                let air_date: String?
                let still_path: String?
            }
            let episodes: [Episode]?
        }
        guard let body: SeasonResponse = try? await get("/tv/\(tmdbID)/season/\(season)") else { return [:] }
        var map: [Int: EpisodeExtra] = [:]
        for ep in body.episodes ?? [] {
            guard let n = ep.episode_number else { continue }
            map[n] = EpisodeExtra(
                rating: (ep.vote_average ?? 0) > 0 ? ep.vote_average : nil,
                airDate: ep.air_date,
                still: imageURL(ep.still_path, size: "w300")
            )
        }
        return map
    }

    /// The parts of a TMDB collection as MetaItems (for the "belongs to" row).
    static func collectionItems(id: Int, language: String = preferredLanguage) async -> [MetaItem] {
        guard let raw = try? await resolveCollection(id: id, language: language) else { return [] }
        return await mapToMetaItems(raw)
    }

    /// Browse a production company's catalog (movies + TV), most-popular first.
    /// Backs the TMDB entity-browse screen reached from a company logo.
    static func browseCompany(id: Int, language: String = preferredLanguage) async -> [MetaItem] {
        async let movies = discover(path: "/discover/movie", with: ["with_companies": String(id)], isMovie: true, language: language)
        async let tv = discover(path: "/discover/tv", with: ["with_companies": String(id)], isMovie: false, language: language)
        let raw = (await movies) + (await tv)
        let sorted = raw.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        return await mapToMetaItems(Array(sorted.prefix(40)))
    }

    private static func discover(path: String, with extra: [String: String], isMovie: Bool, language: String) async -> [TMDBRawItem] {
        var query = ["language": language, "page": "1", "sort_by": "popularity.desc"]
        extra.forEach { query[$0.key] = $0.value }
        struct DiscoverResponse: Decodable { let results: [Result]? }
        struct Result: Decodable {
            let id: Int; let title: String?; let name: String?
            let poster_path: String?; let backdrop_path: String?
            let overview: String?; let release_date: String?; let first_air_date: String?
            let vote_average: Double?
        }
        guard let body: DiscoverResponse = try? await get(path, query: query) else { return [] }
        return (body.results ?? []).compactMap { r in
            guard let title = r.title ?? r.name, !title.isEmpty else { return nil }
            return TMDBRawItem(
                tmdbID: r.id, isMovie: isMovie, name: title,
                poster: imageURL(r.poster_path, size: "w500") ?? imageURL(r.backdrop_path, size: "w780"),
                background: imageURL(r.backdrop_path, size: "w1280"),
                description: r.overview,
                releaseInfo: (r.release_date ?? r.first_air_date).map { String($0.prefix(4)) },
                rating: r.vote_average
            )
        }
    }

    /// A person's full filmography (cast credits, movies + TV), most-acclaimed
    /// first. Used by the Cast Detail screen.
    static func personFilmography(personID: Int, language: String = preferredLanguage) async -> [MetaItem] {
        struct CreditsResponse: Decodable { let cast: [Credit]? }
        struct Credit: Decodable {
            let id: Int; let title: String?; let name: String?; let media_type: String?
            let poster_path: String?; let backdrop_path: String?
            let overview: String?; let release_date: String?; let first_air_date: String?
            let vote_average: Double?
        }
        guard let body: CreditsResponse = try? await get(
            "/person/\(personID)/combined_credits", query: ["language": language]
        ) else { return [] }
        var seen = Set<Int>()
        let raw: [TMDBRawItem] = (body.cast ?? [])
            .sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }
            .compactMap { c in
                let isTV = c.media_type?.lowercased() == "tv"
                guard let title = c.title ?? c.name, !title.isEmpty, seen.insert(c.id).inserted else { return nil }
                return TMDBRawItem(
                    tmdbID: c.id, isMovie: !isTV, name: title,
                    poster: imageURL(c.poster_path, size: "w500") ?? imageURL(c.backdrop_path, size: "w780"),
                    background: imageURL(c.backdrop_path, size: "w1280"),
                    description: c.overview,
                    releaseInfo: (c.release_date ?? c.first_air_date).map { String($0.prefix(4)) },
                    rating: c.vote_average
                )
            }
        return await mapToMetaItems(Array(raw.prefix(40)))
    }
}
