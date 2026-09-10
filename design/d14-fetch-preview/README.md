# D14 Fetch button — interactive preview

Static, self-contained HTML mock (`index.html`) of the locked D14 design
(cc.md §6): the Fetch button, its slide-down track panel and the subtitle
search window. Review artifact only — not the real player, no Flutter code.

## Run

```bash
cd design/d14-fetch-preview
python3 -m http.server 8531 --bind 0.0.0.0
# → http://localhost:8531
```

(Or just open `index.html` in a browser.)

## What it demonstrates (all locked in cc.md §6)

| Behavior | Decision |
|---|---|
| Button left of fullscreen, local video only (greyed out + inert — never hidden — for audio/channels/URLs) | §6.1 · D6 |
| Panel slides down from the control row, floats over the video | §6.2 · rule 5 |
| Esc / click-outside close; opening the search window keeps the panel | §6.2 · rule 3 |
| Panel stays open across taps, marks mirror mpv live | §6.2 |
| Media change (Next) closes the panel | §6.2 |
| Part 1 audio tracks, real language names, untagged → "Track n" | §6.3 |
| Part 2 embedded subs, **Off pinned on top**, mirrors mpv's pick | §6.3 |
| Part 3 local subs (autoloaded + loaded), same selection domain | §6.3 |
| >5 rows per part → fixed 5-row inner scroll | §6.3 |
| Load mark → real file picker, session-only | §6.4 |
| Search window: editable name, Search/Save/Save&Load/Close, glass modal | §6.5 |
| Group A = best 3 in preferred language · Group B = all languages | §6.5 |
| Rows are subtitle files; Save writes `<basename>.<lang>.srt` (OSD card) | §6.5 · D8 |
| Save & Load applies now, row lands in Local marked (live mirror) | §6.5 |
| No OSD for track switches — the row mark is the feedback | §6.6 · D10 |

Demo state: preferred language = Bangla; Next cycles
Interstellar (rich tracks) ↔ Dune (bare, Off marked — the auto-fetch case).

Design tokens mirror `lib/theme/app_theme.dart` (AppColors); motion and the
icon recipe follow follow.md (fade + scale 0.96→1.0, hover glow 1.06,
press 0.90, custom thin monochrome marks, no ripples).
