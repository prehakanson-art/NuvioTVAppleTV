import SwiftUI

// The Netflix-inspired theme's GROUND-UP chrome (NETFLIX_THEME_SPEC.md §17–19):
// its own environmental background and its own custom top navigation — no
// native TabView, no Fusion components. Everything here renders only inside
// `NuvioTVApp.netflixLayout`.

/// §19 environmental background: a stable near-black theater stage. A barely
/// noticeable charcoal ramp plus a faint neutral wash at the upper right — no
/// accent bloom; red stays reserved for active states, and artwork provides
/// the color. Static gradients only (no materials, no filters).
struct NetflixBackground: View {
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ZStack {
            theme.palette.background
            LinearGradient(
                stops: [
                    .init(color: NetflixSurfaces.raised1, location: 0),
                    .init(color: NetflixSurfaces.background, location: 0.58),
                    .init(color: NetflixSurfaces.black, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: 0x787878, alpha: 0.10), .clear],
                center: UnitPoint(x: 0.72, y: 0.12),
                startRadius: 0, endRadius: 950
            )
        }
        .ignoresSafeArea()
    }
}

/// §17 top navigation: logo + destinations + profile chip, floating over the
/// content with a black protection gradient. Resting labels sit at 66% white
/// with the current page full white over a thin accent underline; a focused
/// item goes pure white, scales to 1.045 and widens its underline. Disabled
/// destinations (hidden Live TV) disappear entirely rather than dimming.
///
/// Destinations map to the tabs that exist today — Library surfaces as
/// "My Orivio" (§42). The dedicated TV Shows / Movies / Collections /
/// Discover pages arrive in later sessions and slot into `tabs` here.
struct NetflixTopNav: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var liveTV = LiveTVSettingsStore.shared
    @Binding var selected: Int
    var focusBinding: FocusState<Int?>.Binding
    var onProfileTap: () -> Void = {}
    /// Fires BEFORE `selected` mutates, same contract as SidebarNav.
    var onTabSelected: (Int) -> Void = { _ in }

    /// §17 order, restricted to today's destinations (tab ids match AppTab).
    private var tabs: [(id: Int, label: String)] {
        var items: [(Int, String)] = [(0, "Home"), (2, "My Orivio")]
        if liveTV.enabled { items.append((4, "Live TV")) }
        items.append((1, "Search"))
        items.append((3, "Settings"))
        return items
    }

    var body: some View {
        HStack(spacing: NuvioSpacing.xl + NuvioSpacing.sm) {
            // Orivio's own brand: logo emblem + wordmark in the accent color.
            HStack(spacing: NuvioSpacing.sm) {
                Image("OrivioLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 34)
                Text("ORIVIO")
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(5)
                    .foregroundStyle(theme.palette.secondary)
            }
            .padding(.trailing, NuvioSpacing.md)

            ForEach(tabs, id: \.id) { tab in
                Button {
                    onTabSelected(tab.id)
                    selected = tab.id
                } label: {
                    NetflixNavLabel(text: tab.label, current: selected == tab.id)
                }
                .buttonStyle(NetflixNavButtonStyle())
                .focused(focusBinding, equals: tab.id)
            }

            Spacer(minLength: 0)

            Button(action: onProfileTap) {
                NetflixNavProfileChip(profile: profiles.active)
            }
            .buttonStyle(NetflixNavButtonStyle())
            .focused(focusBinding, equals: -1)
        }
        // §4 safe area (76 px sides at the 1920 reference) and §17 bar
        // position (52–64 px from the top).
        .padding(.horizontal, 76)
        .padding(.top, 42)
        .padding(.bottom, NuvioSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // §17/§21 top protection gradient so the quiet bar reads over bright
        // billboard art without becoming a thick permanent panel.
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.66), location: 0),
                    .init(color: .black.opacity(0.34), location: 0.62),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: [.top, .horizontal])
            .allowsHitTesting(false)
        )
        // Entering the bar lands on the page you're on, not a stale item.
        .onChange(of: focusBinding.wrappedValue != nil) { _, entered in
            if entered, focusBinding.wrappedValue != selected,
               focusBinding.wrappedValue != -1 {
                focusBinding.wrappedValue = selected
            }
        }
    }
}

/// One nav destination: label + underline. Current page keeps a thin accent
/// underline at rest (§17); focus goes pure white and widens it.
private struct NetflixNavLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let text: String
    let current: Bool

    var body: some View {
        VStack(spacing: 7) {
            Text(text)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(isFocused || current
                    ? NetflixSurfaces.textPrimary
                    : NetflixSurfaces.textPrimary.opacity(0.66))
            Capsule()
                .fill(isFocused || current ? theme.palette.secondary : .clear)
                .frame(width: isFocused ? 46 : 26, height: 3)
        }
        .scaleEffect(isFocused ? 1.045 : 1)
        .animation(NetflixMotion.navFocus, value: isFocused)
    }
}

/// The profile chip at the bar's trailing edge — avatar with a focus ring.
private struct NetflixNavProfileChip: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let profile: UserProfile

    var body: some View {
        ProfileAvatarView(profile: profile, size: 46)
            .overlay(
                Circle().strokeBorder(
                    isFocused ? NetflixFocus.borderColor : .clear,
                    lineWidth: NetflixFocus.borderWidth
                )
            )
            .scaleEffect(isFocused ? 1.08 : 1)
            .animation(NetflixMotion.navFocus, value: isFocused)
    }
}

/// §11 press behavior for nav items: compress on press, no other chrome (the
/// label draws its own focus treatment).
private struct NetflixNavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(configuration.isPressed
                       ? NetflixMotion.pressDown : NetflixMotion.pressRelease,
                       value: configuration.isPressed)
    }
}
