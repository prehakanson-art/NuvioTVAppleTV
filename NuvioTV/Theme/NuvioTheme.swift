import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Primitive color tokens ported from NuvioTV's Android design system.
enum NuvioPrimitives {
    static let black = Color(hex: 0x000000)
    static let white = Color(hex: 0xFFFFFF)
    static let neutral950 = Color(hex: 0x0D0D0D)
    static let neutral925 = Color(hex: 0x111111)
    static let neutral900 = Color(hex: 0x1A1A1A)
    static let neutral875 = Color(hex: 0x1E1E1E)
    static let neutral850 = Color(hex: 0x222222)
    static let neutral825 = Color(hex: 0x242424)
    static let neutral800 = Color(hex: 0x2D2D2D)
    static let neutral750 = Color(hex: 0x333333)
    static let neutral700 = Color(hex: 0x4D4D4D)
    static let neutral650 = Color(hex: 0x6F6F6F)
    static let neutral600 = Color(hex: 0x808080)
    static let neutral500 = Color(hex: 0x9E9E9E)
    static let neutral400 = Color(hex: 0xB3B3B3)
    static let neutral200 = Color(hex: 0xE0E0E0)
    static let neutral100 = Color(hex: 0xF5F5F5)
    static let red500 = Color(hex: 0xE53935)
    static let red600 = Color(hex: 0xC62828)
    static let red300 = Color(hex: 0xFF5252)
    static let blue500 = Color(hex: 0x1E88E5)
    static let blue700 = Color(hex: 0x1565C0)
    static let blue300 = Color(hex: 0x42A5F5)
    static let violet500 = Color(hex: 0x8E24AA)
    static let violet700 = Color(hex: 0x6A1B9A)
    static let violet300 = Color(hex: 0xAB47BC)
    static let green500 = Color(hex: 0x43A047)
    static let green700 = Color(hex: 0x2E7D32)
    static let green300 = Color(hex: 0x66BB6A)
    static let amber500 = Color(hex: 0xFB8C00)
    static let amber700 = Color(hex: 0xEF6C00)
    static let amber300 = Color(hex: 0xFFA726)
    static let rose500 = Color(hex: 0xD81B60)
    static let rose700 = Color(hex: 0xC2185B)
    static let rose300 = Color(hex: 0xEC407A)
    static let rating = Color(hex: 0xFFD700)
    static let torrent = Color(hex: 0x7E57C2)
    static let imdb = Color(hex: 0xF5C518)
    static let success = Color(hex: 0x4CAF50)
    static let warning = Color(hex: 0xFFB74D)
    static let error = Color(hex: 0xCF6679)
}

struct ThemePalette: Identifiable, Equatable {
    let id: String
    let displayName: String
    var secondary: Color
    var secondaryVariant: Color
    var onSecondary: Color = NuvioPrimitives.white
    var focusRing: Color
    var focusBackground: Color
    var background: Color = NuvioPrimitives.neutral950
    var backgroundElevated: Color = NuvioPrimitives.neutral900
    var backgroundCard: Color = NuvioPrimitives.neutral825
    var surface: Color = NuvioPrimitives.neutral875
    var surfaceVariant: Color = NuvioPrimitives.neutral800
    var panel: Color = NuvioPrimitives.neutral900
    var overlay: Color = Color.black.opacity(0.85)
    var field: Color = NuvioPrimitives.neutral850
    var playerOverlay: Color = Color.black.opacity(0.8)

    var textPrimary: Color { NuvioPrimitives.white }
    var textSecondary: Color { NuvioPrimitives.neutral400 }
    var textTertiary: Color { NuvioPrimitives.neutral500 }
}

