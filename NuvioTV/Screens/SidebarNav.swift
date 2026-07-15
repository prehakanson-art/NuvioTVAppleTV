import SwiftUI

/// The four primary destinations, matching the APK's left sidebar order.
enum AppTab: Int, CaseIterable, Identifiable {
    case home, search, library, settings
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "bookmark.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Left-edge navigation rail, an exact match of the Android APK's
/// `SidebarNavigation`. Collapsed = **icons only, vertically centered, no
/// profile**. On focus it expands rightward into an elevated panel showing the
/// **profile avatar + name at the top** and the nav items with labels; the
/// focused/selected item is a **light translucent capsule fill** (no border
/// ring, no scale). The parent dims the content behind it.
struct SidebarNav: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    @Binding var selected: Int
    var focusBinding: FocusState<Int?>.Binding
    var onProfileTap: () -> Void = {}
    /// Fires when a tab is tapped, BEFORE `selected` is mutated, so the root
    /// can tell whether this is actually a change of tab (vs. re-tapping the
    /// tab you're already on) and react accordingly.
    var onTabSelected: (Int) -> Void = { _ in }

    var expanded: Bool { focusBinding.wrappedValue != nil }

    static let collapsedWidth: CGFloat = 64
    static let expandedWidth: CGFloat = 270

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile header — visible only when expanded, but its SPACE is
            // always reserved so the nav icons sit at the exact same vertical
            // position in both states (the APK's icons never shift).
            Group {
                if expanded {
                    Button(action: onProfileTap) {
                        SidebarProfileHeader(profile: profiles.active)
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .focused(focusBinding, equals: -1)
                    // Fade in with the expansion instead of popping.
                    .transition(.opacity)
                } else {
                    SidebarProfileHeader(profile: profiles.active).opacity(0)
                }
            }
            .padding(.top, NuvioSpacing.xl)
            .padding(.leading, expanded ? NuvioSpacing.sm : 0)

            Spacer(minLength: 0)

            // Nav items, vertically centered as a group (generous spacing like the APK).
            VStack(alignment: .leading, spacing: 22) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        // Fire BEFORE mutating `selected` so the root can still
                        // see which tab we're coming FROM.
                        onTabSelected(tab.rawValue)
                        selected = tab.rawValue
                        // NOTE: do NOT clear focusBinding here — unfocusing
                        // with no destination makes the engine grab the nearest
                        // candidate (the profile button above). The root
                        // force-moves focus into content instead.
                    } label: {
                        SidebarItemLabel(tab: tab, selected: selected == tab.rawValue, expanded: expanded)
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .focused(focusBinding, equals: tab.rawValue)
                }
            }
            .padding(.horizontal, expanded ? NuvioSpacing.sm : 0)
            // Entering the sidebar lands on the tab you're on, not a stale row.
            .defaultFocus(focusBinding, selected)

            Spacer(minLength: 0)
        }
        // The panel column changes width (collapsed icons ⇄ expanded labels).
        .frame(width: expanded ? Self.expandedWidth : Self.collapsedWidth, alignment: .leading)
        // Clip to the ANIMATING width: in the overlay layout nothing squeezes
        // the labels anymore, so without this they render at their final
        // position the instant they're inserted — visible over the content
        // before the panel has expanded. Clipped, the expanding edge reveals
        // them in sync with the motion.
        .clipped()
        .frame(maxHeight: .infinity, alignment: .top)
        // Elevated panel only when expanded; collapsed rail is transparent over content.
        .background(
            (expanded ? theme.palette.backgroundElevated : Color.clear).ignoresSafeArea()
        )
        .animation(PerformanceSettingsStore.shared.sidebarAnimationEffective
                   ? .spring(response: 0.34, dampingFraction: 0.86) : nil, value: expanded)
        // On ENTRY (collapsed → expanded), snap focus to the current tab —
        // tvOS otherwise lands on the geometrically nearest row, which feels
        // like a stale position when the user was scrolled down in content.
        // Later up/down moves inside the panel are untouched.
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && focusBinding.wrappedValue != selected {
                focusBinding.wrappedValue = selected
            }
        }
    }

}

/// The tappable profile chip at the top of the expanded sidebar. Highlights
/// (capsule fill + accent ring) on focus so it's clear it's selectable — it
/// opens the "Who's watching" / account screen.
private struct SidebarProfileHeader: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let profile: UserProfile

    var body: some View {
        HStack(spacing: NuvioSpacing.sm) {
            // Use the shared ProfileAvatarView so a catalog-chosen avatar
            // (stored as avatarID) resolves through the store and REPLACES the
            // colored initial — the badge here read profile.avatarURL directly,
            // which is nil for catalog avatars, so it always fell back to the
            // letter.
            ProfileAvatarView(profile: profile, size: 56)
            Text(profile.name)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NuvioSpacing.sm)
        .frame(height: 68)
        .background(
            Capsule(style: .continuous)
                .fill(isFocused ? Color.white.opacity(0.15) : .clear)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
        )
    }
}

/// A single rail entry: icon (+ label when expanded). Focused/selected shows a
/// light translucent capsule fill (APK style — no border, no scale).
private struct SidebarItemLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let tab: AppTab
    let selected: Bool
    let expanded: Bool

    private var highlighted: Bool { isFocused || selected }

    var body: some View {
        HStack(spacing: NuvioSpacing.sm) {
            Image(systemName: tab.icon)
                .font(.system(size: expanded ? 30 : 38, weight: .semibold))
                .foregroundStyle(highlighted ? theme.palette.textPrimary : theme.palette.textSecondary)
                .frame(width: expanded ? 40 : nil, alignment: .center)

            if expanded {
                Text(tab.label)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(highlighted ? theme.palette.textPrimary : theme.palette.textSecondary)
                    .lineLimit(1)
                    // Fade with the expansion spring (and out on collapse)
                    // instead of popping in/out structurally.
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        // Collapsed: icons sit just LEFT of the rail's center (a gentle nudge
        // off the original centered position — not jammed against the edge).
        // Leading-aligned with a 6pt inset ≈ 7pt left of dead-center.
        .padding(.leading, expanded ? NuvioSpacing.md : 6)
        .padding(.trailing, expanded ? NuvioSpacing.md : 0)
        .frame(height: 80)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Capsule fill on the focused/selected item, only in the expanded panel.
            Capsule(style: .continuous)
                .fill(expanded && highlighted ? Color.white.opacity(0.15) : .clear)
        )
    }
}

