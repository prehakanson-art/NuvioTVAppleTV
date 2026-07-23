import SwiftUI

// Stremio's Settings — a custom flat, sectioned list (reconstructed from the
// IPA's SettingsVC / SettingsCell): a left-aligned "Settings" title over
// grouped rows (icon + label on a rounded card, value/chevron on the right)
// on the navy stage. NOT the Classic workspace-card + rail. Rows push the
// SAME shared detail panes so every option stays reachable.

struct StremioSettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    var onOpenProfiles: () -> Void = {}
    var onBackAtRoot: () -> Void = {}

    private var generalCategories: [SettingsCategory] {
        let hidden: Set<SettingsCategory> = [.appearance, .themes, .account]
        return SettingsCategory.allCases.filter {
            !hidden.contains($0) && (theme.experienceMode.isAdvanced || !$0.isAdvanced)
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 34) {
                Text("Settings")
                    .font(StremioFont.bold(48))
                    .foregroundStyle(StremioSurfaces.textPrimary)
                    .padding(.top, 40)

                section("APPEARANCE") {
                    row(.themes, title: "Theme", value: theme.appTheme.displayName, icon: "paintbrush.fill")
                    row(.appearance, title: "Accent & Font", value: theme.palette.displayName, icon: "paintpalette.fill")
                }

                section("ACCOUNT") {
                    row(.account, title: "Account", icon: "person.crop.circle.fill")
                    plainRow(title: "Switch Profile", icon: "person.2.fill", action: onOpenProfiles)
                }

                section("GENERAL") {
                    ForEach(generalCategories) { category in
                        row(category, title: category.title, icon: category.icon)
                    }
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(.leading, 60)
            .padding(.trailing, 70)
            .padding(.bottom, 90)
        }
        .scrollClipDisabled()
        .background(StremioSurfaces.background.ignoresSafeArea())
        .navigationDestination(for: SettingsCategory.self) { pane(for: $0) }
        .onExitCommand(perform: onBackAtRoot)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(StremioFont.bold(20))
                .tracking(1.2)
                .foregroundStyle(StremioSurfaces.accentBright)
                .padding(.leading, 6)
            VStack(spacing: 10) { content() }
        }
        .focusSection()
    }

    private func row(_ category: SettingsCategory, title: String, value: String? = nil, icon: String) -> some View {
        NavigationLink(value: category) {
            StremioSettingsRow(icon: icon, title: title, value: value, showChevron: true)
        }
        .buttonStyle(PlainCardButtonStyle())
    }

    private func plainRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            StremioSettingsRow(icon: icon, title: title, value: nil, showChevron: false)
        }
        .buttonStyle(PlainCardButtonStyle())
    }

    @ViewBuilder
    private func pane(for category: SettingsCategory) -> some View {
        Group {
            switch category {
            case .account: AccountSettingsDetail()
            case .appearance: AppearanceDetail()
            case .themes: ThemesDetail()
            case .layout: LayoutSettingsDetail()
            case .contentDiscovery: ContentDiscoveryDetail()
            case .integration: IntegrationsDetail()
            case .plugins: PluginsSettingsDetail()
            case .trakt: TraktDetail()
            case .about: AboutDetail()
            case .playback: PlaybackSettingsDetail()
            case .performance: PerformanceSettingsDetail()
            }
        }
        .background(StremioSurfaces.background.ignoresSafeArea())
    }
}

private struct StremioSettingsRow: View {
    @Environment(\.isFocused) private var isFocused
    let icon: String
    let title: String
    let value: String?
    let showChevron: Bool

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isFocused ? .white : StremioSurfaces.accentBright)
                .frame(width: 40, alignment: .center)
            Text(title)
                .font(StremioFont.medium(26))
                .foregroundStyle(isFocused ? .white : StremioSurfaces.textPrimary)
            Spacer(minLength: 12)
            if let value {
                Text(value)
                    .font(StremioFont.regular(23))
                    .foregroundStyle(isFocused ? .white.opacity(0.85) : StremioSurfaces.textSecondary)
                    .lineLimit(1)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isFocused ? .white.opacity(0.85) : StremioSurfaces.textTertiary)
            }
        }
        .padding(.horizontal, 26)
        .frame(height: 82)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? StremioSurfaces.accent : StremioSurfaces.card)
        )
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 16, y: 6)
        .scaleEffect(isFocused ? 1.012 : 1)
        .animation(StremioFocus.entry, value: isFocused)
    }
}
