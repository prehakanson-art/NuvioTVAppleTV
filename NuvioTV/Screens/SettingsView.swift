import SwiftUI

/// Settings categories shown in the left rail. Order, titles, icons and
/// subtitles match the Android app's `SettingsSectionSpec` list exactly.
/// (The APK's mode-gated Experience/Advanced/Debug sections aren't ported —
/// those are unbuilt features.) The APK folds add-ons, catalogs and
/// collections into one "Content & Discovery" section.
enum SettingsCategory: String, CaseIterable, Identifiable {
    // Matches the live APK rail (Essential mode): no Account/Profiles (those
    // live on the sidebar profile avatar). Only categories whose settings are
    // actually wired up are shown — no stub panes.
    case account, appearance, layout, contentDiscovery, integration, playback, trakt, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .appearance: return "Appearance"
        case .layout: return "Layout"
        case .contentDiscovery: return "Content & Discovery"
        case .integration: return "Integrations"
        case .playback: return "Playback"
        case .trakt: return "Trakt"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .account: return "Nuvio account and profiles"
        case .appearance: return "Color theme and dark mode"
        case .layout: return "Home structure and poster styles"
        case .contentDiscovery: return "Add-ons, catalogs, and collections"
        case .integration: return "Manage available integrations"
        case .playback: return "Auto-play and next-episode behavior"
        case .trakt: return "Scrobble and sync your watch history"
        case .about: return "App information, updates, and legal links"
        }
    }

    // SF Symbols matched to the APK's Material icons.
    var icon: String {
        switch self {
        case .account: return "person.crop.circle.fill"
        case .appearance: return "paintpalette.fill"
        case .layout: return "square.grid.2x2.fill"
        case .contentDiscovery: return "safari.fill"
        case .integration: return "link"
        case .playback: return "play.fill"
        case .trakt: return "checkmark.seal.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var account: NuvioAccountManager
    @EnvironmentObject private var trakt: TraktStore
    @FocusState private var railFocus: SettingsCategory?
    /// True while focus is inside the rail; used to tell the entry event apart
    /// from in-rail moves (entry snaps to `selected` instead of previewing).
    @State private var inRail = false

    // Dev: the settings demo opens on Layout (a content-rich, scrollable pane)
    // so the workspace card + grouped cards + fit can be screenshot-verified.
    @State private var selected: SettingsCategory = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-paneAccount") { return .account }
        if args.contains("-paneTrakt") { return .trakt }
        if args.contains("-paneLayout") { return .layout }
        if args.contains("-paneContent") { return .contentDiscovery }
        if args.contains("-paneIntegration") { return .integration }
        if args.contains("-panePlayback") { return .playback }
        if args.contains("-paneAbout") { return .about }
        return .appearance
    }()

    // Matches the APK's default "Classic" settings: everything sits inside a
    // rounded "workspace" card (inset from the screen edges, faint border) with
    // a vertical rail of tall pill buttons on the LEFT and the detail pane on
    // the RIGHT. Focusing a rail pill live-previews its detail (as the APK
    // does); both regions are focus sections so Right enters the detail and
    // Left returns to the rail without locking up.
    var body: some View {
        HStack(alignment: .top, spacing: NuvioSpacing.xl) {
            rail
            detail
                .frame(maxWidth: 900, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
        }
        .padding(NuvioSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The APK "workspace" card: rounded (28dp), BackgroundElevated fill,
        // hairline border, inset from the screen edges on near-black. Content is
        // CLIPPED to the card so scrolled detail rows never spill outside it.
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.palette.backgroundElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(NuvioPrimitives.neutral750, lineWidth: 1)
        )
        .padding(.horizontal, NuvioSpacing.xxl)
        .padding(.vertical, NuvioSpacing.xl)
        .background(theme.palette.background.ignoresSafeArea())
    }

    // MARK: - Vertical rail (Classic — tall pills)

    private var rail: some View {
        // 220dp rail, pills vertically centered (matches the APK's
        // spacedBy(10, CenterVertically)). 10 categories fit at 56dp each.
        VStack(spacing: NuvioSpacing.sm) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selected = category
                } label: {
                    SettingsRailButton(category: category, selected: selected == category)
                }
                .buttonStyle(PlainCardButtonStyle())
                .focused($railFocus, equals: category)
                // Live-preview: focusing a pill shows its detail (APK behavior)
                // — EXCEPT on the entry event. tvOS enters the rail at the
                // geometrically nearest pill; snapping back to `selected` there
                // keeps the pane you were on. Later moves preview normally.
                .onFocusChange { focused in
                    guard focused else { return }
                    if inRail {
                        selected = category
                    } else {
                        inRail = true
                        if category != selected { railFocus = selected }
                    }
                }
            }
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .center)
        .focusSection()
        // Entering the rail lands on the pane you're viewing, not a stale row.
        .defaultFocus($railFocus, selected)
        .onChange(of: railFocus) { _, newValue in
            if newValue == nil { inRail = false }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selected {
        case .account:
            AccountSettingsDetail()
        case .appearance:
            AppearanceDetail()
        case .layout:
            LayoutSettingsDetail()
        case .contentDiscovery:
            ContentDiscoveryDetail()
        case .integration:
            IntegrationsDetail()
        case .trakt:
            TraktDetail()
        case .about:
            AboutDetail()
        case .playback:
            PlaybackSettingsDetail()
        }
    }
}

