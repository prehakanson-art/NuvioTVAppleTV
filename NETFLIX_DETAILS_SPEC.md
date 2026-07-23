# Orivio Netflix-Style Details Page & Choose Version — Blueprint

Complete replacement specification for the Netflix theme's Details page (Part
One) and the "Choose Version" source picker (Part Two). Delivered 2026-07-19.
Companion to NETFLIX_THEME_SPEC.md; same ground-up rule (gate on
`isNetflixTheme`). Implementation status at the bottom.

---

# PART ONE — DETAILS PAGE

## 1. Purpose

The title should feel like it expanded out of the browsing row and took over
the screen — not a database page. First screen answers: What is this? Why
watch it? What happens on Play? Emphasize artwork, Play, synopsis,
recommendation callout, rating, runtime, year, few personal actions. NO
providers, codecs, seeders, filenames, comments, company data, or advanced
playback controls in the first visual layer. Complexity unfolds progressively.
Almost no visible container — artwork + black gradients create the structure.

## 2. Entry From a Card

Details grows from the selected card (no black flash ever):
- **Stage 1 — confirmation (85 ms)**: card compresses, white edge brightens,
  preview/hero rotation stop, Home focus + row position stored.
- **Stage 2 — environmental takeover (220 ms)**: row dims to ~35%, page bg
  fades toward black, card rises ~6 px, backdrop starts loading behind it.
- **Stage 3 — expansion (340–390 ms)**: full-screen backdrop crossfades, card
  fades out, title logo appears left, actions rise from 8 px below, metadata
  shortly after title. (Card never literally stretches poster→landscape.)
- **Stage 4 — focus arrival**: focus lands on Play/Resume, input unlocks,
  trailer-autoplay delay starts only after the page fully settles.

## 3. Background

Full-screen cinematic backdrop, aspect-fill (never stretch), subject usually
right half, left half darker negative space. Base `#070707`. No artwork →
`radial-gradient(circle at 72% 18%, rgba(88,88,88,0.13), transparent 46%)`
over `linear-gradient(180deg, #151515 0%, #070707 58%, #000000 100%)`.
Never a broken-image symbol or gray rectangle.

## 4. Protection Layers

- **Left text gradient**: 90°, rgba(5,5,5,0.99) 0% → (6,6,6,0.95) 20% →
  (7,7,7,0.80) 40% → (7,7,7,0.48) 58% → (7,7,7,0.12) 78% → transparent 100%.
- **Bottom content gradient**: 0°, #070707 0% → (7,7,7,0.98) 18% →
  (7,7,7,0.72) 38% → (7,7,7,0.22) 64% → transparent 84%.
- **Top gradient**: 180°, rgba(0,0,0,0.68) 0% → (0,0,0,0.20) 52% → transparent.
- **Outer vignette**: corners darken 15–25%, subtle, never a visible frame.

## 5. Ambient Backdrop Motion

Optional (Reduce Motion off): scale 1.00→1.025 over 18–24 s, horizontal drift
≤8 px; felt, not noticed; NEVER pans back and forth. Pause immediately on:
preview start, dialog, scrolling, Choose Version, Reduce Motion, Performance
Mode.

## 6. Main Content Area

Left side. Left edge 92–116 px; top ~210–260 px; max width 660 px; bottom
before lower sections ~650 px. Order: ① contextual callout ② title logo/text
③ match+metadata line ④ secondary format/accessibility badges ⑤ synopsis
⑥ action row ⑦ optional short cast/genre line. Spacing, not boxes.

## 7. Contextual Callout

One concise reason to watch above the logo (18–20 px, weight 650, white, one
line, optional small accent icon): e.g. Emmy Award Winner / #1 in Movies Today
/ Highly Rewatched / Critically Acclaimed / New Episode / Leaving Soon /
Because You Watched… / Orivio Top 10. Must be grounded in real data — never
invent awards/rankings/reasons.

## 8. Title Logo

Transparent logo when available: ≤560×185, left-aligned, never stretched to
fill both dimensions. Text fallback: 58–74 px, weight 750–800, max two lines,
white, tight line height, subtle black shadow. Long titles may drop to 46 px.

## 9. Match / Metadata Line

