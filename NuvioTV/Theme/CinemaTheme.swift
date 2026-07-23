import SwiftUI

// Cinema theme — its OWN palette + design tokens. Reuses nothing from the
// retired Modern/Nova themes. A deep graphite cinematic stage; focus is marked
// by a bright white edge + accent glow + a lift, so every focusable element
// reads clearly as selected.

enum CinemaPalette {
    /// Rebuild `base` with the Cinema graphite surfaces. Keeps the user's chosen
    /// accent (base.secondary) so focus glows track it.
    static func adapt(_ base: ThemePalette, amoled: Bool) -> ThemePalette {
        var p = base

        if amoled {
            p.background = Color(hex: 0x000000)
            p.backgroundElevated = Color(hex: 0x0A0A0C)
            p.backgroundCard = Color(hex: 0x131418)
            p.surface = Color(hex: 0x0A0A0C)
            p.surfaceVariant = Color(hex: 0x17181C)
            p.panel = Color(hex: 0x0A0A0C)
            p.field = Color(hex: 0x131418)
        } else {
            p.background = Color(hex: 0x141619)          // deep graphite stage
            p.backgroundElevated = Color(hex: 0x1C1F24)  // raised panels
            p.backgroundCard = Color(hex: 0x24272E)      // cards / rows
            p.surface = Color(hex: 0x1C1F24)
            p.surfaceVariant = Color(hex: 0x2C3038)
            p.panel = Color(hex: 0x1C1F24)
            p.field = Color(hex: 0x24272E)
        }
        p.overlay = Color.black.opacity(0.72)
        p.textPrimary = Color(hex: 0xF7F8FA)
        p.textSecondary = Color(hex: 0xC0C5CE)
        p.textTertiary = Color(hex: 0x878E99)
        // Focus: a soft white edge + accent-tinted glow (restrained, not neon).
        p.focusRing = Color.white.opacity(0.92)
        p.focusBackground = p.secondary.opacity(0.18)
        p.focusGlow = p.secondary.opacity(0.4)
        return p
    }
}

/// Shared focus/layout constants for Cinema's own components. Tuned for a
/// natural, restrained focus: a gentle lift, a thin white edge, a soft glow.
enum CinemaFocus {
    static let cardRadius: CGFloat = 12
    static let posterScale: CGFloat = 1.045
    static let landscapeScale: CGFloat = 1.03
    static let ringWidth: CGFloat = 2.5
    static let glowRadius: CGFloat = 14
    static let glowOpacity: Double = 0.38
    static let entry: Animation = .spring(response: 0.34, dampingFraction: 0.85)
}