// MARK: - Rail button (Classic — icon + title + chevron, pill highlight)

private struct SettingsRailButton: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let category: SettingsCategory
    let selected: Bool

    private var active: Bool { isFocused || selected }

    var body: some View {
        HStack(spacing: NuvioSpacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? theme.palette.textPrimary : theme.palette.textSecondary)
                .frame(width: 22)
            Text(category.title)
                .font(.system(size: 20, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? theme.palette.textPrimary : theme.palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: NuvioSpacing.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.palette.textTertiary)
        }
        .padding(.horizontal, 18)
        // 56dp capsule pills. Every pill has a dark fill (BackgroundCard);
        // focused/selected read slightly brighter.
        .frame(height: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(active ? theme.palette.backgroundCard : theme.palette.background)
        )
        // Focus/selection outline = the current accent's focusRing (thick on
        // focus, hairline when selected-but-not-focused). NO scale on focus.
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    isFocused ? theme.palette.focusRing : (selected ? theme.palette.focusRing.opacity(0.6) : .clear),
                    lineWidth: isFocused ? 3 : (selected ? 1 : 0)
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

// MARK: - Detail scaffolding

struct SettingsDetailHeader: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(theme.palette.textPrimary)
            Text(subtitle)
                .font(.system(size: 20))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A grouped settings section rendered as a rounded card (title + optional
/// subtitle + rows), matching the APK's `secondaryCardRadius` (18dp) groups.
struct SettingsGroupCard<Content: View>: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            if !title.isEmpty || (subtitle?.isEmpty == false) {
                VStack(alignment: .leading, spacing: 3) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(theme.palette.textPrimary)
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 19))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            }
            content
        }
        .padding(NuvioSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.background.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(NuvioPrimitives.neutral750.opacity(0.6), lineWidth: 1)
        )
    }
}

/// A tappable settings row with strong focus, matching the Android SettingsActionRow.
struct SettingsActionRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    var subtitle: String?
    var value: String?
    var leadingIcon: String?

    var body: some View {
        HStack(spacing: NuvioSpacing.lg) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                    .frame(width: 34)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 19))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.palette.textTertiary)
        }
        .padding(.horizontal, NuvioSpacing.lg)
        .frame(minHeight: 68)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .fill(isFocused ? theme.palette.focusBackground : theme.palette.backgroundCard.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 4)
        )
        .scaleEffect(isFocused ? 1.02 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isFocused)
    }
}