One line under the title: `96% Match • 2026 • TV-MA • 2h 14m` (series:
`… • 4 Seasons`). Match value `#46D369`; rest `#D2D2D2`; dot separators ~55%
opacity. May include match, year, maturity, runtime, seasons, Limited Series,
Final Season, New Episode. NEVER codec/provider/bitrate/size/add-on here.

## 10. Maturity Rating

Compact bordered box: height 28, h-padding 8, border 1px
rgba(255,255,255,0.55), text 16–18 px, radius 2–4. Quieter than Play.
Parental detail lives farther down the page.

## 11. Format / Accessibility Badges

Second quieter line: 4K, HDR, Dolby Vision, Atmos, 5.1, AD, SDH, CC. Thin
white/gray outlines, compact, MAX FOUR in the initial area (rest in More
Details / playback options). SDH / AD / language availability must be visible
without starting playback.

## 12. Synopsis

Width 590–650; 22–25 px; weight 400; LH 31–35; `#E3E3E3`; max FOUR lines;
gentle opacity fade at overflow + small "More" control → full-screen overlay.
Never auto-scrolls.

## 13. Action Row

Order: ① Play/Resume ② Play From Beginning (only when progress) ③ My List
④ Rate ⑤ Choose Version ⑥ More. One-version titles may hide Choose Version
from the row (stays in More). Single baseline; spacing 16–20 px; Play
dominant.

## 14. Play / Resume Button

White bg, dark text. H 58, min-W 146, pad 30, radius 8–12. Black play icon +
Play/Resume/Continue/Watch Live/Play Episode.
Focused: 1.055, lift 2 px, brighter white, shadow `0 14px 34px rgba(0,0,0,0.52)`,
soft white outer edge, neighbors dim ~4%.
Pressed: 0.985 over 85 ms, shadow tightens.
Select: compress → trailer/preview audio stops → auto source resolution →
quick resolve = play; >~180 ms = spinner inside button; failure = open Choose
Version. **Hold Play always opens Choose Version.**

## 15. Play From Beginning

Only when meaningful progress. Dark gray bg, restart icon, white text. Ignores
saved position, keeps all quality/provider/audio/subtitle/player prefs.
Progress >~10 min → confirm "Start from the beginning?" (Cancel focused).

## 16. My List

Circular/rounded dark control. Unsaved: plus ("Add to My List"). Saved: check
("Remove from My List"). Focused: 1.07, lighter gray, white outline, tooltip
under after ~250 ms. Select: compress → plus morphs to check 180 ms → Library
updates immediately → toast (+Undo on remove). No page reload.

## 17. Rating

Thumbs-up icon; opens 3 choices directly above the action row on `#181818`:
Not for Me / I Like This / Love This (thumbs-down / thumbs-up / double-up or
heart). Selected = white or accent. Updates recommendations without leaving
the page. (Five-star stays available in advanced profile settings.)

## 18. Choose Version Control

Replaces the developer-facing "Sources" label. Stacked-rectangle/sliders icon,
dark gray circle, tooltip "Choose Version". Appears when: multiple sources /
hold Play / auto-selection fails / Always Show enabled / substantially
different 4K-HDR-language-audio options. NO provider/add-on/scraper wording
on Details.

## 19. More Control

Menu: Trailer, Episodes, Audio Availability, Subtitle Availability, Cast &
Crew, Parental Guide, Mark Watched, Remove from Continue Watching, Report
Metadata Problem, Advanced Playback Options. Dark vertical panel near the
row; opener stays visually connected; Back closes → focus returns to More.

## 20. Action Focus Movement

Left/Right between actions, 180–210 ms; current shrinks, destination grows
~20 ms later. Row doesn't scroll unless overflowing. First-action + Left →
Back only when spatially right, else 3 px resistance; last + Right → same
resistance, never an unexpected page. Down → first lower section; Up → Back /
title only when focusable.

## 21. Background Trailer Autoplay

Default delay 3 s after page settles + no input. Prepare invisibly → static
darkens ~3% → first frame → crossfade 500 ms → muted + icon (lower/upper
right). Title info and controls stay; left gradient stays OVER video. Stops
on: focus into lower sections, Choose Version, dialog, playback, Back,
backgrounding. Release resources on close.

