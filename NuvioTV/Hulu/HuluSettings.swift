import SwiftUI

// Hulu theme — settings styled like HuluTV (a left menu with accent-outline
// focus + a right detail pane) but backed by Orivio's REAL settings: the left
// menu lists every `SettingsCategory` and the right pane is the SAME shared
// detail view Orivio's other surfaces use, so ALL settings are available.
struct HuluSettingsView: View {
    @EnvironmentObject private var theme: ThemeManager

    @State private var selected: SettingsCategory = .appearance
    @FocusState private var firstMenu: Bool

    private var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { theme.experienceMode.isAdvanced || !$0.isAdvanced }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(categories.enumerated()), id: \.element) { idx, c in
                        HuluMenuRow(text: c.title, selected: selected == c,
                                    focus: idx == 0 ? $firstMenu : nil) { selected = c }
                    }
                }
            }
            .frame(width: 440)
            // Sectioned so pressing Right from ANY menu row jumps into the pane's
            // nearest control (not only when a control happens to line up in y).
            .focusSection()

            ScrollView(.vertical, showsIndicators: false) {
                pane(for: selected)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 40)
            }
            .focusSection()

            HuluWordmark(size: 30)
        }
        .padding(.leading, 130).padding(.top, 60).padding(.trailing, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .huluPullFocusOnAppear($firstMenu)
    }

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

private struct HuluMenuRow: View {
    let text: String
    let selected: Bool
    var focus: FocusState<Bool>.Binding? = nil
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 34, weight: selected ? .semibold : .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.vertical, 14)
                .huluFocusRing(focused, cornerRadius: 12, lineWidth: 4)
        }
        .buttonStyle(.huluFlat).focused($focused).huluExternalFocus(focus)
    }
}