enum NuvioThemes {
    static let crimson = ThemePalette(
        id: "crimson", displayName: "Crimson",
        secondary: NuvioPrimitives.red500,
        secondaryVariant: NuvioPrimitives.red600,
        focusRing: NuvioPrimitives.red300,
        focusBackground: Color(hex: 0x3D1A1A),
        backgroundCard: Color(hex: 0x241A1A)
    )
    static let ocean = ThemePalette(
        id: "ocean", displayName: "Ocean",
        secondary: NuvioPrimitives.blue500,
        secondaryVariant: NuvioPrimitives.blue700,
        focusRing: NuvioPrimitives.blue300,
        focusBackground: Color(hex: 0x1A2D3D),
        background: Color(hex: 0x0D0D0F),
        backgroundElevated: Color(hex: 0x1A1A1E),
        backgroundCard: Color(hex: 0x1A1F24)
    )
    static let violet = ThemePalette(
        id: "violet", displayName: "Violet",
        secondary: NuvioPrimitives.violet500,
        secondaryVariant: NuvioPrimitives.violet700,
        focusRing: NuvioPrimitives.violet300,
        focusBackground: Color(hex: 0x2D1A3D),
        background: Color(hex: 0x0D0D0F),
        backgroundElevated: Color(hex: 0x1A1A1E),
        backgroundCard: Color(hex: 0x1F1A24)
    )
    static let emerald = ThemePalette(
        id: "emerald", displayName: "Emerald",
        secondary: NuvioPrimitives.green500,
        secondaryVariant: NuvioPrimitives.green700,
        focusRing: NuvioPrimitives.green300,
        focusBackground: Color(hex: 0x1A3D1E),
        backgroundCard: Color(hex: 0x1A241A)
    )
    static let amber = ThemePalette(
        id: "amber", displayName: "Amber",
        secondary: NuvioPrimitives.amber500,
        secondaryVariant: NuvioPrimitives.amber700,
        focusRing: NuvioPrimitives.amber300,
        focusBackground: Color(hex: 0x3D2D1A),
        background: Color(hex: 0x0F0D0D),
        backgroundElevated: Color(hex: 0x1E1A1A),
        backgroundCard: Color(hex: 0x24201A)
    )
    static let rose = ThemePalette(
        id: "rose", displayName: "Rose",
        secondary: NuvioPrimitives.rose500,
        secondaryVariant: NuvioPrimitives.rose700,
        focusRing: NuvioPrimitives.rose300,
        focusBackground: Color(hex: 0x3D1A2D),
        backgroundCard: Color(hex: 0x241A1F)
    )
    static let white = ThemePalette(
        id: "white", displayName: "White",
        secondary: NuvioPrimitives.neutral100,
        secondaryVariant: NuvioPrimitives.neutral200,
        onSecondary: NuvioPrimitives.neutral925,
        focusRing: NuvioPrimitives.white,
        focusBackground: Color(hex: 0x303030),
        backgroundCard: NuvioPrimitives.neutral850
    )

    // Picker order matches the APK's Color Theme row: White first.
    static let all: [ThemePalette] = [white, crimson, ocean, violet, emerald, amber, rose]

    static func palette(id: String) -> ThemePalette {
        all.first { $0.id == id } ?? crimson
    }
}

/// App-wide font family (applied at the root via `.fontDesign`).
enum AppFont: String, CaseIterable, Identifiable, Codable {
    case system, rounded, serif, monospaced
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        }
    }
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

/// How much of the settings surface to expose (mirrors Android's
/// ExperienceMode). Essential hides the most technical options.
enum ExperienceMode: String, CaseIterable, Identifiable, Codable {
    case essential, advanced
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .essential: return "Essential"
        case .advanced: return "Advanced"
        }
    }
    var summary: String {
        switch self {
        case .essential: return "A simpler settings screen with just the everyday options"
        case .advanced: return "Every option, including engine, OSD and tuning controls"
        }
    }
    var isAdvanced: Bool { self == .advanced }
}

/// Settings-screen presentation style (mirrors Android's SettingsUiStyle).
/// Drives the corner radius of settings rows/cards.
enum SettingsUiStyle: String, CaseIterable, Identifiable, Codable {
    case classic, zen, horizon
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .zen: return "Zen"
        case .horizon: return "Horizon"
        }
    }
    var summary: String {
        switch self {
        case .classic: return "Soft rounded cards"
        case .zen: return "Pill-shaped rows"
        case .horizon: return "Sharp, squared edges"
        }
    }
    /// Corner radius for settings rows/cards in this style.
    var rowRadius: CGFloat {
        switch self {
        case .classic: return 12
        case .zen: return 26
        case .horizon: return 3
        }
    }
}