struct DetailScaffold<Content: View>: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: NuvioSpacing.lg) {
                SettingsDetailHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(.horizontal, NuvioSpacing.xl)
            .padding(.top, NuvioSpacing.lg)
            .padding(.bottom, NuvioSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Clips scrolled content to the pane so rows stay inside the workspace card.
    }
}

// MARK: - Appearance detail

private struct AppearanceDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    /// Confirmation before switching INTO Essential (it hides options).
    @State private var pendingEssential = false

    var body: some View {
        DetailScaffold(title: SettingsCategory.appearance.title, subtitle: SettingsCategory.appearance.subtitle) {
            SettingsGroupCard(title: "Color Theme", subtitle: "Pick the accent color used across the app") {
                ScrollView(.horizontal) {
                    HStack(spacing: NuvioSpacing.md) {
                        ForEach(NuvioThemes.all) { palette in
                            Button { theme.setPalette(palette) } label: {
                                ColorSwatchCard(palette: palette, selected: theme.palette.id == palette.id)
                            }
                            .buttonStyle(PlainCardButtonStyle())
                        }
                    }
                    // Breathing room for the focus ring; the scroll stays
                    // CLIPPED so swatches don't ride over the rest of the pane.
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
            }

            SettingsGroupCard(title: "AMOLED Mode") {
                SettingsToggleCard(
                    title: "AMOLED Mode",
                    subtitle: "Use pure black for app backgrounds",
                    isOn: Binding(get: { theme.amoled }, set: { theme.amoled = $0 })
                )
            }

            SettingsGroupCard(title: "Font", subtitle: "Typeface used across the app") {
                HStack(spacing: NuvioSpacing.md) {
                    ForEach(AppFont.allCases) { font in
                        Button { theme.font = font } label: {
                            SelectableChip(title: font.displayName, selected: theme.font == font)
                                .fontDesign(font.design)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                }
            }

            SettingsGroupCard(title: "Experience Mode", subtitle: theme.experienceMode.summary) {
                HStack(spacing: NuvioSpacing.md) {
                    ForEach(ExperienceMode.allCases) { mode in
                        Button {
                            if mode == .essential, theme.experienceMode != .essential {
                                pendingEssential = true   // confirm hiding options
                            } else {
                                theme.experienceMode = mode
                            }
                        } label: {
                            SelectableChip(title: mode.displayName, selected: theme.experienceMode == mode)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                }
            }

            SettingsGroupCard(title: "Settings Style", subtitle: theme.settingsUiStyle.summary) {
                HStack(spacing: NuvioSpacing.md) {
                    ForEach(SettingsUiStyle.allCases) { style in
                        Button { theme.settingsUiStyle = style } label: {
                            SelectableChip(title: style.displayName, selected: theme.settingsUiStyle == style)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                }
            }
        }
        .alert("Switch to Essential?", isPresented: $pendingEssential) {
            Button("Cancel", role: .cancel) {}
            Button("Switch") { theme.experienceMode = .essential }
        } message: {
            Text("Essential mode hides the more advanced Playback options (engine, on-screen display, auto-play source, audio and display tuning). You can switch back to Advanced any time.")
        }
    }
}

/// Reusable focus-aware selection chip (accent fill on focus, readable in
/// every state) — used by the theme font picker and other inline selectors.
struct SelectableChip: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isFocused ? theme.palette.onSecondary : (selected ? .white : theme.palette.textSecondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, NuvioSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                    .fill(isFocused ? theme.palette.secondary
                          : (selected ? theme.palette.secondary.opacity(0.28) : theme.palette.backgroundCard.opacity(0.85)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : (selected ? theme.palette.secondary : .clear),
                                  lineWidth: isFocused ? 4 : 2)
            )
            .scaleEffect(isFocused ? 1.05 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isFocused)
    }
}

/// A colored accent swatch card (circle + name, check when selected) for the
/// horizontal Color Theme row.
private struct ColorSwatchCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let palette: ThemePalette
    let selected: Bool

    var body: some View {
        VStack(spacing: NuvioSpacing.sm) {
            ZStack {
                Circle().fill(palette.secondary).frame(width: 60, height: 60)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(palette.onSecondary)
                }
            }
            Text(palette.displayName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.palette.textPrimary)
        }
        .frame(width: 150, height: 130)
        .background(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .fill(isFocused ? theme.palette.focusBackground : theme.palette.background.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing
                              : (selected ? theme.palette.secondary : .clear), lineWidth: isFocused ? 4 : 2)
        )
    }
}

/// A pill switch matching the APK's toggle (dark when off, accent when on,
/// with a sliding white knob).
struct NuvioSwitch: View {
    @EnvironmentObject private var theme: ThemeManager
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? theme.palette.secondary : Color.white.opacity(0.18))
                .frame(width: 64, height: 36)
            Circle()
                .fill(.white)
                .frame(width: 28, height: 28)
                .padding(4)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isOn)
    }
}

