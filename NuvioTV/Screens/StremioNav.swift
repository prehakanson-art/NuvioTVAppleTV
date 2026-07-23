import SwiftUI

// Stremio's left icon TabBar (reconstructed from the IPA's
// tvOS/TabBar/TabBarController + TabBarIconView). A persistent thin rail of
// icons on the left edge with the purple Stremio diamond at the top; focusing
// into it expands the rail rightward to reveal labels, and the current
// destination is a filled purple pill. Content always sits BESIDE the rail
// (Stremio's board is never full-bleed under it).
//
// Renders only inside `NuvioTVApp.stremioLayout`; mechanically it mirrors the
// proven SidebarNav focus-binding contract, so every navigation feature
// (Back-to-open, Left-to-open, Right-to-exit, tab select) works unchanged.

struct StremioNav: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var liveTV = LiveTVSettingsStore.shared
    @Binding var selected: Int
    var focusBinding: FocusState<Int?>.Binding
    var onProfileTap: () -> Void = {}
    var onTabSelected: (Int) -> Void = { _ in }

    var expanded: Bool { focusBinding.wrappedValue != nil }

    static let collapsedWidth: CGFloat = 108
    static let expandedWidth: CGFloat = 340

    /// Stremio's real tvOS tab set (Board · Discover · Library · Search ·
    /// Addons · Settings), with the same icon names Stremio ships
    /// (house / safari / square.stack / gear) — outline when unselected,
    /// filled when selected, exactly like the app. Discover (10) and Addons
    /// (11) are Stremio-only sections, not app tabs.
    private var tabs: [(id: Int, label: String, icon: String, iconFilled: String)] {
        [
            (1, "Search", "magnifyingglass", "magnifyingglass"),
            (0, "Board", "house", "house.fill"),
            (10, "Discover", "safari", "safari.fill"),
            (2, "Library", "square.stack", "square.stack.fill"),
            (11, "Addons", "puzzlepiece.extension", "puzzlepiece.extension.fill"),
            (3, "Settings", "gearshape", "gearshape.fill")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Orivio logo crowns the rail (wordmark when expanded).
            StremioWordmark(expanded: expanded)
                .padding(.top, 40)
                .padding(.bottom, 8)

            // Profile chip — expanded only; opens "Who's watching".
            Button(action: onProfileTap) {
                StremioNavProfile(profile: profiles.active, expanded: expanded)
            }
            .buttonStyle(PlainCardButtonStyle())
            .focused(focusBinding, equals: -1)
            .opacity(expanded ? 1 : 0)
            .disabled(!expanded)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(tabs, id: \.id) { tab in
                    Button {
                        onTabSelected(tab.id)
                        selected = tab.id
                    } label: {
                        StremioNavRow(icon: tab.icon, iconFilled: tab.iconFilled, label: tab.label,
                                      selected: selected == tab.id, expanded: expanded)
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .focused(focusBinding, equals: tab.id)
                }
            }
            .defaultFocus(focusBinding, selected)

            Spacer(minLength: 0)
        }
        .frame(width: expanded ? Self.expandedWidth : Self.collapsedWidth, alignment: .leading)
        .clipped()
        .frame(maxHeight: .infinity, alignment: .top)
        // Expanded: a deep-navy panel that fades out to the RIGHT (a gradient into
        // the content) rather than a hard-edged solid panel.
        .background(alignment: .leading) {
            if expanded {
                LinearGradient(
                    stops: [
                        .init(color: StremioSurfaces.deep, location: 0.0),
                        .init(color: StremioSurfaces.deep, location: 0.5),
                        .init(color: StremioSurfaces.deep.opacity(0), location: 1.0)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: Self.expandedWidth + 190)
                .ignoresSafeArea()
            }
        }
        // Sit the rail closer to the left screen edge (into the overscan area,
        // like the real Stremio rail) instead of fully inside the title-safe box.
        .offset(x: -60)
        .animation(PerformanceSettingsStore.shared.sidebarAnimationEffective
                   ? .spring(response: 0.32, dampingFraction: 0.85) : nil, value: expanded)
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && focusBinding.wrappedValue != selected {
                focusBinding.wrappedValue = selected
            }
        }
    }
}

/// One rail entry. Collapsed: a centered icon (purple when current, gray
/// otherwise, white on focus). Expanded: a full purple pill on the current /
/// focused item with the label beside it.
private struct StremioNavRow: View {
    @Environment(\.isFocused) private var isFocused
    let icon: String
    let iconFilled: String
    let label: String
    let selected: Bool
    let expanded: Bool

    // Stremio's sidebar focus is a warm-WHITE pill with dark text (not the
    // purple accent); the current tab shows white content, everything else gray.
    private var content: Color {
        if isFocused && expanded { return .black }
        if isFocused || selected { return .white }
        return StremioSurfaces.textSecondary
    }
    private var pill: Color {
        if isFocused { return StremioSurfaces.frame }
        return .clear
    }

    var body: some View {
        HStack(spacing: 16) {
            // Outline icon normally; filled variant when it's the current tab.
            Image(systemName: selected ? iconFilled : icon)
                .font(.system(size: expanded ? 28 : 34, weight: .regular))
                .foregroundStyle(content)
                .frame(width: 44, alignment: .center)
            if expanded {
                Text(label)
                    .font(StremioFont.medium(25))
                    .foregroundStyle(content)
                    .lineLimit(1)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, expanded ? 20 : 0)
        .padding(.trailing, expanded ? 22 : 0)
        .frame(height: 66)
        .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(expanded ? pill : .clear)
        )
        // Current tab: a thin WHITE bar at the screen's left edge (like Stremio),
        // shown in both the collapsed and expanded rail.
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(.white)
                    .frame(width: 4, height: 32)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Orivio logo mark (collapsed) / logo + "ORIVIO" wordmark (expanded).
private struct StremioWordmark: View {
    let expanded: Bool
    var body: some View {
        HStack(spacing: 12) {
            OrivioMark()
                .frame(width: 42, height: 42)
                .frame(width: 44, alignment: .center)
            if expanded {
                Text("ORIVIO")
                    .font(StremioFont.bold(24))
                    .tracking(1.5)
                    .foregroundStyle(StremioSurfaces.textPrimary)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, expanded ? 20 : 0)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
        .accessibilityHidden(true)
    }
}

/// The Orivio brand mark, rendered from the app's own logo asset.
struct OrivioMark: View {
    var body: some View {
        Image("OrivioLogo")
            .resizable()
            .scaledToFit()
    }
}

/// Profile chip at the top of the expanded rail.
private struct StremioNavProfile: View {
    @Environment(\.isFocused) private var isFocused
    let profile: UserProfile
    let expanded: Bool

    var body: some View {
        HStack(spacing: 16) {
            ProfileAvatarView(profile: profile, size: 44)
                .overlay(Circle().strokeBorder(isFocused ? StremioSurfaces.accent : .clear, lineWidth: 3))
                .frame(width: 44, alignment: .center)
            if expanded {
                Text(profile.name)
                    .font(StremioFont.medium(24))
                    .foregroundStyle(isFocused ? .white : StremioSurfaces.textSecondary)
                    .lineLimit(1)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, expanded ? 20 : 0)
        .padding(.trailing, expanded ? 22 : 0)
        .frame(height: 60)
        .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused && expanded ? StremioSurfaces.accentFill : .clear)
        )
    }
}
