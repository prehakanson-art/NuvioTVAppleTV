import SwiftUI

// Netflix-inspired theme tokens (NETFLIX_THEME_SPEC.md §5–§9). Consumed only
// by netflix-gated code paths, so the Fusion and Classic themes are unaffected.
// Perf note (see nuviotv-fusion-perf memory / prior passes): everything here is
// flat colors and named animations — no materials, no live filters. Components
// that adopt these tokens must keep using overlays / pre-rendered images
// instead of .brightness/.saturation/.blur, exactly like Fusion does now.

// MARK: - Surfaces & text (§5.1, §5.3)

/// The black "theater stage". Unlike Fusion's graphite, the Netflix theme sits
/// on near-black so artwork provides the color.
enum NetflixSurfaces {
    /// Player canvas, AMOLED, deep modals, letterbox, art-from-darkness.
    static let black = Color(hex: 0x000000)
    /// Standard page background (Home, Movies, TV Shows, My Fusion, …).
    static let background = Color(hex: 0x070707)
    /// First raised surface — settings panels, keyboards, containers.
    static let raised1 = Color(hex: 0x111111)
    /// Second raised surface — list rows, quick menus, dialogs, plain cards.
    static let raised2 = Color(hex: 0x181818)
    /// Strongest raised surface — focused settings rows, selected filters.
    static let raised3 = Color(hex: 0x272727)
    /// Focused source row (§69).
    static let raisedFocus = Color(hex: 0x2A2A2A)

    static let textPrimary = Color(hex: 0xFFFFFF)
    static let textSecondary = Color(hex: 0xD2D2D2)
    static let textTertiary = Color(hex: 0x9A9A9A)
    static let textDisabled = Color(hex: 0x616161)
    /// Black text over the white Play button (§5.3, §23).
    static let onWhite = Color(hex: 0x080808)

    // §5.4 semantic colors — always paired with a label/icon, never color-only.
    static let live = Color(hex: 0xE50914)
    static let success = Color(hex: 0x42CB7F)
    static let warning = Color(hex: 0xE5A63A)
    static let error = Color(hex: 0xFF4E59)
    static let info = Color(hex: 0x5B9FFF)
    static let cached = Color(hex: 0x48CA80)
    static let unreleased = Color(hex: 0xA1A1A1)

    // §96 skeletons.
    static let skeleton = Color(hex: 0x1B1B1B)
    static let skeletonHighlight = Color(hex: 0x292929)
}

// MARK: - Accents (§6)

/// The seven configurable accents in their Netflix-theme tunings, keyed by the
/// same ids as `NuvioThemes` so the user's Color Theme maps straight through.
/// Reuses the `FusionAccent` shape (primary / brightFocus / darkTint / glow).
/// Default is Crimson — the theme's "Fusion Red" identity (§5.2).
enum NetflixAccents {
    static let white = FusionAccent(
        primary: Color(hex: 0xF1F1F1), brightFocus: Color(hex: 0xFFFFFF),
        darkTint: Color(hex: 0x777777), glow: Color(hex: 0xFFFFFF, alpha: 0.22))
    static let crimson = FusionAccent(
        primary: Color(hex: 0xE51C23), brightFocus: Color(hex: 0xFF343C),
        darkTint: Color(hex: 0x8E1115), glow: Color(hex: 0xE51C23, alpha: 0.28))
    static let ocean = FusionAccent(
        primary: Color(hex: 0x368BFF), brightFocus: Color(hex: 0x65A8FF),
        darkTint: Color(hex: 0x20569E), glow: Color(hex: 0x368BFF, alpha: 0.28))
    static let violet = FusionAccent(
        primary: Color(hex: 0x9466FF), brightFocus: Color(hex: 0xB08BFF),
        darkTint: Color(hex: 0x5B3C9E), glow: Color(hex: 0x9466FF, alpha: 0.28))
    static let emerald = FusionAccent(
        primary: Color(hex: 0x34CF88), brightFocus: Color(hex: 0x5CE5A6),
        darkTint: Color(hex: 0x1D7A52), glow: Color(hex: 0x34CF88, alpha: 0.28))
    static let mint = FusionAccent(
        primary: Color(hex: 0x1CE783), brightFocus: Color(hex: 0x57F0A5),
        darkTint: Color(hex: 0x0F7C48), glow: Color(hex: 0x1CE783, alpha: 0.30))
    static let amber = FusionAccent(
        primary: Color(hex: 0xF0AA3C), brightFocus: Color(hex: 0xFFC666),
        darkTint: Color(hex: 0x8D6326), glow: Color(hex: 0xF0AA3C, alpha: 0.27))
    static let rose = FusionAccent(
        primary: Color(hex: 0xEF679F), brightFocus: Color(hex: 0xFF8CBB),
        darkTint: Color(hex: 0x943E65), glow: Color(hex: 0xEF679F, alpha: 0.28))
    static let orivioPurple = FusionAccent(
        primary: Color(hex: 0x6D27E8), brightFocus: Color(hex: 0x925DFF),
        darkTint: Color(hex: 0x3C137F), glow: Color(hex: 0x6D27E8, alpha: 0.30))
    static let lavender = FusionAccent(
        primary: Color(hex: 0xB99AFF), brightFocus: Color(hex: 0xD4C1FF),
        darkTint: Color(hex: 0x6D5AA8), glow: Color(hex: 0xB99AFF, alpha: 0.26))