/// A toggle row rendered as a focusable card (title + subtitle + pill switch),
/// matching the APK's toggle rows.
struct SettingsToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ToggleCardLabel(title: title, subtitle: subtitle, isOn: isOn)
        }
        .buttonStyle(PlainCardButtonStyle())
    }
}

private struct ToggleCardLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    let subtitle: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: NuvioSpacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 24, weight: .medium))
                    .foregroundStyle(theme.palette.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 18))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            NuvioSwitch(isOn: isOn)
        }
        .padding(.horizontal, NuvioSpacing.lg)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: theme.settingsRowRadius, style: .continuous)
                .fill(isFocused ? theme.palette.focusBackground : theme.palette.backgroundCard.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.settingsRowRadius, style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 4)
        )
    }
}

/// A navigation-style row with a trailing value + chevron. Focus = brighter
/// fill + thick accent ring so the selected row is always unmistakable.
struct SettingsValueCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 24, weight: .medium))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle).font(.system(size: 18))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            Spacer()
            Text(value).font(.system(size: 22, weight: .medium))
                .foregroundStyle(theme.palette.secondary)
            Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.palette.textTertiary)
        }
        .padding(.horizontal, NuvioSpacing.lg)
        .frame(minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .fill(isFocused ? theme.palette.focusBackground : theme.palette.backgroundCard.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 4)
        )
        .scaleEffect(isFocused ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Add-ons detail

/// Settings → Account: Nuvio account sign-in/status + Manage Profiles. Both
/// were moved here from the "Who's watching" gate so account and profile
/// management live in Settings.
private struct AccountSettingsDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: NuvioAccountManager
    @EnvironmentObject private var profiles: ProfileStore
    @State private var showAccount = false
    @State private var showProfiles = false

    var body: some View {
        DetailScaffold(title: SettingsCategory.account.title, subtitle: SettingsCategory.account.subtitle) {
            SettingsGroupCard(title: "") {
                Button { showAccount = true } label: {
                    SettingsValueCard(
                        title: account.authState.isSignedIn ? "Nuvio Account" : "Sign in to Nuvio",
                        subtitle: account.authState.isSignedIn
                            ? "Sync your addons, library, progress and profiles"
                            : "Sign in to sync your addons, library, progress and profiles",
                        value: accountStatus
                    )
                }
                .buttonStyle(PlainCardButtonStyle())

                Button { showProfiles = true } label: {
                    SettingsActionRow(
                        title: "Manage Profiles",
                        subtitle: "Add, rename, recolor, PIN-lock and remove profiles",
                        value: "\(profiles.profiles.count)",
                        leadingIcon: "person.2.fill"
                    )
                }
                .buttonStyle(PlainCardButtonStyle())
            }
        }
        .fullScreenCover(isPresented: $showAccount) {
            ZStack {
                theme.palette.background.ignoresSafeArea()
                AccountView()
            }
            .environmentObject(theme)
            .environmentObject(account)
            .environmentObject(profiles)
            .onChange(of: account.authState) { _, newState in
                if case .signedIn = newState { showAccount = false }
            }
            .onExitCommand { showAccount = false }
        }
        .fullScreenCover(isPresented: $showProfiles) {
            ProfileManageView { showProfiles = false }
                .environmentObject(theme)
                .environmentObject(profiles)
        }
    }

    private var accountStatus: String {
        switch account.authState {
        case .signedIn(_, let email): return email.isEmpty ? "Signed in" : email
        case .loading: return "…"
        case .signedOut: return ""
        }
    }
}

