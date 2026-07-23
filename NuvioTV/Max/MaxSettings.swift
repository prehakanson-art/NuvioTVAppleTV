import SwiftUI

// Max theme — a settings screen styled to fit the Max look (a left section menu +
// a right detail pane, MaxTV's SettingsView layout) but wired to Orivio's REAL
// settings: the left menu lists every `SettingsCategory` and the right pane is
// the SAME shared detail view Orivio's other surfaces use, so ALL settings are
// available (Appearance, Themes, Layout, Playback, Integrations, Performance,
// Account, …) — not a cut-down subset.
struct MaxSettingsView: View {
    @EnvironmentObject private var theme: ThemeManager

    @State private var selected: SettingsCategory = .appearance
    @FocusState private var firstMenu: Bool

    /// Same visibility rule as Orivio's settings rail (hide advanced-only panes
    /// in Essential experience mode).
    private var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { theme.experienceMode.isAdvanced || !$0.isAdvanced }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings").font(MaxStyle.hero(52)).foregroundStyle(.white)
                .padding(.top, 40)

            HStack(alignment: .top, spacing: 70) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(categories.enumerated()), id: \.element) { idx, c in
                            MaxMenuRow(title: c.title, icon: c.icon, selected: selected == c,
                                       focus: idx == 0 ? $firstMenu : nil) { selected = c }
                        }
                    }
                }
                .frame(width: 440)
                // Sectioned so Right from ANY menu row enters the pane's nearest
                // control (not only when one lines up in y).
                .focusSection()

                ScrollView(.vertical, showsIndicators: false) {
                    pane(for: selected)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.trailing, 60)
                }
                .focusSection()
            }
        }
        .padding(.leading, 60).padding(.trailing, 40)
        .maxPullFocusOnAppear($firstMenu)
    }

    /// The shared Orivio detail pane for a category (identical to what the ATV
    /// settings surface shows) so every setting works.
    @ViewBuilder private func pane(for category: SettingsCategory) -> some View {
        switch category {
        case .account:           AccountSettingsDetail()
        case .appearance:        AppearanceDetail()
        case .themes:            ThemesDetail()
        case .layout:            LayoutSettingsDetail()
        case .contentDiscovery:  ContentDiscoveryDetail()
        case .integration:       IntegrationsDetail()
        case .plugins:           PluginsSettingsDetail()
        case .trakt:             TraktDetail()
        case .about:             AboutDetail()
        case .playback:          PlaybackSettingsDetail()
        case .performance:       PerformanceSettingsDetail()
        }
    }
}

private struct MaxMenuRow: View {
    let title: String
    let icon: String
    let selected: Bool
    var focus: FocusState<Bool>.Binding? = nil
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(selected ? .black : .white)
                    .frame(width: 30)
                Text(title)
                    .font(.system(size: 28, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? .black : .white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.white : (focused ? MaxStyle.surfaceHi : .clear)))
        }
        .buttonStyle(.maxFlat).focused($focused).maxExternalFocus(focus)
    }
}