/// The synced slice of the theme (accent palette + AMOLED + font + experience).
struct ThemeSnapshot: Codable, Equatable {
    var paletteID: String
    var amoled: Bool
    var font: AppFont
    /// Default advanced so existing users keep the full settings surface.
    var experienceMode: ExperienceMode = .advanced
    var settingsUiStyle: SettingsUiStyle = .classic
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published private var basePalette: ThemePalette {
        didSet {
            UserDefaults.standard.set(basePalette.id, forKey: Self.key)
            if !applyingRemote { onLocalChange?() }
        }
    }
    /// AMOLED mode: force pure-black surfaces (APK "Use pure black for app backgrounds").
    @Published var amoled: Bool {
        didSet {
            UserDefaults.standard.set(amoled, forKey: Self.amoledKey)
            if !applyingRemote { onLocalChange?() }
        }
    }
    /// App-wide font family (applied at the root with `.fontDesign`).
    @Published var font: AppFont {
        didSet {
            UserDefaults.standard.set(font.rawValue, forKey: Self.fontKey)
            if !applyingRemote { onLocalChange?() }
        }
    }
    /// Settings-surface complexity (Essential hides advanced options).
    @Published var experienceMode: ExperienceMode {
        didSet {
            UserDefaults.standard.set(experienceMode.rawValue, forKey: Self.experienceKey)
            if !applyingRemote { onLocalChange?() }
        }
    }
    /// Settings-screen presentation style (row/card shape).
    @Published var settingsUiStyle: SettingsUiStyle {
        didSet {
            UserDefaults.standard.set(settingsUiStyle.rawValue, forKey: Self.settingsStyleKey)
            if !applyingRemote { onLocalChange?() }
        }
    }
    /// Corner radius for settings rows/cards under the current style.
    var settingsRowRadius: CGFloat { settingsUiStyle.rowRadius }

    /// Fired on a local (user-driven) theme change so the sync manager pushes it.
    var onLocalChange: (() -> Void)?
    private var applyingRemote = false

    private static let key = "nuvio.theme"
    private static let amoledKey = "nuvio.theme.amoled"
    private static let fontKey = "nuvio.theme.font"
    private static let experienceKey = "nuvio.theme.experience"
    private static let settingsStyleKey = "nuvio.theme.settingsstyle"

    init() {
        // Default to violet to match the Nuvio brand mark (cyan→purple play
        // logo); the old "crimson" default matched the retired red icon.
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? "violet"
        basePalette = NuvioThemes.palette(id: saved)
        amoled = UserDefaults.standard.bool(forKey: Self.amoledKey)
        font = AppFont(rawValue: UserDefaults.standard.string(forKey: Self.fontKey) ?? "") ?? .system
        experienceMode = ExperienceMode(rawValue: UserDefaults.standard.string(forKey: Self.experienceKey) ?? "") ?? .advanced
        settingsUiStyle = SettingsUiStyle(rawValue: UserDefaults.standard.string(forKey: Self.settingsStyleKey) ?? "") ?? .classic
    }

    /// Current theme as a syncable snapshot.
    var snapshot: ThemeSnapshot {
        ThemeSnapshot(
            paletteID: basePalette.id, amoled: amoled, font: font,
            experienceMode: experienceMode, settingsUiStyle: settingsUiStyle
        )
    }

    /// Apply a snapshot pulled from the account without echoing it back up.
    func applyRemote(_ s: ThemeSnapshot) {
        guard s != snapshot else { return }
        applyingRemote = true
        basePalette = NuvioThemes.palette(id: s.paletteID)
        amoled = s.amoled
        font = s.font
        experienceMode = s.experienceMode
        settingsUiStyle = s.settingsUiStyle
        applyingRemote = false
    }

    /// The palette used across the app, with the AMOLED override applied.
    var palette: ThemePalette {
        guard amoled else { return basePalette }
        var p = basePalette
        p.background = NuvioPrimitives.black
        p.backgroundElevated = Color(hex: 0x0A0A0A)
        return p
    }

    /// Change the accent theme (keeps AMOLED state).
    func setPalette(_ palette: ThemePalette) { basePalette = palette }
}

/// Spacing scale ported from Nuvio's SpacingTokens.
enum NuvioSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 44
    static let huge: CGFloat = 64
}

enum NuvioRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
}