    static func accent(id: String) -> FusionAccent {
        switch id {
        case "white": return white
        case "ocean": return ocean
        case "violet": return violet
        case "purple": return orivioPurple
        case "lavender": return lavender
        case "emerald": return emerald
        case "mint": return mint
        case "amber": return amber
        case "rose": return rose
        // Crimson AND the fallback: the theme's default identity is red.
        default: return crimson
        }
    }

    /// The near-white, light-lavender and neon-mint accents need dark text on
    /// their fill.
    static func needsDarkOn(id: String) -> Bool { id == "white" || id == "lavender" || id == "mint" }
}

// MARK: - Palette adapter (§5)

/// Rebuild the selected accent palette on the Netflix black stage, the same
/// way `ATVPalettes.adapt` builds Fusion's graphite. Called from
/// `ThemeManager.buildPalette` only while the netflix theme is active.
enum NetflixPalettes {
    static func adapt(_ base: ThemePalette, amoled: Bool) -> ThemePalette {
        var p = base

        // ── Accent (§6) ──
        let accent = NetflixAccents.accent(id: base.id)
        p.secondary = accent.primary
        p.secondaryVariant = accent.darkTint
        p.focusRing = accent.brightFocus
        p.focusGlow = accent.glow
        p.onSecondary = NetflixAccents.needsDarkOn(id: base.id)
            ? NetflixSurfaces.onWhite : NuvioPrimitives.white
        p.focusBackground = accent.primary.opacity(0.18)

        // ── Surfaces (§5.1) — dark only; AMOLED drops the stage to pure black.
        p.background = amoled ? NetflixSurfaces.black : NetflixSurfaces.background
        p.backgroundElevated = NetflixSurfaces.raised1
        p.backgroundCard = NetflixSurfaces.raised2
        p.surface = NetflixSurfaces.raised1
        p.surfaceVariant = NetflixSurfaces.raised3
        p.panel = NetflixSurfaces.raised1
        p.field = NetflixSurfaces.raised2
        p.overlay = Color.black.opacity(0.85)

        // ── Text ramp (§5.3) ──
        p.textPrimary = NetflixSurfaces.textPrimary
        p.textSecondary = NetflixSurfaces.textSecondary
        p.textTertiary = NetflixSurfaces.textTertiary
        return p
    }
}

// MARK: - Motion (§8)

/// Netflix-theme motion: the SAME two curves as Fusion (enter
/// cubic-bezier(0.22,1,0.36,1), exit (0.4,0,0.6,1)) with the spec's own
/// durations — controlled, fast, confident; nothing bouncy.
enum NetflixMotion {
    static func enter(_ d: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: d) }
    static func exit(_ d: Double) -> Animation { .timingCurve(0.4, 0, 0.6, 1, duration: d) }

    static let focusEntry = enter(0.22)
    static let focusExit = exit(0.165)
    static let focusMove = enter(0.20)
    static let focusMoveFast = enter(0.15)      // rapid row navigation (§12)
    static let pressDown = enter(0.085)
    static let pressRelease = exit(0.125)
    static let navFocus = enter(0.175)
    static let pageEnter = enter(0.32)
    static let pageExit = exit(0.22)
    static let cardToDetail = enter(0.36)
    static let heroCrossfade = enter(0.50)
    static let heroManual = enter(0.40)
    static let heroRapid = enter(0.24)
    static let dialogEnter = enter(0.23)
    static let dialogExit = exit(0.175)
    static let toastEnter = enter(0.21)
    static let toastExit = exit(0.19)
    static let controlsAppear = enter(0.18)
    static let controlsDismiss = exit(0.25)
    static let artworkFadeIn = enter(0.26)

    /// §26 hero pacing: slower, more cinematic than Fusion's 9 s dwell model.
    static let heroInitialIdleSeconds: Double = 8
    static let heroDwellSeconds: Double = 7
    /// §32 default preview-autoplay idle delay.
    static let previewDelaySeconds: Double = 2.5
    static let toastVisibleSeconds: Double = 2.6
    /// §37 expanded-card stability delay.
    static let expandedCardDelaySeconds: Double = 0.45
}

// MARK: - Focus geometry (§9)

/// Netflix-theme focus treatment constants. Note §9's brightness/saturation
/// deltas are implemented as flat overlays (unfocused dim ≈ black 0.13), NOT
/// `.brightness()/.saturation()` filters — those are per-frame offscreen
/// passes the A8/A10X can't afford (see the Fusion perf pass).
enum NetflixFocus {
    static let portraitScale: CGFloat = 1.075
    static let portraitLift: CGFloat = -7
    static let landscapeScale: CGFloat = 1.09
    static let landscapeLift: CGFloat = -8
    /// Reduced scale while scrubbing focus rapidly (§12).
    static let rapidScale: CGFloat = 1.025
    static let borderWidth: CGFloat = 2
    static let borderColor = Color.white.opacity(0.90)
    /// Flat-overlay stand-in for §9.3's unfocused brightness 0.84–0.89.
    static let unfocusedDim: Double = 0.13
    static func shadow(_ focused: Bool) -> Color { .black.opacity(focused ? 0.72 : 0) }
}