/// Content & Discovery — the APK folds add-ons, catalogs and collections into
/// one section, so this pane hosts add-on management plus a Collections entry.
/// Content & Discovery pane: a single "Addons" drill-in row (APK behavior).
private struct ContentDiscoveryDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var collections: CollectionsStore
    @EnvironmentObject private var homeCatalogSettings: HomeCatalogSettingsStore
    @State private var showAddons = false

    var body: some View {
        DetailScaffold(title: SettingsCategory.contentDiscovery.title, subtitle: SettingsCategory.contentDiscovery.subtitle) {
            SettingsGroupCard(title: "") {
                Button { showAddons = true } label: {
                    SettingsValueCard(
                        title: "Addons",
                        subtitle: "Manage add-ons, catalog order, and collections",
                        value: "\(addonManager.addons.count)"
                    )
                }
                .buttonStyle(PlainCardButtonStyle())
            }
        }
        .fullScreenCover(isPresented: $showAddons) {
            ZStack {
                theme.palette.background.ignoresSafeArea()
                AddonsManagementView()
            }
            .environmentObject(theme)
            .environmentObject(addonManager)
            .environmentObject(collections)
            .environmentObject(homeCatalogSettings)
            .onExitCommand { showAddons = false }
        }
    }
}

/// Full add-ons management screen, opened from Content & Discovery. Structured
/// to mirror the APK's Add-ons screen: Install card → Catalog Order → Collections
/// → Refresh → Installed Add-ons list (with per-addon on/off, reorder, remove).
private struct AddonsManagementView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var collections: CollectionsStore
    @EnvironmentObject private var homeCatalogSettings: HomeCatalogSettingsStore

    @State private var newAddonURL = ""
    @State private var installing = false
    @State private var installMessage: String?
    @State private var showCollections = false
    @State private var showCatalogOrder = false
    @State private var refreshing = false
    @State private var showExport = false

    private static let refreshIdle = "Re-fetch installed add-on manifests"
    @State private var refreshSubtitle = AddonsManagementView.refreshIdle

    var body: some View {
        DetailScaffold(title: "Add-ons", subtitle: "Manage add-ons, catalog order, and collections") {
            // Install Add-on
            SettingsGroupCard(title: "Install Add-on", subtitle: "Install Stremio add-ons by manifest URL") {
                HStack(spacing: NuvioSpacing.md) {
                    TextField("https://.../manifest.json", text: $newAddonURL)
                        .font(.system(size: 23))
                        .padding(.horizontal, NuvioSpacing.lg)
                        .padding(.vertical, NuvioSpacing.md)
                        .background(theme.palette.field, in: RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous))
                        .frame(maxWidth: 640)
                    Button { install() } label: {
                        if installing {
                            ProgressView().tint(theme.palette.onSecondary)
                        } else {
                            Text("Install").font(.system(size: 23, weight: .semibold))
                        }
                    }
                    .disabled(installing || newAddonURL.isEmpty)
                }

                if let installMessage {
                    Text(installMessage)
                        .font(.system(size: 20))
                        .foregroundStyle(installMessage.hasPrefix("Installed") ? NuvioPrimitives.success : NuvioPrimitives.error)
                }
            }

            // Catalog Order (APK files this under Add-ons)
            Button { showCatalogOrder = true } label: {
                SettingsActionRow(
                    title: "Catalog Order",
                    subtitle: "Reorder, rename and hide your home catalog rows",
                    leadingIcon: "arrow.up.arrow.down"
                )
            }
            .buttonStyle(PlainCardButtonStyle())

            // Collections
            Button { showCollections = true } label: {
                SettingsActionRow(
                    title: "Collections",
                    subtitle: "Group catalogs into custom home rows",
                    value: collections.collections.isEmpty ? nil : "\(collections.collections.count)",
                    leadingIcon: "rectangle.stack.fill"
                )
            }
            .buttonStyle(PlainCardButtonStyle())

            // Refresh Add-ons
            Button { refresh() } label: {
                SettingsActionRow(
                    title: "Refresh Add-ons",
                    subtitle: refreshSubtitle,
                    value: refreshing ? "…" : nil,
                    leadingIcon: "arrow.clockwise"
                )
            }
            .buttonStyle(PlainCardButtonStyle())
            .disabled(refreshing)

            // Export Setup: QR with every installed manifest URL — scan with a
            // phone to keep your addon list for a fresh install.
            Button { showExport = true } label: {
                SettingsActionRow(
                    title: "Export Add-on Setup",
                    subtitle: "Show a QR code containing every installed manifest URL",
                    leadingIcon: "qrcode"
                )
            }
            .buttonStyle(PlainCardButtonStyle())

            // Installed Add-ons
            SettingsGroupCard(title: "Installed Add-ons") {
                if addonManager.addons.isEmpty {
                    Text("No add-ons installed yet.")
                        .font(.system(size: 21))
                        .foregroundStyle(theme.palette.textSecondary)
                } else {
                    ForEach(Array(addonManager.addons.enumerated()), id: \.element.id) { index, addon in
                        AddonRowView(
                            addon: addon,
                            canMoveUp: index > 0,
                            canMoveDown: index < addonManager.addons.count - 1,
                            onMoveUp: { addonManager.moveUp(addon) },
                            onMoveDown: { addonManager.moveDown(addon) },
                            onToggle: { addonManager.setEnabled(addon, !addon.enabled) },
                            onRemove: { addonManager.remove(addon) }
                        )
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCollections) {
            CollectionsCoverView { showCollections = false }
                .environmentObject(theme)
                .environmentObject(collections)
                .environmentObject(addonManager)
        }
        .fullScreenCover(isPresented: $showCatalogOrder) {
            CatalogOrderCoverView { showCatalogOrder = false }
                .environmentObject(theme)
                .environmentObject(addonManager)
                .environmentObject(collections)
                .environmentObject(homeCatalogSettings)
        }
        .fullScreenCover(isPresented: $showExport) {
            AddonExportView(
                urls: addonManager.addons.map(\.manifestURL),
                onDone: { showExport = false }
            )
            .environmentObject(theme)
        }
    }

    private func install() {
        installing = true
        installMessage = nil
        let url = newAddonURL
        Task {
            do {
                try await addonManager.install(manifestURL: url)
                installMessage = "Installed successfully"
                newAddonURL = ""
            } catch {
                installMessage = "Install failed: \(error.localizedDescription)"
            }
            installing = false
        }
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            await addonManager.refresh()
            refreshing = false
            refreshSubtitle = "Add-ons refreshed just now"
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            refreshSubtitle = Self.refreshIdle
        }
    }
}

