import SwiftUI

// Max theme — a faithful port of the HBO Max / Max tvOS look into Orivio.
// A pure-black stage, white type, and WHITE focus treatments (white borders,
// white fills, scale) — no coloured chrome. The one accent that survives is the
// small blue progress bar. Its identity is a left sidebar that collapses to
// icons and expands over a scrim, an HBO max lockup top-right on browse pages,
// a left-scrimmed featured hero, and Top 10 rank numerals.
//
// Like Aurora/Onyx the recolour of the SHARED screens (Search / Library /
// Settings / Detail / Player) lives in `MaxPalette.adapt`, so those render
// unchanged but on Max's black surfaces with a white focus edge. Home + the
// sidebar are FULLY CUSTOM (`MaxHomeView`, `MaxSidebarNav`) so they match the
// real app 1:1. Everything gates on `ThemeManager.isMaxTheme`.

/// Design tokens for the Max look. Mirrors MaxTV's `Max` enum, renamed so it
/// doesn't shadow anything in Orivio. Colours use the shared `Color(hex:)`.
enum MaxStyle {

    // MARK: Palette
    static let stage      = Color.black
    /// Slightly raised surface for cards / setting rows.
    static let surface    = Color(hex: 0x1A1A1D)
    static let surfaceHi  = Color(hex: 0x2A2A2E)
    /// Sidebar scrim when expanded.
    static let scrim      = Color.black.opacity(0.82)
    /// The one accent that survives in Max: the small blue progress / check.
    static let progress   = Color(hex: 0x2E6BE6)
    static let check      = Color(hex: 0x3B82F6)

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary  = Color.white.opacity(0.5)
    static let textFaint     = Color.white.opacity(0.32)

    /// Left inset for page text/rails — sits just right of the collapsed
    /// sidebar icons, so content hugs the left like the real app. Hero/backdrop
    /// images ignore this and bleed full-width behind the sidebar.
    static let side: CGFloat = 130

    // MARK: Type — Max uses a bespoke grotesque; SF Pro is the closest system
    // stand-in. Titles are heavy, everything else regular/semibold.
    static func hero(_ s: CGFloat)     -> Font { .system(size: s, weight: .heavy) }
    static func title(_ s: CGFloat)    -> Font { .system(size: s, weight: .bold) }
    static func semibold(_ s: CGFloat) -> Font { .system(size: s, weight: .semibold) }
    static func medium(_ s: CGFloat)   -> Font { .system(size: s, weight: .medium) }
    static func regular(_ s: CGFloat)  -> Font { .system(size: s, weight: .regular) }

    // MARK: Scrims
    /// Left-anchored scrim over a hero backdrop so text stays legible; darkens
    /// the left ~55% and fades to clear, plus a bottom fade.
    static var heroScrim: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black.opacity(0.85), location: 0.30),
                    .init(color: .clear, location: 0.70)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                colors: [.black, .black.opacity(0.0)],
                startPoint: .bottom, endPoint: .center
            )
        }
    }
}

/// Rebuild the palette with Max's pure-black stage + white focus edge. Keeps the
/// blue progress accent for played bars, but focus is monochrome white (like
/// Onyx) so every shared screen matches the real Max app.
enum MaxPalette {
    static func adapt(_ base: ThemePalette, amoled: Bool) -> ThemePalette {
        var p = base

        // Max is already the blackest of blacks — AMOLED is a no-op here.
        p.background = Color.black
        p.backgroundElevated = Color(hex: 0x101012)
        p.backgroundCard = Color(hex: 0x1A1A1D)
        p.surface = Color(hex: 0x1A1A1D)
        p.surfaceVariant = Color(hex: 0x2A2A2E)
        p.panel = Color(hex: 0x101012)
        p.field = Color(hex: 0x1A1A1D)
        p.overlay = Color.black.opacity(0.85)
        p.playerOverlay = Color.black.opacity(0.85)

        p.textPrimary = .white
        p.textSecondary = Color.white.opacity(0.72)
        p.textTertiary = Color.white.opacity(0.5)

        // The signature: WHITE focus fill + edge (no colour, no glow). Selected
        // states across shared components read as a white pill with dark text,
        // exactly like Max's white highlights.
        p.secondary = .white
        p.secondaryVariant = Color(hex: 0xE5E5E5)
        p.onSecondary = .black
        p.focusRing = .white
        p.focusBackground = Color.white.opacity(0.16)
        p.focusGlow = .clear
        return p
    }
}
