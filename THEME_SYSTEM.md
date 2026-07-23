# Orivio (NuvioTV-AppleTV) — Theme System Reference

Everything an AI (or a person) needs to design a new theme for the tvOS app.
This is a code-accurate inventory of the theming primitives, the components that
respond to them, and the extension points for adding a whole new look.

The design lives in three independent layers — a theme can touch any of them:

1. **App theme** (`AppTheme`) — the overall look/feel *preset* and chrome
   (sidebar vs top bar, native settings vs two-pane, card platter vs ring, hero
   style). Currently `classic` and `appletv`.
2. **Accent palette** (`ThemePalette`) — the color scheme layered on top of any
   app theme (White, Crimson, Ocean, Violet, Emerald, Amber, Rose).
3. **Appearance + modifiers** — light/dark (ATV only), AMOLED, font family,
   settings-surface style, home layout, poster sizing, and the performance
   effect toggles.

The selected app theme is `ThemeManager.appThemeID`; rendering code that a theme
restyles branches on it (today via the `theme.isAppleTVTheme` convenience).

---

## 1. Theme axes (every user-selectable knob)

| Axis | Type | Values | Where | Synced |
|---|---|---|---|---|
| App theme | `AppTheme` (`AppThemes.all`) | `classic`, `appletv` | Settings → Themes | `ThemeSnapshot.appThemeID` |
| Accent palette | `ThemePalette` (`NuvioThemes.all`) | `white, crimson, ocean, violet, emerald, amber, rose` (default **violet**) | Settings → Appearance → Color Theme | `ThemeSnapshot.paletteID` |
| Appearance (ATV only) | `ATVAppearance` | `system`, `light`, `dark` | Settings → Themes (and ATV Settings top row) | `ThemeSnapshot.atvAppearance` |
| AMOLED | `Bool` | pure-black surfaces | Settings → Appearance | `ThemeSnapshot.amoled` |
| Font family | `AppFont` | `system, rounded, serif, monospaced` | Settings → Appearance → Font | `ThemeSnapshot.font` |
| Experience mode | `ExperienceMode` | `essential`, `advanced` (hides advanced panes) | Settings → Appearance | `ThemeSnapshot.experienceMode` |
| Settings UI style | `SettingsUiStyle` | `classic` (r12/18), `zen` (r28/34), `horizon` (r2/2) | Settings → Appearance | `ThemeSnapshot.settingsUiStyle` |
| Home layout | `HomeLayout` | `modern`, `grid`, `classic` | Settings → Layout | home sync blob |
| Poster size | `PosterSize` | `small` 180, `medium` 220, `large` 264 pt wide (×3/2 tall) | Settings → Layout | home sync blob |
| Poster corner radius | `Int` | one of `0, 6, 12, 16, 22` | Settings → Layout | home sync blob |
| Poster labels | `Bool` | show title under posters | Settings → Layout | home sync blob |
| Landscape posters | `Bool` | 16:9 cards instead of portrait (Modern only) | Settings → Layout | home sync blob |
| Continue-Watching sort | `ContinueWatchingSortMode` | `recentlyWatched`, `streamingStyle` | Settings → Layout | home sync blob |
| CW "next up" blur | `Bool` | spoiler-blur unstarted stills | Settings → Layout | home sync blob |
| Performance effects | 7 `Bool`s | see §7 | Settings → Performance | perf blob |

`AppThemes.defaultID = classic`. Accent default is **violet** (matches the brand
mark); AMOLED off; font system; experience advanced; settings style classic.

---

## 2. App themes — the two look presets

`AppTheme { id, displayName, summary, icon }` in `Theme/NuvioTheme.swift`.

| Theme | Chrome | Settings surface | Cards | Hero | Appearance |
|---|---|---|---|---|---|
| **Classic** | Left `SidebarNav` rail (collapsible, dims content) | Two-pane "workspace" card (`SettingsView`) | Custom focus ring + scale + shadow (`PlainCardButtonStyle`) | Focus-following billboard (`HeroInfoView`) | Hard-dark always |
| **Apple TV** | Native top `TabView` (Liquid Glass on tvOS 26) | tvOS-Settings list (`ATVSettingsView`) | Native `CardButtonStyle` platter + trackpad wiggle, caption *below* | Prominent auto-rotating spotlight + Play button (`ATVHeroInfoView`) | Light / Dark / Automatic; warm ambient background |

The single source of truth for "which chrome" is `ThemeManager.isAppleTVTheme`
(`appThemeID == "appletv"`). Adding a third theme means either reusing that flag
or introducing a new branch (see §9).

---

## 3. Color tokens

### 3a. Primitives — `NuvioPrimitives` (raw hex, never themed directly)

