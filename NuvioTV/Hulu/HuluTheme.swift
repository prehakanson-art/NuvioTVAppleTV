import SwiftUI

// Hulu theme — a faithful port of the HuluTV tvOS look into Orivio: a very dark
// navy/teal stage, white type, and an accent used for focus outlines, the
// wordmark and hero episode lines. Per request the accent is NOT hardcoded Hulu
// green — it's the user's chosen Color Theme (`palette.secondary`), so the focus
// colour changes with the accent picker. Everything gates on
// `ThemeManager.isHuluTheme`.

/// Fixed design tokens for the Hulu look (stage/surfaces/fonts/scrim). The accent
/// (green in the original) is intentionally NOT here — components read
/// `theme.palette.secondary` so it follows the Color Theme.
enum HuluStyle {
    /// Near-black with a faint blue-green cast, like Hulu's dark theme.
    static let stage      = Color(hex: 0x0A0E14)
    static let stageDeep  = Color(hex: 0x05080C)
    static let surface    = Color(hex: 0x14202A)
    static let surfaceHi  = Color(hex: 0x1E2E3A)

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary  = Color.white.opacity(0.5)
    static let textFaint     = Color.white.opacity(0.32)

    /// Left inset for page text/rails — sits just right of the collapsed sidebar
    /// icons; hero/backdrop images bleed full-width behind the sidebar.
    static let side: CGFloat = 130

    /// App background: the dark stage with a subtle teal glow from bottom-right.
    static var background: some View {
        ZStack {
            stage
            RadialGradient(colors: [Color(hex: 0x123040).opacity(0.7), .clear],
                           center: .init(x: 0.85, y: 0.9), startRadius: 40, endRadius: 1500)
        }
        .ignoresSafeArea()
    }

    /// Left-anchored hero scrim so title/buttons stay legible over the backdrop.
    static var heroScrim: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: stage, location: 0.0),
                .init(color: stage.opacity(0.85), location: 0.32),
                .init(color: .clear, location: 0.68)
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [stage, stage.opacity(0.0)], startPoint: .bottom, endPoint: .center)
        }
    }

    // MARK: Type
    static func hero(_ s: CGFloat)     -> Font { .system(size: s, weight: .heavy) }
    static func title(_ s: CGFloat)    -> Font { .system(size: s, weight: .bold) }
    static func semibold(_ s: CGFloat) -> Font { .system(size: s, weight: .semibold) }
    static func medium(_ s: CGFloat)   -> Font { .system(size: s, weight: .medium) }
    static func regular(_ s: CGFloat)  -> Font { .system(size: s, weight: .regular) }
}

/// Rebuild the palette with the Hulu navy stage while KEEPING the user's accent
/// (secondary / focusRing), so the Color Theme picker recolours the focus rings,
/// wordmark, progress bars, etc.
enum HuluPalette {
    static func adapt(_ base: ThemePalette, amoled: Bool) -> ThemePalette {
        var p = base
        p.background = amoled ? Color.black : HuluStyle.stage
        p.backgroundElevated = HuluStyle.stageDeep
        p.backgroundCard = HuluStyle.surface
        p.surface = HuluStyle.surface
        p.surfaceVariant = HuluStyle.surfaceHi
        p.panel = HuluStyle.stageDeep
        p.field = HuluStyle.surface
        p.overlay = Color.black.opacity(0.85)
        p.playerOverlay = Color.black.opacity(0.8)
        p.textPrimary = .white
        p.textSecondary = Color.white.opacity(0.72)
        p.textTertiary = Color.white.opacity(0.5)
        // secondary / secondaryVariant / focusRing stay the user's accent.
        return p
    }
}