/// Full-screen Collections manager, opened from Content & Discovery. Menu/Back
/// closes it back to the settings pane.
private struct CollectionsCoverView: View {
    @EnvironmentObject private var theme: ThemeManager
    let onDone: () -> Void

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            CollectionsSettingsDetail()
                .padding(.horizontal, NuvioSpacing.xxl)
                .padding(.vertical, NuvioSpacing.xl)
        }
        .onExitCommand { onDone() }
    }
}

private struct AddonRowView: View {
    @EnvironmentObject private var theme: ThemeManager
    let addon: InstalledAddon
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onToggle: () -> Void = {}
    let onRemove: () -> Void

    private var isCinemeta: Bool { addon.manifestURL == AddonManager.cinemetaURL }

    var body: some View {
        HStack(spacing: NuvioSpacing.md) {
            // On/off toggle (APK's per-addon switch).
            Button(action: onToggle) { AddonToggle(isOn: addon.enabled) }
                .buttonStyle(PlainCardButtonStyle())

            VStack(alignment: .leading, spacing: 3) {
                Text(addon.manifest.name)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                HStack(spacing: NuvioSpacing.sm) {
                    if let version = addon.manifest.version {
                        Text("v\(version)").font(.system(size: 18)).foregroundStyle(theme.palette.textTertiary)
                    }
                    if addon.manifest.providesCatalogs { capability("Catalogs") }
                    if addon.manifest.providesStreams { capability("Streams") }
                    if addon.manifest.providesMeta { capability("Meta") }
                }
            }
            // Dim the info when the addon is off.
            .opacity(addon.enabled ? 1 : 0.45)

            Spacer()

            // Reorder controls (dimmed + non-focusable at the ends).
            RowActionCircle(icon: "chevron.up", action: onMoveUp)
                .disabled(!canMoveUp)
                .opacity(canMoveUp ? 1 : 0.3)
            RowActionCircle(icon: "chevron.down", action: onMoveDown)
                .disabled(!canMoveDown)
                .opacity(canMoveDown ? 1 : 0.3)

            // Cinemeta is the bundled meta provider and can't be removed.
            if !isCinemeta {
                Button(action: onRemove) { TrashCircle() }
                    .buttonStyle(PlainCardButtonStyle())
            }
        }
        .padding(.horizontal, NuvioSpacing.lg)
        .padding(.vertical, NuvioSpacing.sm)
        .frame(minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .fill(theme.palette.backgroundCard.opacity(0.5))
        )
    }