## 22. Scrolling Below the Hero

Hero = first ~620–700 px; part of first lower section visible. Down from
actions scrolls up over 260–330 ms; title area shrinks in prominence;
backdrop darkens + blurs slightly; Back stays available; logo may become a
small persistent header.

## 23. Series: Season Selector

First lower section: season selector + episode list (+ optional sort). Compact
dark button "Season 3" → vertical menu (number/name, episode count, year,
watched progress; selected = check). Focused season: `#303030`, 1.015, white
text, stronger shadow. Change: menu closes → episodes fade 140 ms → skeletons
if needed → new fade in 220 ms → focus on remembered/first episode.

## 24. Episode Cards

Wide landscape cards (not list rows): thumbnail, number, title, runtime, air
date, progress, short description, watched, New Episode callout,
unavailable/unreleased. Focused: 1.055, white edge, strong shadow, thumb
brightens, description expands, progress brightens, play icon over thumb;
gentler tilt than browsing art. Select = play/resume via auto selection.
**Hold Select/Play = Choose Version for that episode.**

## 25. Episode Quick Actions

Long press: Play/Resume, Start From Beginning, Choose Version, Mark Watched,
Add Series to My List, Episode Details. Beside the episode when space allows;
page dims; Back restores focus.

## 26. More Like This

Netflix-style row, large dense cards. Optional single contextual label under
the FOCUSED card (Award Winner / Popular Now / Similar Tone / From the Same
Creator / Because You Watched…). Background updates only after the 160 ms
focus-stability delay.

## 27. Trailers and More

Landscape cards: thumb, title, runtime, type (Teaser / Official Trailer).
Plays in the standard player; hide source selection unless multiple trailer
versions truly exist.

## 28. Cast

Portrait cards: headshot, name, character. Focused: 1.06, white edge, name
white, character brighter. Select → filmography in the same Netflix-style
rows.

## 29. About This Title

Lower text-column section (not cards): creators, directors, writers, cast,
genres, advisories, audio availability, subtitle availability, original
language, release date, production companies, copyright. Focused links
brighten + subtle underline.

## 30. Parental Guide

Maturity rating + Violence / Language / Sexual content / Substances /
Frightening content, each with a short severity indicator. Neutral grays and
amber (not all red). Selecting a category expands the explanation.

## 31. Back Behavior

Order: close menu → close expanded synopsis → close Choose Version → return
from lower sections to hero (when appropriate) → exit Details to the
originating card. On exit: state preserved, trailer stops, backdrop fades,
originating row returns, focus lands on the original card (~220 ms),
horizontal + vertical scroll restored.

## 32. Loading State

Logo/metadata/Play appear as soon as basic metadata exists — never block on
cast/comments/recommendations/companies. Blurred backdrop placeholder, dark
logo placeholder, action skeletons, episode + recommendation skeleton cards.
Sections load independently; a failed section is omitted/replaced alone.

## 33. Error Behavior

Playback info fails → keep metadata, Play becomes Retry, keep Choose Version.
Artwork fails → dark gradient + text title, all actions functional.
Recommendations fail → hide More Like This (no full-page error). Episodes
fail → "Retry Episodes" inside that section.

## 34. Accessibility

VoiceOver order: title, type, match/callout, year, maturity, runtime/seasons,
synopsis, focused action. Badges announced once. Predictable left-to-right
action order. Reduced Motion: expansion/hero movement become fades.

---

# PART TWO — CHOOSE VERSION

## 35. Purpose

Replaces the raw source list. Initial view = a few understandable choices
(Recommended / Best Picture / Best Compatibility / Smaller File / Original
Audio / Another Version). The technical system keeps operating underneath;
full detail requires explicit action (Advanced Details / Show All Sources).

## 36. Openers

Choose Version control; hold Play; auto-selection unconfident; preferred
version fails; Change Version during playback; picking audio/video format
needing another source; "Always Ask Which Version" enabled. Opening pauses
any Details trailer.

## 37. Entrance

