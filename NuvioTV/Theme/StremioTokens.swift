import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// STREMIO — a theme that reproduces the Stremio tvOS app's look. Every color
// below is lifted directly from Stremio.app's Assets.car named color assets:
//
//   accentColor          rgb(0.482,0.357,0.961)  → #7B5BF5  (signature purple)
//   backgroundColor      rgb(0.059,0.051,0.145)  → #0F0D25  (dark navy-purple)
//   primary100Color      rgb(0.047,0.047,0.063)  → #0C0C10
//   primaryFontColor     rgb(0.949,·,·)          → #F2F2F2
//   secondaryFontColor   rgb(0.502,·,·)          → #808080
//   secondaryColor       white @ 3%              (subtle card surface)
//   thirdColor           white @ 7%              (elevated surface)
//   greenAccentColor     rgb(0.204,0.671,0.369)  → #34AB5E
//   yellowAccentColor    rgb(0.965,0.780,0.008)  → #F6C702
//
// Font: Plus Jakarta Sans (bundled from the Stremio app; see UIAppFonts).
//
// Stremio's focus language is the PURPLE ACCENT — focused cards get a purple
// border + purple ambient glow and a gentle scale, on rounded corners. That is
// deliberately unlike the app's other dark themes, so Stremio reads as itself.
// ═══════════════════════════════════════════════════════════════════════════

enum StremioSurfaces {
    /// The signature dark navy-purple stage (backgroundColor #0F0D25).
    static let background = Color(hex: 0x0F0D25)
    /// Elevated panel = Stremio's secondaryColor (white @ 3%) over the stage.
    static let elevated = Color(hex: 0x16152B)
    /// Card surface = Stremio's thirdColor (white @ 7%) over the stage.
    static let card = Color(hex: 0x201E34)
    /// Field / secondary panel = white @ 3% over the stage.
    static let field = Color(hex: 0x16152B)
    /// Darkest scrim = primary100Color #0C0C10.
    static let deep = Color(hex: 0x0C0C10)
    /// Dark scrim tint for gradients (primary100).
    static let scrim = Color(hex: 0x0C0C10)

    /// Signature Stremio purple (accentColor #7B5BF5). Stremio has no separate
    /// "bright" accent — focus uses the same accent (and accent @ 50%), so
    /// `accentBright` is aliased to it rather than an invented lighter shade.
    static let accent = Color(hex: 0x7B5BF5)
    static let accentBright = Color(hex: 0x7B5BF5)
    static let accentDark = Color(hex: 0x5B3FD6)
    /// Translucent purple for selection fills (accent @ 50% is Stremio's).
    static let accentFill = Color(hex: 0x7B5BF5, alpha: 0.22)

    // Exact Stremio font colors.
    static let textPrimary = Color(hex: 0xF2F2F2)     // primaryFontColor
    static let textSecondary = Color(hex: 0x808080)   // secondaryFontColor (pure gray)
    static let textTertiary = Color(hex: 0x6A6A6A)
    static let onAccent = Color(hex: 0xFFFFFF)

    /// The Stremio tvOS app's focus FRAME is its warm near-white primary font
    /// colour (#F2F2F2) — a clean bright border around the lifted card, NOT the
    /// purple accent. This is the signature of the reflective poster.
    static let frame = Color(hex: 0xF2F2F2)

    static let green = Color(hex: 0x34AB5E)
    static let yellow = Color(hex: 0xF6C702)
    static let red = Color(hex: 0xE5484D)

    // Thin translucent surfaces from Stremio's secondaryColor / thirdColor.
    static let hairline = Color.white.opacity(0.07)
    static let overlaySurface = Color.white.opacity(0.03)
}

/// Rebuilds the shared palette on Stremio's navy-purple stage with the purple
/// accent. Called from `ThemeManager.buildPalette` only while active. Unlike
/// the HBO-style themes this KEEPS a colored accent (`secondary` = purple) so
/// every shared control (buttons, chips, progress) picks up Stremio's purple.
enum StremioPalettes {
    static func adapt(_ base: ThemePalette, amoled: Bool) -> ThemePalette {
        var p = base
        p.secondary = StremioSurfaces.accent
        p.secondaryVariant = StremioSurfaces.accentDark
        p.onSecondary = StremioSurfaces.onAccent
        p.focusRing = StremioSurfaces.accent
        p.focusGlow = .clear                        // Stremio focus is border+scale, no glow
        p.focusBackground = StremioSurfaces.accentFill

        p.background = amoled ? Color(hex: 0x07060F) : StremioSurfaces.background
        p.backgroundElevated = StremioSurfaces.elevated
        p.backgroundCard = StremioSurfaces.card
        p.surface = StremioSurfaces.elevated
        p.surfaceVariant = StremioSurfaces.card
        p.panel = StremioSurfaces.elevated
        p.field = StremioSurfaces.field
        p.overlay = Color.black.opacity(0.82)
        p.playerOverlay = Color.black.opacity(0.4)

        p.textPrimary = StremioSurfaces.textPrimary
        p.textSecondary = StremioSurfaces.textSecondary
        p.textTertiary = StremioSurfaces.textTertiary
        return p
    }
}

// MARK: - Font

/// Plus Jakarta Sans — Stremio's typeface. Used by Stremio-specific chrome
/// (sidebar, wordmark, headings). Falls back to the system font automatically
/// if the bundled TTF fails to register.
enum StremioFont {
    static func regular(_ size: CGFloat) -> Font { .custom("PlusJakartaSans-Regular", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("PlusJakartaSans-Medium", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("PlusJakartaSans-Bold", size: size) }
}

// MARK: - Focus geometry

enum StremioFocus {
    /// Rounded cards (Stremio uses generously rounded poster corners).
    static let cardRadius: CGFloat = 12
    static let posterScale: CGFloat = 1.06
    static let landscapeScale: CGFloat = 1.05
    /// Stremio focus = a clean purple border + scale, NO ambient glow bloom.
    static let borderColor = StremioSurfaces.accent
    static let borderWidth: CGFloat = 4
    /// Kept for call sites but transparent — Stremio has no focus glow.
    static let glow = Color.clear
    static let unfocusedDim: Double = 0.0
    static let entry = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

// MARK: - Background

/// Every Stremio page sits on the flat navy-purple stage.
struct StremioBackground: View {
    var body: some View { StremioSurfaces.background.ignoresSafeArea() }
}
