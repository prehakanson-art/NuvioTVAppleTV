# Fusion Netflix-Inspired Apple TV Theme — Blueprint

Complete visual, behavioral, motion, focus, background, navigation, playback,
and settings blueprint. Delivered 2026-07-19; source of truth for the theme's
multi-session build. Implementation status lives at the bottom.

---

## 1. Overall Purpose

Make Fusion feel like a premium subscription streaming service while preserving
the flexibility of a personal media center. Simple during ordinary viewing
(large cinematic feature, familiar rows, Play + More Info, a personal "My
Fusion" destination); Fusion keeps managing add-ons, debrid, source quality,
cached streams, player engines, Trakt, cloud content, collections, metadata,
playback preferences underneath.

Dark theater: black, near-black, charcoal, white, gray. Red reserved for active
states, progress, important indicators, select brand moments. Artwork provides
most of the changing color.

NOT just red paint on Fusion — change page hierarchy, navigation behavior,
focus treatment, timing, hero behavior, density so the whole experience feels
designed around a Netflix-style TV interaction model.

Two rhythms:
- **Moving**: fast, stable, responsive. Background changes, previews, extended
  metadata, expensive effects pause.
- **Resting**: cinematic. Artwork sharpens, information appears, a preview may
  begin, extra actions appear.

## 2. Relationship to Existing Features

- Keep all three Home layouts: **Modern** = full Netflix billboard experience;
  **Classic** = focus-following artwork w/ smaller feature area; **Grid** = no
  billboard, no focus-generated backdrop calls (perf on old boxes).
- Keep Continue Watching logic, catalog rows, collections, landscape poster
  option, poster sizes, labels, corner radius, spoiler blur, catalog ordering —
  reinterpret presentation only.
- Detail keeps trailers, auto source selection, held-Play manual sources, Play
  From Beginning, Library/Watched, ratings, extended synopsis, seasons,
  episodes, cast, collections, recommendations, companies, comments, parental
  guidance.
- Search, Discover, Saved Library, Cloud Library, Live TV, Collections,
  Community Collections, profiles, integrations, playback settings,
  performance, Trakt, diagnostics all remain accessible.

## 3. Fundamental Visual Character

Dark, direct, cinematic, slightly dramatic. Fewer visible materials than the
glass Fusion theme; more open artwork. Dominant screen usually black; selected
artwork emerges from black, clearest around the subject, dissolving into
darkness behind text/controls. Large empty black areas are desirable. Red
visible enough to establish the theme, limited enough never to exhaust: mostly
progress bars, selected nav indicators, active tabs, watched/saved controls,
loading indicators, occasional focus accents. Foreground = white text, artwork
cards, buttons, nav. Focused item is the only object that appears close.

## 4. Reference Resolution and Safe Area

- Reference canvas 1920×1080; scale proportionally on 4K.
- Safe area: 76 px left/right, 52 px top, 58 px bottom. Background art, preview
  video, gradients, shadows, vignettes may bleed to the edge.
- 8-px spacing system (occasional 4-px optical corrections). Related controls
  12–20 px apart; cards in a row 18–26 px; major modules 48–72 px.

## 5. Color System

### 5.1 Backgrounds
- Pure black `#000000`: player canvas, AMOLED, behind unloaded art, black page
  transitions, deep modals, letterbox, art-from-darkness screens.
- Standard app background `#070707`: Home, Movies, TV Shows, My Fusion,
  Discover, Collections, Live TV.
- Raised 1 `#111111`: settings panels, search keyboard bg, empty-state cards,
  source-selection containers, secondary surfaces.
- Raised 2 `#181818`: focused list rows, quick-action menus, inactive buttons,
  dialogs, non-artwork cards.
- Raised 3 `#272727`: focused settings rows, selected filters, pressed
  non-artwork controls, active player option rows.

### 5.2 Primary red
- Default Fusion red `#E51C23`; bright focus `#FF343C`; dark `#8E1115`;
  glow `rgba(229,28,35,0.28)`.
- Red affects: nav indicator, progress bars, hero position indicator, selected
  tabs, toggle tracks, slider fills, saved/watched confirmation, loading
  indicator, selected filter, active season chip, collection focus glow,
  source recommendation marker.
- Red must NOT recolor: artwork, studio/channel logos, Dolby/HDR badges,
  warning/error states, body text, whole page backgrounds.

### 5.3 Text
Primary `#FFFFFF`; secondary `#D2D2D2`; tertiary `#9A9A9A`; disabled
`#616161`; black-on-white-button `#080808`. Descriptions = secondary;
technical metadata/dates = tertiary.

### 5.4 Semantic
Live `#E50914`; success `#42CB7F`; warning `#E5A63A`; error `#FF4E59`; info
`#5B9FFF`; cached/instant `#48CA80`; unreleased `#A1A1A1`. Never color-only —
always a label/icon/accessible description.

## 6. Configurable Accent Palettes

Keep White, Crimson, Ocean, Violet, Emerald, Amber, Rose. Default Crimson (or a
dedicated Fusion Red). Changing accent alters only active states; black
foundation constant.

| Accent | Primary | Bright | Dark | Glow |
|---|---|---|---|---|
| White | `#F1F1F1` | `#FFFFFF` | `#777777` | `rgba(255,255,255,0.22)` |
| Crimson | `#E51C23` | `#FF343C` | `#8E1115` | `rgba(229,28,35,0.28)` |
| Ocean | `#368BFF` | `#65A8FF` | `#20569E` | `rgba(54,139,255,0.28)` |
| Violet | `#9466FF` | `#B08BFF` | `#5B3C9E` | `rgba(148,102,255,0.28)` |
| Emerald | `#34CF88` | `#5CE5A6` | `#1D7A52` | `rgba(52,207,136,0.28)` |
| Amber | `#F0AA3C` | `#FFC666` | `#8D6326` | `rgba(240,170,60,0.27)` |
| Rose | `#EF679F` | `#FF8CBB` | `#943E65` | `rgba(239,103,159,0.28)` |

Palette change animation: swatch compresses 85 ms; accents fade toward neutral
gray ~100 ms; new accent fades in 220 ms; glows bloom ~280 ms. No page reload;
focus, row position, hero title, scroll, playback unchanged.

## 7. Typography

Apple system font. Bold tight headings; calm legible body; structured (not
console-like) technical info.

| Role | Size (px) | Weight | Notes |
|---|---|---|---|
| Billboard title | 60–76 | 750–800 | max 2 lines, LH ~1.05× |
| Page title | 42–50 | 700 | one line if possible |
| Row heading | 27–31 | 650–700 | |
| Card title | 21–24 | 600 | |
| Hero description | 22–25 | 400 | LH 30–34 px |
| Metadata | 18–21 | 500–600 | |
| Button label | 21–24 | 700 | |
| Navigation label | 20–23 | 600 | |
| Source technical | 16–19 | 500 | |

Text over artwork: deep black shadow, never an outline/glow look.

## 8. Motion Language

Controlled, fast, confident. Not bouncy/playful/soft.
Main easing `cubic-bezier(0.22, 1, 0.36, 1)`; exit `cubic-bezier(0.4, 0, 0.6, 1)`.

| Event | Duration (ms) |
|---|---|
| Focus enter card | 220 |
| Focus leave card | 165 |
| Focus between neighbors | 180–220 |
| Rapid row navigation | 135–165 |
| Press down / release | 85 / 125 |
| Long-press recognition | 520 (cue ~420) |
| Top-nav focus move | 175 |
| Page transition | 300–340 |
| Card→Detail | 340–390 |
| Hero bg crossfade | 420–520 |
| Hero manual change | 380–430 |
| Hero rapid browsing | 220–260 |
| Dialog in / out | 230 / 175 |
| Toast in / visible / out | 210 / 2600 / 190 |
| Player controls in / out | 180 / 250 |
| Artwork fade-in | 250–280 |

Reduce durations during rapid repeated remote input.

## 9. Focus Model

Exactly one control focused. Focus = scale + brightness + shadow + edge +
metadata visibility + limited parallax.

- **Portrait card**: scale 1.075; y −7; brightness 1.05; saturation 1.025;
  shadow `0 22px 52px rgba(0,0,0,0.72)`; white edge 2 px @ 0.90.
- **Landscape card**: scale 1.09; y −8; brightness 1.055; saturation 1.03;
  shadow `0 24px 58px rgba(0,0,0,0.74)`.
- **Unfocused**: brightness 0.84–0.89; saturation 0.92–0.96; minimal shadow;
  title hidden/gray/visible per layout. Must not look disabled.

## 10. Parallax / Reflection

Restrained tilt: ±2.4° horizontal, ±1.8° vertical. Layer motion: bg ≤2 px,
subject ≤4 px, logo ≤6 px. Reflection broad/soft/low-opacity (studio light, not
a white dot). Return to center ~240 ms, ≤0.2° single overshoot. Reduce Motion:
no tilt/reflection/layers — strong white edge + brightness + small scale.

## 11. Press & Selection

Select compresses before activating: card 1.09→~1.035; button 1.05→~0.99.
Down 85 ms, release 125 ms; shadow tightens. Destination transition begins
before the object fully returns to focused scale. Long press ~520 ms, subtle
cue from ~420 ms.

## 12. Rapid Navigation Mode

Repeat starts ~360 ms; interval 130 ms accelerating to ~85 ms. During rapid
movement: card scale 1.025; parallax/reflections stop; background updates
pause; preview autoplay stops; expanded metadata stays closed; row animation
shortens. Full effects return ~140 ms after movement stops.

## 13. Launch

Cold launch on pure black; no spinner for first 250–400 ms. Fusion logo fades
in center (Fusion's own mark, never the Netflix wordmark/animation). Narrow
red/accent light may spread behind logo, subtle. Spinner below logo only after
~1 s. Destination: signed out → QR sign-in; one unlocked profile → Home; 2+ →
Who's Watching; locked last profile → PIN; recent suspension → restore. No
replay after brief suspension.

## 14. QR Sign-In

Pure black + subtle red radial glow behind central panel. Left: logo, short
explanation, device code. Right: large QR in a white square (high contrast, not
on translucency). Panel `#111111`, simple. Status line (Waiting for sign-in /
Connecting / Account found / Syncing preferences / Ready) crossfades 160 ms.
Complete → QR shrinks/fades, check mark, on to profiles or Home.

## 15. Who's Watching

Near-black background, no movie backdrop; subtle red/profile-color glow behind
the row. Heading "Who's watching?" centered upper third, 50–58 px white.
Avatars centered row, 175–190 px square; name below; lock icon on PIN
profiles; Add tile = plus on dark charcoal.
Focus: scale 1.10, rise 8 px, white ring, profile glow, name gray→white,
layered avatar tilt ≤1.5°.
Selection: compress → glow expands → others fade to 45% → PIN if required →
load that profile's theme/layout/add-ons/CW/Library/source prefs → Home fades
in → returning profiles restore prior Home focus.

## 16. PIN Entry

Overlay (blur+darken profiles screen). Centered panel: avatar, name, "Enter
PIN", 4 positions, keypad (keys ≥92 px). Focused key: white bg, black text,
scale 1.08, deep shadow. Wrong PIN: one restrained shake, red error text, no
bouncing, reset ~600 ms. Repeated failures → temporary delay.

## 17. Top Navigation

Central structural change. Items: Fusion logo, Home, TV Shows, Movies, Live
TV, Collections, My Fusion, Discover, Search, Add-ons, Profile. Disabled
destinations disappear entirely (e.g. Live TV hidden). Bar 52–64 px from top;
logo 105–140 px wide; labels 20–23 px semibold.
**Resting** (content focused): labels ~66% white; current page full white +
thin accent underline; black gradient protects over bright art; must not read
as a thick permanent panel.
**Focused item**: pure white, scale 1.045, underline expands, optional dark
capsule, neighbors dim slightly, art stays visible.
**Selecting**: label compresses; underline brightens; old page stores focus,
shifts 18 px left and fades; new page enters 28 px from right; nav stays
stable; new page restores remembered focus or default.

## 18. Back Button

At page root, Back → top navigation: stop preview, pause hero rotation, store
row+card, reveal nav, dim content to ~72%, focus current destination; 260–320
ms. Down from nav returns to stored item (else hero Play). Back in Detail →
originating card. Back in dialog → close dialog only. Back in playback →
reveal controls / exit panels first.

## 19. Home Background

Base `#070707`. No hero art → subtle wash:
`radial-gradient(circle at 72% 12%, rgba(120,120,120,0.10), transparent 48%)`
over `linear-gradient(180deg, #111111 0%, #070707 58%, #000000 100%)`.
Hero active → title art fills top region, dissolves into black. Lower Home
stays stable black.

## 20. Modern Home Layout

Top nav + full-width billboard + optional preview video + Play & More Info +
manual hero browsing + auto rotation + first row peeking beneath billboard +
focus-following background behavior + portrait/landscape cards. Billboard
dominates first screen; first row peeks (upper ~2/3 of heading + first cards).

## 21. Billboard Background

Full width, ~620–700 px tall. Subject right half; left kept visually empty for
text. Aspect-fill, never stretch. Four overlays: left readability gradient
(almost black at edge, fading from ~28%, mostly transparent ~75%); bottom
gradient blending into `#070707`; top nav gradient; broad outer vignette. Art
emerges from darkness, not a rectangular banner.

## 22. Billboard Foreground

Text block ~86–110 px from left; vertical center ~330–440 px from top. Order:
source/collection label → title logo/text → recommendation/rating line →
release/format metadata → synopsis → actions → carousel indicators. Region ≤
650 px wide. Logo ≤560×185; else 60–76 px bold text. Metadata e.g.
`96% Match • 2026 • TV-MA • 3 Seasons • Dolby Vision` (match value green or
accent; rest white/gray). Synopsis ≤3 lines, end fades (no hard cut); full text
via More Info.

## 23. Billboard Play Button

White bg, black text; height 58, min width 142, padding 30, radius 8–12. Label:
Play / Resume / Watch Live / Play Episode / Continue.
Focused: 1.055, rise 2 px, brighter, bigger shadow, subtle white edge, hero
rotation pauses.
Select: compress 85 ms → rotation stops → preview audio fades → Auto Link
Selector; spinner if >~180 ms; success → playback loading; failure → Streams.
**Hold Play always opens Streams directly.**

## 24. More Info Button

`rgba(109,109,110,0.72)` bg, info icon + white text. Focused: 1.05, lighter,
white border, bigger shadow, billboard locked. Select → Detail; transition
starts from billboard content, background stays while Detail info fades in.

## 25. My Fusion Button

Unsaved: plus (My Fusion / Add). Saved: check (In My Fusion). Add: compress →
plus morphs to check → accent/gray fill → Library updates immediately → Trakt
sync queued → "Added to My Fusion" toast. Remove offers Undo.

## 26. Hero Carousel

Up to 10 titles. Source: first catalog row / configured Trending / featured
collection / Continue Watching / community collection / mixed. Defaults: 8 s
initial idle; 7 s dwell; 500 ms transition; preview ~2.5 s after stable. The
old 2 s Fusion rotation stays available as "Fast Showcase".

## 27. Auto Rotation Rules

Only when genuinely idle. Timer resets on any input (directional, touch,
select, back, play/pause, voice, nav, scroll, unmute, dialog). Advance in
order; wrap unless disabled. Pause IMMEDIATELY on interaction (never finish an
in-progress transition after the user moves). No restart until a fresh idle
period.

## 28. Hero Transition

Logo fades ~180 ms; synopsis ~140 ms; old art shifts left ~8 px darkening; new
art starts 12 px right, fades in; full crossfade ~500 ms; new title rises from
8 px below; metadata +80 ms after title; buttons stay in place (labels/states
crossfade); pagination updates 180 ms.

## 29. Manual Hero Navigation

Billboard title area focused: Left/Right = prev/next title; Select = More
Info; Play/Pause = play; Up = nav; Down = first row. On buttons: Left/Right
move between actions first; beyond first/last action may change hero; strong
swipe beyond group changes hero. Manual 380–430 ms; rapid 220–260 ms. Never
block movement on artwork loads; cancel unfinished loads, show final title.

## 30. Hero Dragging

Continuous touch: drag between heroes; commit at ~32% width (less at high
velocity); else spring back ~220 ms. Never rest between titles.

## 31. Hero Pagination

Below action row. Inactive 7×7 @32% white; active 28×7 accent; 180 ms animate.
Not focusable by default (accessibility option may enable).

## 32. Preview Autoplay

Per-profile. Default delay 2.5 s; options Off/1/2/3/5/8 s. Start: title stable
→ idle delay → player prepares invisibly → static art darkens ~3% → first
frame → crossfade 450–550 ms → muted + indicator; text/controls stay. Cancel
immediately on focus move/scroll/nav/detail/play/dialog/background/disabled:
audio ≤120 ms, video ≤250 ms, static returns without black flash.

## 33. First Content Row

Peeks over billboard's bottom fade. Continue Watching first if present, else
first enabled catalog row. Heading 28–31 px bold. Down from billboard scrolls
row fully into view; billboard moves up and darkens.

## 34. Hero → Rows Focus

Down from Play → card most aligned beneath; from More Info → center-left card;
from My Fusion → farther right. If the hero was entered from a card, plain
Down returns to it. Page move 260–320 ms; button hands off as card grows.

## 35. Content Rows

Dense and fast. Landscape ~5–6 full cards + partial; portrait ~6–8 by poster
size. Gap 18–24 px; right edge reveals part of next card; focused card stays in
a comfortable central region; each row remembers horizontal position.

## 36. Row Focus Movement

Right: shrink current, enlarge destination ~20 ms later; scroll when nearing
right boundary; settle between 36–72% width. Down/Up: nearest horizontal
center in adjacent row. Never reset rows to first item. At row ends, extra
press = subtle 3 px resistance.

## 37. Expanded Card (optional)

After ~450 ms stable focus, card expands down/up: title, match %, rating,
runtime, seasons, genres, Play, Add, Rate, More Info. Panel `#181818`,
attached to artwork; expand 220–260 ms; close ≤170 ms; neighbors move
minimally. Disable-able in Performance settings.

## 38. Continue Watching

Landscape cards: artwork, progress bar (accent fill, ~28% white track, 5–7 px),
title, S/E, remaining time, optional Next Up, optional spoiler blur.
Selecting must NOT replay a stored expiring URL — re-query sources and match
prior quality/HDR/DV/Atmos/release; no close match → Streams.
Long press: Resume / Start Over / More Info / Manual Sources / Mark Watched /
Remove from Continue Watching.

## 39. Catalog Rows

Row titles may show add-on name, type, source badge, More. Poster sizes 180/
220/264 stay. Modern may use 16:9 stills. Captions on/off (title must still be
available via hero/expanded card/accessibility). Hide unreleased when enabled.

## 40. TV Shows Page

Top nav stays. Filter strip: Featured / New / Popular / Genres / Networks /
A–Z. Smaller billboard (title, match/rating, year, seasons, rating, synopsis,
Play, More Info, Add). Rows: New Episodes, Trending Series, Continue Watching,
Complete Series, Drama, Comedy, Crime, Reality, Documentary, Sci-Fi,
International, Kids. Feature art dissolves into black under first rows.

## 41. Movies Page

Like TV Shows with movie metadata (year, rating, runtime, genres, quality
formats). Rows: New Movies, Popular, Action, Comedy, Drama, Horror, Family,
Documentaries, Award Winners, Recently Added, Leaving Soon. All Movies = dense
poster grid + filters (dark overlay or pushed screen, no web dropdowns).

## 42. My Fusion

Personal destination (Netflix's "My Netflix" concept + Fusion cloud/Trakt).
Order: Continue Watching, My List, Cloud Library, Recently Watched, Rated
Titles, Trakt Watchlist, Saved Live Channels, Reminders, Upcoming Episodes.
Stable black bg (no billboard unless configured). Big "My Fusion" title. Tabs:
Overview / Saved / Cloud / History / Ratings / Live — each preserves scroll +
focus.

## 43. Saved Library

Movies / Shows split. Sort: Suggested, Added, Name, Recently Watched, Release
Date (Recently Watched uses real CW timestamps). Poster rows or grid; empty
sections explain + Browse button.

## 44. Cloud Library

Debrid files: parsed title, original filename, provider (small icon),
resolution, size, date, audio/HDR badges. Selecting plays DIRECTLY (no
scraping). Multiple files per item → compact file list.

## 45. Collections

Curated categories, not computer folders. Appear as pinned Home row / category
row / folder tile / detail page / combined All tab / per-folder tabs. Built
from discover queries, companies, people, networks, Trakt lists, ids.
Folder tile: layered artwork (front sharp, two offset rear), title + count
below. Focused: 1.08, rear layers separate, white edge, accent glow (when
Focus Glow on), optional collage page background. Opens to remembered item.

## 46. Community Collections

Polished curated packs: logo, artwork montage, description, catalog count,
installed state. Uninstalled → preview page; Install compresses → spinner →
check; new rows fade into Home; confirmation toast.

## 47. Search

From top nav. Pure black. Large field top; keyboard left/lower; results
right/below. Keep 350 ms debounce, parallel add-on search, streaming results,
dedup by id+type. Focused key: white bg, black char, 1.10, strong shadow.
Sections: Top Results, Movies, TV Shows, Episodes, Live Channels, Collections,
People, Companies. New results never steal focus.

## 48. Discover

Dark grid; large filters on top (Movies/Series, Catalog, Genre, Year, Rating,
Sort, Provider). Focused filter: gray raised, white text, accent underline.
Filters open pushed list/dark overlay. Infinite scroll: preload at last two
rows; skeletons below; append without moving focus.

## 49. Live TV

Featured live billboard (channel logo, program, time, progress, Live badge,
Watch Live, Start Over, More Info) + rows: Recent, Favorites, News, Sports,
Entertainment, Local, International, By Country, By Language. M3U plays
immediately; add-on channels open Streams. Destination disappears when hidden.

## 50–51. Detail Page & Background

Billboard expands into a title environment: originating art enlarges, row
darkens, backdrop crossfades. Content: logo, match/rating, year/maturity/
runtime/seasons, format badges, synopsis, action row, seasons/related, lower
sections. Full-bleed backdrop, subject right of center, left heavily dark,
bottom blends to pure black, top dark for controls. Trailer autoplay after
idle delay. Missing art → black-to-charcoal gradient + text (never a broken
image icon).

## 52. Detail Action Row

Order: Play/Resume, Play From Beginning, My Fusion, Watched, Rating, Trailer,
More. Play = white; secondary gray/dark circles; active saved/watched = accent.
Stable single baseline; focused action scales + brightens.

## 53. Detail Play

Auto Link Selector considers preferred/secondary add-on, min quality, max
size, cached preference, resolution filters, codecs, HDR/DV, audio. Found →
play; disabled/failed → Streams; **hold Play → Streams always**.

## 54. Play From Beginning

Ignores progress, keeps source prefs. Minor progress → start immediately;
significant → confirm "Start from the beginning?" default Cancel.

## 55–56. My Fusion & Watched Toggles (Detail)

Add: compress, morph icon, update Library, queue Trakt, toast; remove offers
Undo; stays on page. Watched: mark complete, check, remove/advance CW, queue
Trakt history, update recs, toast; toggleable.

## 57. Rating Overlay

Five stars centered over darkened/blurred Detail; current selection accent;
Left/Right change, Select confirms, Back cancels; returns focus to Rating.

## 58. Extended Synopsis

"More" teaser → full-screen dark reading overlay (image faint behind heavy
black), wide readable column, remote vertical scroll, Back restores exact
focus.

## 59. Trailer Autoplay (Detail)

Idle delay → prepare → backdrop darkens slightly → crossfade 500 ms → muted +
control; text/actions visible; any input pauses. On leave: tear down player
AND loop observer (no leaked resources).

## 60. Seasons

Chips above episodes. Selected: accent fill + white text. Focused unselected:
gray raised, white edge, 1.035. Change: compress → fade episodes 140 ms →
skeletons if needed → fade in 220 ms → restore remembered episode.

## 61. Episodes

Landscape cards: thumb, number, title, air date, runtime, progress, watched,
synopsis, unreleased state. Focused: thumb scales, white edge, description
expands, progress brightens, background may update after delay. Select =
play/resume. Long press: Play, Start Over, Manual Sources, Mark Watched, Add
to My Fusion, Episode Details.

## 62. Cast

Horizontal person cards (headshot, name, character). Focused: enlarge, white
ring, name white, character brighter; optional filmography-image background.
Select → filmography.

## 63–67. Franchise / More Like This / Companies / Comments / Parental Guide

- Franchise row "Part of the Collection", standard cards.
- More Like This: dense row, standard focus, bg updates only after stability
  delay, loads independently.
- Companies: dark tiles, centered original-brand logo; focused 1.06 + white
  edge + lighter charcoal. Select → company browse.
- Comments: charcoal cards (avatar, user, date, spoiler state, text, likes);
  spoilers blurred until confirmed; no parallax.
- Parental Guide (only when enabled): Sex/Violence/Profanity/Drugs/Frightening,
  each icon + severity + summary + expand. Neutral warning colors.

## 68–70. Streams Source Picker

Top: Back, title, content title, filter chips, Refresh, recommended summary.
Grouped 2160p/1080p/720p/480p, size tiers within. Ranking keeps cached state,
release quality, codec, HDR, DV, audio, seeders, bitrate, size, add-on.
Row shows: resolution, release type, size, codec, HDR, DV, Atmos, audio,
bitrate, seeders, add-on, cached, language, group. Row bg `#181818`; focused
`#2A2A2A`, 1.012, white edge; recommended marker = accent; Cached/Instant =
success green. Select: compress → verify → Preparing Stream overlay → resolve
→ engine init → play; failure returns to the same row with Retry / Try Next
Best / Choose Another Source / Change Player.

## 71. Playback Loading

Black; optional heavy-blur backdrop; center logo + spinner + status (Searching
Sources / Ranking Results / Connecting to Provider / Preparing Video / Loading
Subtitles / Starting Playback), crossfade 150–180 ms; skip statuses when fast.

## 72. Video Player

Video only; controls auto-hide 3–5 s; video darkens slightly with controls.
Top: Back, title, episode, source, clock. Center: RW / Play-Pause / FF.
Bottom: timeline, current, remaining, buffered, chapters, intro marker, live
position. Right: Audio, Subtitles, Episodes, Scaling, More.

## 73. Scrubbing

Hold playback; enlarge timeline + thumb; preview thumbnail + exact timestamp;
dim other controls. Slow = precise; sustained accelerates; reversal slows
immediately. Select confirms; Back cancels/restores.

## 74. Skip Intro

Dark rectangular button lower-right; focused = white bg/black text/1.05.
Select: compress → seek → fade → continue. Auto-skip shows "Intro Skipped"
toast with temporary Undo.

## 75. Up Next

Card near end: next image, number, title, countdown (accent ring/bar), Play
Now, Cancel. Per-profile autoplay preference; Still Watching after configured
episode count.

## 76. Audio/Subtitle Panel

Right panel 540–620 px, `rgba(10,10,10,0.95)`. Sections: Audio, Subtitles,
Appearance, Timing. Focused option: gray raised, white text, check, accent
indicator. Immediate apply; Back closes → prior player control.

## 77. Quick Actions (long press)

Card stays enlarged; page darkens; charcoal menu: Play/Resume, More Info, Add,
Mark Watched, Start Over, Manual Sources, Remove from CW. Safest action gets
focus; Back restores card.

## 78. App & Source Icons

Rounded-square tiles (add-ons, debrid, external players, community packs,
integrations): logo, dark/branded bg, Installed/connection/warning badges.
Focused: 1.08, rise 8 px, white edge, deeper shadow, slight parallax, logo
layer +3–5 px, optional source-color glow.

## 79. Settings Main

Dark list. Categories: Account & Profiles, Appearance, Themes, Layout, Content
& Discovery, Integrations, Plugins, Playback, Performance, Trakt, About. Row
transparent black; focused `#282828`, white text, accent bar left, 1.012,
chevron +3 px. Select pushes detail from right.

## 80–90. Settings Panes (keep full Fusion content)

- **Account & Profiles**: manage/add/rename/recolor/avatar/PIN/remove; Auto
  Link Selector, preferred/secondary add-on, min quality, max size. Profile
  cards w/ avatar + color; destructive remove confirms.
- **Appearance**: accent swatches (focused 1.12 + ring + glow + live preview),
  AMOLED (pure black), Font (System/Rounded/Serif/Mono), Experience Mode,
  Settings Style (Classic/Zen/Horizon).
- **Themes**: App Theme (Netflix-inspired / Apple TV / Classic) + appearance
  mode; large preview; confirm big changes; preserve all data.
- **Layout**: Modern/Classic/Grid, landscape posters, labels, size, radius,
  fullscreen backdrop, hide unreleased, add-on name, type suffix, full release
  date, trailer button, CW sorting, episode thumbs, next-up, spoiler blur,
  catalog order, collections. Mini live preview; never replaces real page
  until applied.
- **Content & Discovery**: add-ons, discover, catalog order, community
  catalogs/collections, refresh all (non-blocking progress), export QR,
  installed list, refresh timer, Live TV visibility, location/language
  filters, badge packs.
- **Integrations**: TMDB (per-feature toggles: cast, trailers, more-like-this,
  details, release dates, companies, collections, episodes), MDBList, Debrid
  (branded tiles, QR sign-in, preferred check), Anime Skips, TorrServer/P2P.
- **Plugins** (Advanced only): repos → scraper lists; add via manifest/QR;
  remove confirms.
- **Playback**: Autoplay, Seeking, Skip Intro, Sources, Content, Auto-play
  Source, Player, OSD, Audio, Subtitles, Trailers — full existing control set,
  descriptions in tertiary gray.
- **Performance**: Performance Mode (instant, no restart — disables preview
  autoplay, hero video, backdrop updates, parallax, heavy blur, large shadows,
  expanded cards, aggressive preloading), Reset to Recommended, Billboard
  Artwork, Hero Crossfade, Card Shadows, Focus Zoom, Navigation Animations,
  Button Effects, Row-Ahead Preloading, Artwork Fade-In, FPS overlay (green
  55–60, amber 40–54, red <40).
- **Trakt**: device-code sign-in (large code + QR), scrobble, history, CW,
  watchlist, ratings, Sync Now (per-category progress, backgroundable), sign
  out.
- **About**: version, build, privacy, licenses, attributions, device, tvOS,
  Clear Cache (explains scope, never removes profiles/libraries/settings,
  confirms), metadata/image-cache/source-list diagnostics.

## 91–95. Controls

- **Toggles**: off = dark-gray track; on = accent + white knob. Focused: 1.06 +
  white outline + brighter title. Select: compress, knob 170 ms, track 130 ms,
  dependent rows 220 ms, announce value.
- **Sliders**: dark track, accent fill, white knob; row brightens; value
  prominent; Left/Right step; hold repeats after ~400 ms; Select = fine mode;
  Back exits adjustment.
- **Pickers**: pushed list or centered dark panel; current = check + accent;
  focused = `#303030` + white + slight scale; simple pickers auto-close;
  multi-select stays until Done.
- **Dialogs**: centered over dim+blur; 720–900 px; `#181818` /
  `rgba(24,24,24,0.96)`; big white title, gray body; safest action focused;
  destructive = red text, fully red only when focused.
- **Toasts**: lower center; `rgba(24,24,24,0.96)`; white text; accent/green/
  amber/red icon; never steal focus; Undo for reversible actions.

## 96–97. Loading & Errors

Never blank when layout is known: skeletons `#1B1B1B` / highlight `#292929`,
slow low-contrast shimmer (no bright white). Nav + headings immediate; low-res
art fades to high-res; long loads → message + Retry.
Offline: icon, "You're offline", explanation, Retry, Network Settings,
available cloud/local content. Playback failure: "We couldn't play this
title", Try Next Best Source, Choose Another Source, Change Player, Return to
Details. Metadata failure: keep play actions, hide failed sections, title text
when logos fail. Artwork failure: gradient, never broken-image icon.

## 98–99. Reduced Motion & Accessibility

Reduce Motion: no hero dragging/parallax/reflections/background zoom; slides →
fades; reduced card scale; optionally no auto-rotation; no expanded-card
animation; strong focus borders; zero functionality removed.
Accessibility: every control exposes name/value/state/hint; VoiceOver
announces title, type, progress, watched, saved, cached, resolution, tab,
setting value; focus order = visual geometry; never color-only status.

## 100. Focus Memory

Remember focus separately for: Home hero, each Home row, TV Shows, Movies, My
Fusion tabs, Search, Discover, Live TV, collection pages, Detail actions,
seasons, episodes, Streams, settings categories + details. Returning restores
exact card, row position, scroll, hero title, tab, filters, season, source
filter, background art.

## 101. Universal Selection Contract

Focus distinct → Select compresses → highlight brightens → position stored →
previews/rotation pause → destination grows from the object → page loads →
focus at logical primary action → input unlocks → Back returns to origin.
Cards→Details; Play→auto resolution; held Play→Streams; collections→curated
pages; cast→filmography; companies→browse; channels→play/Streams; cloud→direct
play; settings rows→detail; toggles→immediate; sliders→adjust; profiles→
personalized state.

## 102. Final Intended Experience

A polished streaming service on Apple TV with Fusion's power underneath.
Cinematic first impression; quiet top nav; billboard alive only at rest; rows
dense/fast/predictable; cards grow and brighten without excess reflectivity;
Play hides source complexity (held Play = full control); My Fusion = one
personal destination; settings reveal depth only when opened.
**Simple when watching, fast when browsing, powerful when asked.**

---

## Implementation status

**Architecture**: GROUND-UP theme, the way Fusion stands apart from Classic.
Everything gates on `theme.isNetflixTheme`; it does NOT ride `isAppleTVTheme`.
Own chrome = `NuvioTVApp.netflixLayout` (per-tab NavigationStacks over the
shared roots) + `Screens/NetflixNav.swift` (`NetflixTopNav`, `NetflixBackground`).
Own tokens = `Theme/NetflixTokens.swift`; palette via `NetflixPalettes.adapt`.

- **2026-07-19 · Session 1 (foundation + chrome skeleton)**: theme registered
  (`netflix`, `-netflixTheme` dev arg); tokens (§5 surfaces, §6 accents, §8
  motion, §9 focus constants); palette adapter; §19 black-stage background;
  custom §17 top navigation (logo, 66%-white resting labels, accent underline,
  focus scale, profile chip, protection gradient, Back-at-root → bar per §18);
  toasts enabled (§95 via shared host). Home/cards currently render the
  Classic behaviors on the black stage — the theme's own §20–31 billboard, §9
  card focus treatment, §35–37 rows/expanded cards, §42 My Fusion page, §79
  settings restyle (interim: shared ATV settings list), TV Shows/Movies/
  Collections/Discover nav destinations are future sessions.