    private func capability(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(theme.palette.secondary)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(theme.palette.secondary.opacity(0.15), in: Capsule())
    }
}

/// The addon on/off switch, with a focus ring so it reads as selectable.
private struct AddonToggle: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let isOn: Bool

    var body: some View {
        NuvioSwitch(isOn: isOn)
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }
}

/// A round reorder button (up/down chevron) for addon rows.
private struct RowActionCircle: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { RowActionCircleLabel(icon: icon) }
            .buttonStyle(PlainCardButtonStyle())
    }
}

private struct RowActionCircleLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(isFocused ? theme.palette.onSecondary : theme.palette.textPrimary)
            .frame(width: 60, height: 60)
            .background(Circle().fill(isFocused ? theme.palette.secondary : Color.white.opacity(0.12)))
            .overlay(Circle().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3))
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }
}

/// Readable, clearly-focusable delete control for addon rows: a red trash
/// circle that fills solid red with a ring on focus.
private struct TrashCircle: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: "trash.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(isFocused ? .white : NuvioPrimitives.red300)
            .frame(width: 64, height: 64)
            .background(Circle().fill(isFocused ? NuvioPrimitives.red500 : NuvioPrimitives.red500.opacity(0.18)))
            .overlay(Circle().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3))
            .scaleEffect(isFocused ? 1.08 : 1)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - About detail

