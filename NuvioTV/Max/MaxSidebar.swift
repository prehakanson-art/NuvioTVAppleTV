import SwiftUI

// Max theme — the left sidebar, ported VERBATIM from MaxTV's `MaxTopNav`
// (SidebarNav). Collapsed it shows only icons in a fixed left strip, vertically
// centered; when any item takes focus it expands over the SAME see-through
// multi-stop gradient MaxTV uses, revealing the profile header, "My Stuff",
// labels and "Settings" — the icons stay put (same x/y). Sizes/insets/gradient
// are 1:1 with MaxTV. It exposes the Orivio focus-binding contract
// (`selection` + `focusBinding`) so Back-to-open / Right-to-exit work.

/// The sidebar destinations, top-to-bottom.
enum MaxSection: String, CaseIterable, Identifiable {
    case search     = "Search"
    case home       = "Home"
    case series     = "Series"
    case movies     = "Movies"
    case liveTV     = "Live TV"
    case categories = "Categories"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .search:     return "magnifyingglass"
        case .home:       return "house.fill"
        case .series:     return "tv"
        case .movies:     return "film"
        case .liveTV:     return "dot.radiowaves.left.and.right"
        case .categories: return "square.grid.2x2"
        }
    }
}

struct MaxSidebarNav: View {
    @EnvironmentObject private var profiles: ProfileStore
    @Binding var selection: MaxSection
    /// nil = a special screen (My Stuff / Settings) is showing; no section pill.
    var specialSelected: Bool
    var focusBinding: FocusState<MaxSidebarNav.Row?>.Binding
    var onProfile: () -> Void = {}
    var onMyStuff: () -> Void = {}
    var onSettings: () -> Void = {}
    var onSelectSection: (MaxSection) -> Void = { _ in }

    enum Row: Hashable { case profile, myStuff, section(MaxSection), settings }

    private var expanded: Bool { focusBinding.wrappedValue != nil }
    static let collapsedWidth: CGFloat = 120
    static let expandedWidth: CGFloat = 470
    private var width: CGFloat { expanded ? Self.expandedWidth : Self.collapsedWidth }

    var body: some View {
        ZStack(alignment: .leading) {
            // Full-width see-through scrim — the exact MaxTV gradient: dark and
            // readable across the menu column, fading into the content so the
            // artwork stays slightly visible.
            if expanded {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.97), location: 0.0),
                    .init(color: .black.opacity(0.92), location: 0.26),
                    .init(color: .black.opacity(0.45), location: 0.44),
                    .init(color: .clear,               location: 0.68)
                ], startPoint: .leading, endPoint: .trailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Single column so up/down focus traverses in reading order. The
            // profile/My-Stuff header and the Settings footer always reserve
            // their space (hidden + non-focusable when collapsed), so the eight
            // nav icons keep the exact same position whether collapsed or open.
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    MaxRowButton(row: .profile, avatar: profiles.active, label: profiles.active.name,
                                 expanded: expanded, selected: false, width: width,
                                 focusBinding: focusBinding) { onProfile() }
                    MaxRowButton(row: .myStuff, icon: "bookmark", label: "My Stuff",
                                 expanded: expanded, selected: specialSelected, width: width,
                                 focusBinding: focusBinding) { onMyStuff() }
                }
                .opacity(expanded ? 1 : 0)
                .disabled(!expanded)

                Spacer(minLength: 20)

                ForEach(MaxSection.allCases) { s in
                    MaxRowButton(row: .section(s), icon: s.icon, label: s.rawValue,
                                 expanded: expanded, selected: !specialSelected && selection == s,
                                 width: width, focusBinding: focusBinding) {
                        onSelectSection(s); selection = s
                    }
                }

                Spacer(minLength: 20)

                MaxRowButton(row: .settings, icon: "gearshape", label: "Settings",
                             expanded: expanded, selected: false, width: width,
                             focusBinding: focusBinding) { onSettings() }
                    .opacity(expanded ? 1 : 0)
                    .disabled(!expanded)
            }
            .defaultFocus(focusBinding, .section(selection))
            .padding(.vertical, 50)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .ignoresSafeArea()
        .animation(PerformanceSettingsStore.shared.sidebarAnimationEffective
                   ? .easeOut(duration: 0.22) : nil, value: expanded)
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && focusBinding.wrappedValue == nil {
                focusBinding.wrappedValue = .section(selection)
            }
        }
    }
}

private struct MaxRowButton: View {
    let row: MaxSidebarNav.Row
    var icon: String? = nil
    var avatar: UserProfile? = nil
    let label: String
    let expanded: Bool
    let selected: Bool
    let width: CGFloat
    var focusBinding: FocusState<MaxSidebarNav.Row?>.Binding
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MaxRowLabel(icon: icon, avatar: avatar, label: label,
                        expanded: expanded, selected: selected, width: width)
        }
        .buttonStyle(.maxFlat)
        .focused(focusBinding, equals: row)
    }
}

private struct MaxRowLabel: View {
    @Environment(\.isFocused) private var isFocused
    var icon: String? = nil
    var avatar: UserProfile? = nil
    let label: String
    let expanded: Bool
    let selected: Bool
    let width: CGFloat

    /// Fixed leading inset for the glyph — identical collapsed and expanded, so
    /// the icons never shift horizontally when the panel opens.
    private let edge: CGFloat = 46

    var body: some View {
        HStack(spacing: 24) {
            glyph.frame(width: 44, height: 44)
            if expanded {
                Text(label)
                    .font(.system(size: 30, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected || isFocused ? .white : MaxStyle.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 13)
        .padding(.leading, edge)
        .frame(width: width, alignment: .leading)
        // Selection bar overlays to the left of the icon without shifting it.
        .overlay(alignment: .leading) {
            if expanded && selected {
                Rectangle().fill(.white).frame(width: 4, height: 28)
                    .padding(.leading, edge - 22)
            }
        }
    }

    @ViewBuilder private var glyph: some View {
        let active = selected || isFocused
        if let avatar {
            ProfileAvatarView(profile: avatar, size: 44)
                .overlay(Circle().strokeBorder(isFocused ? .white : .clear, lineWidth: 3))
        } else if let icon {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(active ? .white : MaxStyle.textTertiary)
        }
    }
}