`black, white, neutral950…neutral100` (a 16-step warm-neutral ramp),
`red/blue/violet/green/amber/rose {300,500,600/700}`, plus semantic constants:
`rating` (#FFD700), `torrent` (#7E57C2), `imdb` (#F5C518), `success` (#4CAF50),
`warning` (#FFB74D), `error` (#CF6679).

### 3b. Palette fields — `ThemePalette` (what a color theme sets)

| Field | Role | Classic default |
|---|---|---|
| `secondary` | accent (buttons, focus fill, selected) | palette accent |
| `secondaryVariant` | darker accent | palette accent 700 |
| `onSecondary` | text/icon on accent fill | white (dark text for the White palette) |
| `focusRing` | focus border stroke | accent 300 |
| `focusBackground` | focus fill wash | dark accent-tint |
| `background` | screen base | `neutral950` |
| `backgroundElevated` | raised surface / panels | `neutral900` |
| `backgroundCard` | card fill behind artwork | `neutral825` |
| `surface` / `surfaceVariant` | secondary fills | `neutral875` / `neutral800` |
| `panel` | side/overlay panels | `neutral900` |
| `overlay` | modal scrim | black 0.85 |
| `field` | inputs / chips | `neutral850` |
| `playerOverlay` | player OSD scrim | black 0.8 |
| `textPrimary/Secondary/Tertiary` | text ramp (now **stored**, so light mode can flip them dark) | white / neutral400 / neutral500 |

Register a new accent by adding a `ThemePalette` to `NuvioThemes.all`. Only
`secondary/secondaryVariant/focusRing/focusBackground` (+ optional `background`
tints) usually need setting; the rest inherit sensible neutral defaults.

### 3c. How the live palette is resolved — `ThemeManager.palette`

1. Start from the selected accent (`basePalette`).
2. **Apple TV theme** → run `ATVPalettes.adapt(base, light:, amoled:)`: keeps the
   accent, swaps neutral surfaces for tvOS-style greys — a **warm light** set
   (`#E7E2DA` stage, near-white cards, dark warm text) or a **dark** set, honoring
   AMOLED for pure black.
3. **Classic + AMOLED** → forces `background`/`backgroundElevated` to black.

`theme.atvIsLight` resolves `ATVAppearance` against the live system scheme
(`systemIsDark`, fed in from the root view). Root applies
`.preferredColorScheme(theme.preferredColorScheme)` — Classic is always `.dark`,
Apple TV returns light/dark/`nil` (follow the TV).

---

## 4. Scale tokens

- **Spacing** — `NuvioSpacing`: `xs 6, sm 10, md 14, lg 20, xl 28, xxl 44, huge 64`.
- **Radius** — `NuvioRadius`: `sm 8, md 12, lg 16, xl 22`.
- **Settings radii** — from `SettingsUiStyle`: `rowRadius` / `cardRadius`
  (classic 12/18, zen 28/34, horizon 2/2), read via
  `theme.settingsRowRadius` / `theme.settingsCardRadius`.

---

## 5. Material & background helpers

- **`View.atvGlass(in: Shape)`** — Liquid Glass (`glassEffect(.regular,…)`) on
  tvOS 26+, `.regularMaterial` fallback below. Used by ATV settings section
  cards; the top TabView bar is native glass automatically.
- **`ATVBackground`** — full-screen warm/dark ambient wash for the Apple TV
  theme (gradient + accent radial bloom + warm top-right bloom in light).
- **`HeroGradient`** — reusable left/bottom scrim behind Detail/Sources heroes;
  has separate light-mode ramps (lighter, so the art stays vivid).

---

## 6. Themed components (the building blocks a theme restyles)

**Navigation chrome**
- `SidebarNav` — Classic collapsible left rail (dims content when expanded).
- Top `TabView` in `NuvioTVApp.atvLayout` — ATV native tab bar over `ATVBackground`.

**Cards** (`Components/Components.swift`)
- `PosterCard` — portrait tile; in ATV mode drops its ring/scale/shadow/caption
  (the platter carries focus, caption goes below).
- `LandscapeCard` — 16:9 tile (CW + episodes); `showsCaption` gates the in-card
  label.
- `ATVCardCaption` — title (+ subtitle) rendered **below** the button so the
  native platter never bridges art→label.
- `View.mediaCardButtonStyle()` — the adaptive style switch: native
  `CardButtonStyle` (wiggle) in ATV, `PlainCardButtonStyle` (ring) in Classic.

**Hero** (`Screens/HomeView.swift`)
- `HeroBackdropView` — full-bleed backdrop + Netflix scrim; ATV adds a
  progressive-blur frosted dissolve (with light-mode ramps).
- `HeroInfoView` — Classic focus-following billboard (logo, meta, synopsis).
- `ATVHeroInfoView` + `ATVHeroPlayButton` — tall bottom-anchored spotlight with
  logo, green rating line, synopsis, white Play pill; auto-rotates the top 10
  (`HeroFocus.spotlight` / `setSpotlight` / `rotateIfIdle`, 2 s tick, idle > 6 s).

**Settings surfaces** (`Screens/SettingsView.swift`, `Screens/ATVSettingsView.swift`)
- `SettingsView` — Classic two-pane workspace card + tall pill rail.
- `ATVSettingsView` — tvOS-Settings list of glass section cards; rows push the
  **same** detail panes (`AppearanceDetail`, `ThemesDetail`, `LayoutSettingsDetail`,
  etc. — now internal so both surfaces reuse them).
- Shared: `SettingsGroupCard`, `SettingsRowBackground`, `SettingsActionRow`,
  `SettingsIconTile`, `SettingsDetailHeader`, `NuvioSwitch`, `SelectableChip`,
  `ColorSwatchCard`, `ThemeChoiceCard`.

**Badges / meta** — `MetaBadge`, `ImdbBadge`, `RatingBadge`, `WatchedBadge`,
`MetaLine`/`MetaDot`/`MetaDotText`, `MDBListRatingsRow`. (Use `.primary` for
white-in-dark / dark-in-light chips.)

**States** — `NuvioLoadingView`, `NuvioEmptyState`, `HomeLoadingBackdrop`,
`PlaceholderShimmer`, `MarqueeText` (focus title scroll).

---

## 7. Focus & motion conventions

- **Focus indication**: Classic draws its own `focusRing` stroke + `focusZoom`
  scale + shadow; ATV uses the native platter (branch on `theme.isAppleTVTheme`
  to suppress the custom visuals so they don't double up).
- **Vertical navigation**: home rows are **not** wrapped in `.focusSection()` —
  that made vertical moves re-home to a center card; without it tvOS preserves
  the column (Netflix/TV-app behavior).
- **Springs**: card focus `.spring(response: 0.32, dampingFraction: 0.82)`;
  buttons `.easeOut(0.12)`.
- **Performance effect toggles** (`PerformanceSettingsStore`, each `*Effective`
  gated by Reduce Motion): `heroBackdrop`, `heroCrossfade`, `cardShadows`,
  `focusZoom`, `artworkFadeIn`, `sidebarAnimation`, `buttonAnimations`
  (+ `showFPSOverlay` diagnostic). A theme should degrade gracefully when these
  are off (older Apple TVs).

---

## 8. Persistence, sync & dev flags

- **UserDefaults keys**: `nuvio.theme` (accent), `.amoled`, `.font`,
  `.experience`, `.settingsstyle`, `.appTheme`, `.atvAppearance`.
- **Sync**: `ThemeSnapshot` (accent + amoled + font + experience + settingsStyle
  + `appThemeID?` + `atvAppearance?`) round-trips through the account; new fields
  stay optional so old blobs decode. Home/poster prefs ride a separate blob.
- **Dev launch args** (beat the synced snapshot for the session):
  `-atvTheme` / `-classicTheme`, `-atvLight` / `-atvDark`, `-settingsTabDemo`,
  plus the demo entry points `-homeDemo`, `-settingsDemo`, `-detailDemo`, etc.

---

## 9. Recipe — adding a brand-new app theme

1. **Register** an `AppTheme` in `AppThemes.all` (id, displayName, summary,
   icon). It shows up in Settings → Themes automatically.
2. **Chrome**: decide the nav. Reuse `isAppleTVTheme` if it should look like the
   ATV top bar, or add a new computed flag on `ThemeManager` and branch
   `NuvioTVApp.mainContent` (add a new `*Layout`).
3. **Palette**: add an `ATVPalettes`-style adapter (or reuse) so the accent
   survives but your surfaces/appearance apply; wire it into
   `ThemeManager.palette` and `preferredColorScheme`.
4. **Background**: an `ATVBackground`-style full-screen view (or a flat color).
5. **Cards**: pick a `mediaCardButtonStyle` branch (platter vs ring vs your own
   `ButtonStyle`) and whether captions sit inside or below.
6. **Hero**: reuse `HeroInfoView`, `ATVHeroInfoView`, or add a new hero view;
   `HeroFocus` already supports focus-follow **and** spotlight rotation.
7. **Settings surface**: reuse `SettingsView`, `ATVSettingsView`, or add one that
   pushes the shared detail panes.
8. **Sync**: if the theme adds a persisted knob, add an **optional** field to
   `ThemeSnapshot` (+ a UserDefaults key + `applyRemote`).
9. **Dev flag**: add a `-yourTheme` launch override in
   `ThemeManager.launchThemeOverride` for sim testing.
10. **Verify** in the sim on the booted "apple tv 4k " device, both appearances,
    and confirm Classic is untouched (gate every change on your theme flag).