Details stays visible behind: freeze art/trailer frame, darken to ~28%
brightness, blur 24–30 px, slight desaturate, title logo faint on left. Panel
rises from ~18 px below while fading; 240–280 ms. Focus lands on Recommended.

## 38. Layout

Centered/right-weighted panel: W 980–1180, max-H 760, bg `rgba(18,18,18,0.96)`,
optional 28 px backdrop blur, radius 14–20, shadow `0 28px 72px rgba(0,0,0,0.68)`.
Contains: heading, short explanation, Recommended, other versions,
filters/Advanced, refresh status, Cancel.

## 39. Heading

"Choose a Version" (36–42 px, 700, white) + "Orivio recommends the best
available option for your device and preferences." (19–22 px, secondary gray,
≤2 lines). Optional small title thumb/logo. No add-on/provider names.

## 40. Recommended Version

First + largest wide card: Recommended label, resolution, HDR format, audio
format, approx size, Instant/Preparing state, short reason, play icon. E.g.
`4K Dolby Vision • Dolby Atmos • 24.8 GB` + "Best match for this Apple TV and
your playback settings". NEVER: filename, seeders, scraper, release group,
raw URL, provider id, codec profile string. Focused: 1.025, `#303030`, white
edge, strong shadow, label brightens, play icon right, green Instant badge
brightens when cached. Selected: compress → verify → playback loading; verify
fails → stay, highlight next best.

## 41. Recommended Reason

Plain-language, FROM ACTUAL RANKING LOGIC (never claim undetected features):
Best picture and audio available / Best match for your Apple TV / Fastest to
start / Matches your preferred release type / Best under your size limit /
Best subtitle compatibility / Matches the version you previously watched /
Original-language audio available / Avoids unsupported Dolby Vision profile.

## 42. Other Version Cards

Below Recommended; vertical wide cards (or horizontal row when 3–4). Show only
distinguishing info. Examples: Best Picture `4K HDR10 • Atmos • 42.1 GB`;
Fastest Start `1080p • 5.1 • 8.4 GB`; Smaller File `1080p • Stereo • 3.2 GB`;
Original Audio `4K • Korean Atmos • English Subtitles`; Compatibility
`1080p SDR • 5.1 • Works with all selected subtitle options`. Normally ≤5–6
simplified choices.

## 43. Quality Grouping

Many versions → group: 4K / HD / Data Saver / Alternate Language /
Compatibility. Label above cards; each version appears in exactly ONE
category (ranking decides the most useful).

## 44. Instant / Preparing

Cached: "Instant" — green + lightning, no provider name. Non-cached: "May
take longer" — gray/amber + clock. Preparing: spinner + status only when
reliable. No debrid terminology in the simple view.

## 45. Focused Version Card

Scale 1.018–1.025; `#181818`→`#303030`; white 2 px edge; shadow
`0 16px 38px rgba(0,0,0,0.56)`; primary label white; secondary brightens;
play icon fades in; Advanced Details hint appears. No strong parallax (text
content); trackpad ≤1°.

## 46. Selecting a Version

Compress 85 ms → revalidate → spinner replaces play icon → label "Preparing"
→ list dims slightly → loading screen after ~220 ms if not ready → play →
panel closes ONLY after player initialized. Failure: stay open, focus back on
the failed card, "This version is no longer available", offer Try Next Best,
auto-highlight next closest; never close the whole Details page.

## 47. Try Next Best

One action that picks the next source on the same ranking profile,
prioritizing similarity: resolution → HDR → audio → language → release type →
size → provider availability. User never needs to know why the original
failed.

## 48–49. Advanced Details Drawer

Open via long-press on a version / Info button / "Advanced Details" control /
Right from focused card. Right-side drawer (`#101010`, W 460–560); list stays
visible left. Shows EVERYTHING: filename, add-on, provider, cached, res,
codec, bit depth, HDR, DV profile, audio codec/channels, Atmos, language,
subtitles, size, bitrate, seeders, release type/group, container,
compatibility warnings. Labels tertiary gray, values white, warnings amber,
errors red. Doesn't steal focus; Back closes only the drawer.

## 50–51. Show All Sources (raw list)