private struct AboutDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @State private var info: AboutInfo?
    @State private var cacheLabel = DiagnosticsService.cacheSizeLabel()
    @State private var clearing = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        DetailScaffold(title: SettingsCategory.about.title, subtitle: SettingsCategory.about.subtitle) {
            SettingsGroupCard(title: "") {
                VStack(spacing: NuvioSpacing.sm) {
                    HStack(spacing: NuvioSpacing.sm) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(theme.palette.secondary)
                        Text("NUVIO")
                            .font(.system(size: 40, weight: .heavy))
                            .foregroundStyle(theme.palette.textPrimary)
                    }
                    Text("Made with ❤️ by Tapframe and friends — Apple TV port")
                        .font(.system(size: 19))
                        .foregroundStyle(theme.palette.textSecondary)
                    Text("Version \(version)")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, NuvioSpacing.md)

                Button { info = .privacy } label: {
                    SettingsValueCard(title: "Privacy Policy", subtitle: "View our privacy policy", value: "")
                }.buttonStyle(PlainCardButtonStyle())
                Button { info = .supporters } label: {
                    SettingsValueCard(title: "Supporters & Contributors", subtitle: "Open recognition and project credits", value: "")
                }.buttonStyle(PlainCardButtonStyle())
                Button { info = .licenses } label: {
                    SettingsValueCard(title: "Licenses & Attributions", subtitle: "Open-source components used in this app", value: "")
                }.buttonStyle(PlainCardButtonStyle())
            }

            SettingsGroupCard(title: "Diagnostics", subtitle: "Build information and storage") {
                SettingsValueCard(title: "Version", subtitle: "App build", value: DiagnosticsService.appVersion)
                SettingsValueCard(title: "System", subtitle: DiagnosticsService.deviceModel, value: DiagnosticsService.systemVersion)
                Button {
                    guard !clearing else { return }
                    clearing = true
                    DiagnosticsService.clearCaches()
                    cacheLabel = DiagnosticsService.cacheSizeLabel()
                    clearing = false
                } label: {
                    SettingsValueCard(
                        title: "Clear cache",
                        subtitle: "Remove cached source lists, metadata and images",
                        value: clearing ? "…" : cacheLabel
                    )
                }.buttonStyle(PlainCardButtonStyle())
            }
        }
        .fullScreenCover(item: $info) { item in
            AboutInfoView(info: item)
                .environmentObject(theme)
        }
    }
}

/// The three static info pages reachable from About.
private enum AboutInfo: String, Identifiable {
    case privacy, supporters, licenses
    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .supporters: return "Supporters & Contributors"
        case .licenses: return "Licenses & Attributions"
        }
    }

    var body: String {
        switch self {
        case .privacy:
            return "Nuvio does not collect, store, or share any personal data. All playback, library, and account information stays on your device or with the third-party services you explicitly connect (such as TMDB, Trakt, or your debrid provider). No analytics or tracking is performed by this app."
        case .supporters:
            return "Nuvio is made with ❤️ by Tapframe and a community of contributors. Special thanks to everyone who has reported issues, submitted translations, and supported the project. The Apple TV port builds on their work."
        case .licenses:
            return "This app uses open-source components including SwiftUI, KSPlayer, and metadata provided by TMDB. TMDB is used under their API terms; this product uses the TMDB API but is not endorsed or certified by TMDB. Full license texts for bundled components are available in the source repository."
        }
    }
}

private struct AboutInfoView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    let info: AboutInfo

    var body: some View {
        DetailScaffold(title: info.title, subtitle: "") {
            SettingsGroupCard(title: "") {
                Text(info.body)
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NuvioSpacing.md)
            }
        }
        .onExitCommand { dismiss() }
    }
}


/// Full-screen QR export of the installed addon manifest URLs — scan with a
/// phone to carry the setup to a fresh install (one URL per line).
private struct AddonExportView: View {
    @EnvironmentObject private var theme: ThemeManager
    let urls: [String]
    let onDone: () -> Void

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            VStack(spacing: NuvioSpacing.xl) {
                Text("Add-on Setup")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text("Scan with your phone — one manifest URL per line. Paste them into any Nuvio install to restore your add-ons.")
                    .font(.system(size: 23))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                QRCodeView(string: urls.joined(separator: "\n"))
                    .frame(width: 460, height: 460)
                Text("\(urls.count) add-on\(urls.count == 1 ? "" : "s")")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(theme.palette.textTertiary)
                Button("Done", action: onDone)
            }
            .padding(NuvioSpacing.huge)
        }
        .onExitCommand(perform: onDone)
    }
}
