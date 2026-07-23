import SwiftUI

// Onyx theme — modelled on the bobsupra/NuvioTVOS tvOS client's look. Its whole
// identity is the FOCUS treatment, not colour: a near-black stage where the
// focused element is marked by a crisp, bright WHITE edge and a subtle white
// wash — no coloured ring, no glow, no lift. Clean, flat, Apple-native.
//
// Rides the shared Classic layout (like Aurora): the recolour lives entirely in
// this palette adapter, so the app's rows/hero/sidebar render unchanged but on
// the Onyx surfaces with a white focus ring. The user's chosen accent still
// shows on ratings/selected states — Onyx only owns the stage + the focus edge.

enum OnyxPalette {
    /// Rebuild `base` with the Onyx near-black surfaces + white focus edge.
    /// Keeps the user's accent (`base.secondary`) so the picker stays honest.
    static func adapt(_ base: ThemePalette, amoled: Bool) -> ThemePalette {
        var p = base

        if amoled {
            p.background = Color(hex: 0x000000)          // true black stage
            p.backgroundElevated = Color(hex: 0x080809)
            p.backgroundCard = Color(hex: 0x101012)
            p.surface = Color(hex: 0x080809)
            p.surfaceVariant = Color(hex: 0x161618)
            p.panel = Color(hex: 0x080809)
            p.field = Color(hex: 0x101012)
        } else {
            p.background = Color(hex: 0x050506)          // charcoal near-black
            p.backgroundElevated = Color(hex: 0x0D0D0F)
            p.backgroundCard = Color(hex: 0x151517)      // cards / rows
            p.surface = Color(hex: 0x0D0D0F)
            p.surfaceVariant = Color(hex: 0x1C1C1F)
            p.panel = Color(hex: 0x0D0D0F)
            p.field = Color(hex: 0x151517)
        }
        p.overlay = Color.black.opacity(0.8)
        p.playerOverlay = Color.black.opacity(0.82)
        p.textPrimary = Color(hex: 0xF7F8FA)
        p.textSecondary = Color.white.opacity(0.7)       // NuvioTVOS uses white/opacity
        p.textTertiary = Color.white.opacity(0.5)
        // The signature: a pure-white focus edge + a faint white wash, and NO
        // glow — the monochrome focus language that defines the look.
        p.focusRing = Color.white
        p.focusBackground = Color.white.opacity(0.16)
        p.focusGlow = .clear
        return p
    }
}