Bottom control, never initial focus. Replaces cards with grouped rows (by
resolution), keeps title/filter header + "Back to Simple View". Row = two
lines: ① res, release type, short filename, size, cached ② codec, HDR, audio,
seeders, add-on, language, group. `#181818` / focused `#303030` @1.012.
Recommended = thin accent bar + label; cached = green Instant. Not a
spreadsheet.

## 52. Filters

Chips: All / 4K / HD / Instant / HDR / Original Audio / Smaller Files.
Focused: white bg, black text, 1.04. Selected: white/accent fill + check.
Filtering keeps current focus when possible.

## 53. Refresh

Upper-right. Icon rotates once; existing versions stay; "Checking for more
versions"; merge + dedupe; focus stays on the same logical version. Never a
full-screen spinner.

## 54. Progressive Loading

Recommended skeleton immediately; query all sources in parallel;
high-confidence versions appear as they arrive; re-rank as better ones land;
NEVER move focus from a card being considered — show a subtle "Better version
found" badge instead. Show results by ~3 s even if queries continue.

## 55. Ranking

Profile prefs: cached/instant, max/min resolution, HDR pref, DV support,
device compatibility, audio format, original language, subtitle
compatibility, release type, size limit, bitrate, seeders, provider
reliability, prior playback success, previously-watched characteristics.
Simple screen converts factors to labels, never shows the formula.

## 56. Returning Viewer Matching

Continue Watching recreates the prior version: same resolution → HDR → audio
→ language → release group → size tier → provider (when reliable). Card may
read "Matches the version you previously watched". Never reuse an expired URL
without revalidation.

## 57. Back Order

Close Advanced Details → Raw→Simple → close filter menu → close Choose
Version → focus returns to opener. Details trailer does NOT auto-restart;
preview-idle timer restarts only after fresh inactivity.

## 58. During Playback

Change Version: pause, preserve time, open over blurred frame, mark "Current",
rank alternatives relative to it; new version resumes at same time; warn if
edit/duration differs; Cancel resumes original.

## 59. Language Versions

Cards lead with language clarity (Original Korean Audio / English Dub /
Spanish Audio / English SDH Included / Commentary Track). Never require
filename inspection; warn when no compatible subtitles for the selected
language.

## 60. Compatibility Warnings

Concise, amber unless playback impossible (then red): DV may not display
correctly / subtitles require another player / Atmos unavailable on current
output / exceeds size limit / may take longer to start / resume position may
not match / audio language differs. Selecting opens the explanation.

## 61–62. Empty / Error States

Empty: "No versions are available right now" + "Try refreshing, changing your
source settings, or checking again later." + Refresh / Manage Sources /
Return to Details (art stays visible). Errors distinguish: none found /
provider not connected / network unavailable / add-on failed / auth expired —
plain language; technical codes only inside Advanced Details.

## 63. Accessibility

Announce per option: label, resolution, HDR, audio, size, instant/delayed,
reason, warning. Raw filename never announced unless drawer open. Focus
order: Recommended → others → filters → Refresh → Advanced → Cancel.

## 64. Reduced Motion

Panel fades without rising; cards scale ≤1.01; no background zoom; loading
indicators stay; Details card expansion becomes crossfade; trailer autoplay
separately disable-able.

## 65. Performance Mode

Backdrop blur → opaque dark overlay; no ambient motion; no background
preview; reduced shadows; no parallax; simplified cards immediately; limited
re-rank animation; full functionality preserved.

## 66–67. Intended Experience

Details: cinematic backdrop, one meaningful callout, title, concise metadata,
readable synopsis, dominant Play; more only on request; never technical
source info just for opening a title. Choose Version: complex sources feel
like a polished consumer feature — Recommended / Best Picture / Fastest Start
/ Smaller File / Original Audio — with debrid/scrapers/release
groups/codecs/seeds/filenames fully available but only behind Advanced
Details / Show All Sources.

---

## Implementation status

- **Not yet implemented.** A first hero-restyle pass was built and then
  REVERTED on user request (2026-07-19) — the Details page currently renders
  the shared header in every theme. This document remains the blueprint;
  nothing in Part One or Part Two exists in code yet. When implementation
  starts, follow the ground-up rule (gate on `isNetflixTheme`, own components,
  no live filters).
