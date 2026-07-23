import SwiftUI

// Hulu theme — the left sidebar, ported from HuluTV's `SidebarNav`. Collapsed it
// shows icons only; on focus it expands over a scrim to reveal the profile
// header, labels and the wordmark. Focus is the accent rounded outline; the
// current page is bold white. Uses the Orivio focus-binding contract so
// Back-to-open / Right-to-exit / snap-to-current-tab all work.

/// The sidebar destinations, top-to-bottom (HuluTV's `Section`).
enum HuluSection: String, CaseIterable, Identifiable {
    case search   = "Search"
    case home     = "Home"
    case tv       = "TV"
    case movies   = "Movies"
    case news     = "News"
    case myStuff  = "My Stuff"
    case hubs     = "Hubs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .search:   return "magnifyingglass"
        case .home:     return "house"
        case .tv:       return "tv"
        case .movies:   return "film"
        case .news:     return "doc.text"
        case .myStuff:  return "checkmark.square"
        case .hubs:     return "square.grid.2x2"
        case .settings: return "gearshape.fill"
        }
    }
}

struct HuluSidebarNav: View {
    @EnvironmentObject private var profiles: ProfileStore
    @Binding var selection: HuluSection
    var focusBinding: FocusState<HuluSidebarNav.Row?>.Binding
    var onProfile: () -> Void = {}
    var onSelectSection: (HuluSection) -> Void = { _ in }

    enum Row: Hashable { case profile, section(HuluSection) }

    private var expanded: Bool { focusBinding.wrappedValue != nil }
    static let collapsedWidth: CGFloat = 120
    static let expandedWidth: CGFloat = 380
    private var width: CGFloat { expanded ? Self.expandedWidth : Self.collapsedWidth }

    var body: some View {
        ZStack(alignment: .leading) {
            // Always mounted with an animated opacity so it fades in IN LOCKSTEP
            // with the panel's width (a `.transition` popped ahead of the width).
            LinearGradient(stops: [
                .init(color: HuluStyle.stageDeep.opacity(0.98), location: 0.0),
                .init(color: HuluStyle.stageDeep.opacity(0.95), location: 0.3),
                .init(color: HuluStyle.stage.opacity(0.55), location: 0.5),
                .init(color: .clear, location: 0.78)
            ], startPoint: .leading, endPoint: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(expanded ? 1 : 0)

            VStack(alignment: .leading, spacing: 4) {
                HuluProfileRow(profile: profiles.active, expanded: expanded, width: width,
                               focusBinding: focusBinding, action: onProfile)
                    .opacity(expanded ? 1 : 0)
                    .disabled(!expanded)

                Spacer(minLength: 16)

                ForEach(HuluSection.allCases) { s in
                    HuluRowButton(icon: s.icon, label: s.rawValue, expanded: expanded,
                                  selected: selection == s, width: width, row: .section(s),
                                  focusBinding: focusBinding) { onSelectSection(s); selection = s }
                }

                Spacer(minLength: 16)

                HuluWordmark(size: 34)
                    .padding(.leading, 46)
                    .opacity(expanded ? 1 : 0)
                    .frame(height: 44)
            }
            .defaultFocus(focusBinding, .section(selection))
            .padding(.vertical, 44)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .ignoresSafeArea()
        .animation(PerformanceSettingsStore.shared.sidebarAnimationEffective
                   ? .spring(response: 0.34, dampingFraction: 0.86) : nil, value: expanded)
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && focusBinding.wrappedValue == nil {
                focusBinding.wrappedValue = .section(selection)
            }
        }
    }
}

private struct HuluProfileRow: View {
    @Environment(\.isFocused) private var isFocused
    let profile: UserProfile
    let expanded: Bool
    let width: CGFloat
    var focusBinding: FocusState<HuluSidebarNav.Row?>.Binding
    let action: () -> Void
    private let edge: CGFloat = 40

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                ProfileAvatarView(profile: profile, size: 56)
                if expanded {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                        Text("Switch").font(.system(size: 20)).foregroundStyle(HuluStyle.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, edge - 6)
            .frame(width: width, alignment: .leading)
            .huluFocusRing(isFocused && expanded, cornerRadius: 14)
        }
        .buttonStyle(.huluFlat)
        .focused(focusBinding, equals: .profile)
    }
}

private struct HuluRowButton: View {
    let icon: String
    let label: String
    let expanded: Bool
    let selected: Bool
    let width: CGFloat
    let row: HuluSidebarNav.Row
    var focusBinding: FocusState<HuluSidebarNav.Row?>.Binding
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HuluRowLabel(icon: icon, label: label, expanded: expanded, selected: selected, width: width)
        }
        .buttonStyle(.huluFlat)
        .focused(focusBinding, equals: row)
    }
}

private struct HuluRowLabel: View {
    @Environment(\.isFocused) private var isFocused
    let icon: String
    let label: String
    let expanded: Bool
    let selected: Bool
    let width: CGFloat

    private let edge: CGFloat = 46
    private var active: Bool { selected || isFocused }

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: selected ? .semibold : .regular))
                .foregroundStyle(active ? .white : HuluStyle.textTertiary)
                .frame(width: 40, height: 40)
            // Kept in the tree and faded via opacity (not `if expanded`) so the
            // label fades in IN LOCKSTEP with the panel's gradient/width — a
            // conditional insert popped the words in ahead of the gradient.
            Text(label)
                .font(.system(size: 28, weight: selected ? .bold : .medium))
                .foregroundStyle(active ? .white : HuluStyle.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .opacity(expanded ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.leading, edge)
        .frame(width: width, alignment: .leading)
        .clipped()
        .huluFocusRing(isFocused && expanded, cornerRadius: 12)
    }
}
