import SwiftUI

/// Settings → Performance: per-effect switches so slower Apple TVs (HD,
/// 4K 1st gen) can turn off exactly the things causing lag — each row says
/// what the effect costs and what OFF looks like. All ON = the full look.
struct PerformanceSettingsDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var store = PerformanceSettingsStore.shared

    private var s: Binding<PerformanceSettingsStore.Settings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    var body: some View {
        DetailScaffold(title: SettingsCategory.performance.title,
                       subtitle: SettingsCategory.performance.subtitle) {
            SettingsGroupCard(
                title: "Home billboard",
                subtitle: "The hero area at the top of the Home screen"
            ) {
                PerfToggleRow(
                    icon: "photo.tv",
                    title: "Hero backdrop artwork",
                    subtitle: "Full-screen art behind Home that changes with every card you focus — the single heaviest effect on older Apple TVs. Off: flat background; the title, info and rows are unchanged.",
                    isOn: s.heroBackdrop
                )
                PerfToggleRow(
                    icon: "square.stack.3d.forward.dottedline",
                    title: "Hero crossfade",
                    subtitle: "Dissolve animation when the hero art and info change. Blends two full-screen images for almost half a second. Off: they switch instantly.",
                    isOn: s.heroCrossfade
                )
            }

            SettingsGroupCard(
                title: "Cards & rows",
                subtitle: "Posters and the rows they live in"
            ) {
                PerfToggleRow(
                    icon: "rectangle.fill.on.rectangle.fill",
                    title: "Card shadows",
                    subtitle: "Soft drop shadows under posters. The shadow re-renders while a card grows/shrinks, costing GPU time on every focus move. Off: flat cards, same layout.",
                    isOn: s.cardShadows
                )
                PerfToggleRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Focus zoom",
                    subtitle: "The focused card springs slightly larger. Off: only the highlight ring marks focus — the cheapest possible focus effect.",
                    isOn: s.focusZoom
                )
            }

            SettingsGroupCard(
                title: "Animations",
                subtitle: "Motion across the app's chrome"
            ) {
                PerfToggleRow(
                    icon: "sidebar.left",
                    title: "Sidebar animation",
                    subtitle: "The sidebar's expand/collapse spring and the dim it casts over the content — a full-screen fade composited on every open/close. Off: the sidebar and dim appear/disappear instantly.",
                    isOn: s.sidebarAnimation
                )
                PerfToggleRow(
                    icon: "hand.tap",
                    title: "Button & pill effects",
                    subtitle: "Small controls (See All, tab pills, filter chips, button presses) scale and spring when focused or clicked. Off: they highlight instantly with no motion.",
                    isOn: s.buttonAnimations
                )
            }

            SettingsGroupCard(
                title: "Artwork loading",
                subtitle: "How poster images arrive on screen"
            ) {
                PerfToggleRow(
                    icon: "square.and.arrow.down.on.square",
                    title: "Preload row artwork",
                    subtitle: "Downloads posters for rows below the fold in the background so they're ready when you scroll. Off: less background work while browsing, but posters load as they appear.",
                    isOn: s.artworkPrefetch
                )
                PerfToggleRow(
                    icon: "circle.lefthalf.filled",
                    title: "Artwork fade-in",
                    subtitle: "Posters fade in when they finish loading; each fade re-renders its card for the duration. Off: artwork pops in instantly.",
                    isOn: s.artworkFadeIn
                )
            }

            Text("Everything ON is the app's full look. Turn things OFF top-to-bottom until the Home screen feels right — each switch only removes visual polish, never content or features. These switches are per-device and don't sync to your account.")
                .font(.system(size: 18))
                .foregroundStyle(theme.palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Toggle row matching the Playback pane's rows (icon, title, wrapped
/// description, switch).
private struct PerfToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            PerfToggleLabel(icon: icon, title: title, subtitle: subtitle, isOn: isOn)
        }
        .buttonStyle(PlainCardButtonStyle())
    }
}

private struct PerfToggleLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let icon: String
    let title: String
    let subtitle: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: NuvioSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(theme.palette.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 19))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            NuvioSwitch(isOn: isOn)
        }
        .padding(.horizontal, NuvioSpacing.lg)
        .padding(.vertical, NuvioSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: theme.settingsRowRadius, style: .continuous)
                .fill(isFocused ? theme.palette.focusBackground : .clear)
        )
    }
}
