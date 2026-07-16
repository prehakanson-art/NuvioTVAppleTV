import Foundation

/// Location + language preferences for Live TV. When set, the embedded IPTV
/// list is loaded from iptv-org's per-country / per-language playlist instead
/// of the giant global one, so channels that don't apply to the viewer are
/// simply not there. Shared singleton (like PerformanceSettingsStore) so both
/// the settings pane and the Live TV tab read it without extra wiring.
@MainActor
final class LiveTVSettingsStore: ObservableObject {
    static let shared = LiveTVSettingsStore()

    /// ISO-3166 alpha-2 lowercase (iptv-org country file), "" = all.
    @Published var countryCode: String { didSet { UserDefaults.standard.set(countryCode, forKey: Self.countryKey) } }
    /// ISO-639-3 lowercase (iptv-org language file), "" = all.
    @Published var languageCode: String { didSet { UserDefaults.standard.set(languageCode, forKey: Self.langKey) } }

    private static let countryKey = "nuvio.livetv.country.v1"
    private static let langKey = "nuvio.livetv.language.v1"

    private init() {
        countryCode = UserDefaults.standard.string(forKey: Self.countryKey) ?? ""
        languageCode = UserDefaults.standard.string(forKey: Self.langKey) ?? ""
    }

    private static let base = "https://iptv-org.github.io/iptv"

    /// Playlist to load: country wins, then language, then the global list.
    var primaryPlaylistURL: String {
        if !countryCode.isEmpty { return "\(Self.base)/countries/\(countryCode).m3u" }
        if !languageCode.isEmpty { return "\(Self.base)/languages/\(languageCode).m3u" }
        return M3UService.iptvOrgURL
    }

    /// When BOTH are set, the country list is narrowed to channels that also
    /// appear in this language list (intersection).
    var secondaryLanguageURL: String? {
        guard !countryCode.isEmpty, !languageCode.isEmpty else { return nil }
        return "\(Self.base)/languages/\(languageCode).m3u"
    }

    struct Option: Identifiable { let code: String; let name: String; var id: String { code } }

    static let countries: [Option] = [
        .init(code: "", name: "All countries"),
        .init(code: "us", name: "United States"),
        .init(code: "gb", name: "United Kingdom"),
        .init(code: "ca", name: "Canada"),
        .init(code: "au", name: "Australia"),
        .init(code: "ie", name: "Ireland"),
        .init(code: "nz", name: "New Zealand"),
        .init(code: "in", name: "India"),
        .init(code: "de", name: "Germany"),
        .init(code: "fr", name: "France"),
        .init(code: "es", name: "Spain"),
        .init(code: "it", name: "Italy"),
        .init(code: "pt", name: "Portugal"),
        .init(code: "nl", name: "Netherlands"),
        .init(code: "se", name: "Sweden"),
        .init(code: "no", name: "Norway"),
        .init(code: "dk", name: "Denmark"),
        .init(code: "pl", name: "Poland"),
        .init(code: "ru", name: "Russia"),
        .init(code: "tr", name: "Turkey"),
        .init(code: "br", name: "Brazil"),
        .init(code: "mx", name: "Mexico"),
        .init(code: "ar", name: "Argentina"),
        .init(code: "jp", name: "Japan"),
        .init(code: "kr", name: "South Korea"),
    ]

    static let languages: [Option] = [
        .init(code: "", name: "All languages"),
        .init(code: "eng", name: "English"),
        .init(code: "spa", name: "Spanish"),
        .init(code: "fra", name: "French"),
        .init(code: "deu", name: "German"),
        .init(code: "ita", name: "Italian"),
        .init(code: "por", name: "Portuguese"),
        .init(code: "nld", name: "Dutch"),
        .init(code: "rus", name: "Russian"),
        .init(code: "tur", name: "Turkish"),
        .init(code: "pol", name: "Polish"),
        .init(code: "ara", name: "Arabic"),
        .init(code: "hin", name: "Hindi"),
        .init(code: "jpn", name: "Japanese"),
        .init(code: "kor", name: "Korean"),
        .init(code: "zho", name: "Chinese"),
    ]

    func countryName(_ code: String) -> String { Self.countries.first { $0.code == code }?.name ?? "All countries" }
    func languageName(_ code: String) -> String { Self.languages.first { $0.code == code }?.name ?? "All languages" }
}
