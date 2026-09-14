# SALU — EQ / Tune panel (eq_imp.md)

> **Purpose:** What the Equalizer button does, in simple terms. One button,
> one panel, four parts. Everything works while playing — no restart, no
> stopping.
>
> **Design language (owner's final decision, 2026-09-13):** every selector
> in the panel is a **continuum — a thin line with labeled stops**. Audio
> presets, picture looks, aspect ratios and speeds are all stop-lines.
> (The glyph and dial candidates were previewed in `design/eq-preview/`
> and dropped — continuum locked for all four parts.)

---

## 1. The simple list (what this gives us)

1. **Add an Equalizer button** — new icon button just to the left of the
   subtitle (Fetch) button. Same look & feel as the existing buttons
   (custom thin mark — three sliders — grey → white on hover, glow when
   active).

2. **Opening it shows a panel with 4 parts** (slides down over the video,
   same recipe as the Tracks panel; Esc closes; opening it closes the
   other panels). **Each part is a labeled continuum:**
   - **Part 1 – Audio Equalizer**: continuum of presets (stops = the
     preset set, labels in short form where needed) + 10 band sliders
     below it (31 Hz to 16 kHz).
   - **Part 2 – Picture**: continuum of looks (stops = Original, Vivid,
     Night, Faded, Warm, Cool) + 5 fine sliders below it (Saturation,
     Gamma, Contrast, Brightness, Hue).
   - **Part 3 – Aspect**: continuum of shapes (stops = Auto, 4:3, 16:9,
     1.85, 2.35, 21:9, 1:1, 9:16) + "Snap window" toggle. Auto + Snap =
     "the window is the screen" (see point 10).
   - **Part 4 – Speed**: continuum of speeds (stops = 0.5×, 0.75×, 1×,
     1.25×, 1.5×, 2×, 3×) + "Keep pitch" toggle.

3. **Everything works while playing** — change takes effect instantly on
   the video/audio on screen.

4. **Your settings are remembered** — close the app, reopen it: your EQ,
   picture, aspect and speed come back exactly as you left them.

5. **"My" save slot** — a small save mark stores your current 10-band
   setup as "My"; the My mark applies it. **One shared slot for all
   files** — a single EQ state for the whole player (no separate
   music/movie memories; that idea was dropped). My is a mark below the
   line, not a stop on it.

6. **The preset set follows what is playing** (owner's idea):
   - **Audio file** (MP3, FLAC, …) → 13 preset stops: Flat, Pop, Rock,
     Jazz, Classical, Bass Boost, Treble Boost, V-Shape, Vocal, Lounge,
     Live, Dance, Phone (+ My).
   - **Video file** (MKV, MP4, …) → 4 preset stops: Flat, Movie, Music
     Video, Documentary (+ My).
   - The line re-lays out when the file type changes; your current curve
     is kept, and when it matches a preset of the new set the knob sits
     on that stop.

7. **Auto EQ (Settings switch, default OFF)** (owner's idea): when ON,
   SALU picks a preset the moment a file loads, and it learns from your
   corrections (see section 5).

8. **Hover to try, click to keep** (owner's gesture — applies to EVERY
   continuum, stop, look and fine slider):
   - Hover for a moment → you immediately *hear / see* that setting on
     the live playback (a hover over a stop previews that stop; a hover
     over the line previews the blend under the cursor).
   - Move the mouse away → it reverts to what you had. Nothing is saved.
   - **Single click → keeps it** (saved like everything else).
   - The preview starts after ~0.3 s on the control, so sweeping the
     mouse across does not flick through settings.

9. **Curve on the video** (owner's idea): a small mark in the panel draws
   the equalizer curve right on the picture itself, in a soft colour,
   like film grain. Toggle on/off. Only meaningful when the EQ is not
   Flat (when Flat the mark dims).

10. **The window is the screen** (owner's idea): with aspect on **Auto**
    and "Snap window" ON, SALU resizes the SALU window to the *actual
    shape of the file being played* — 2.39:1 movie → 2.39:1 window,
    4:3 cartoon → 4:3 window. **No black bars.** The cinema changes shape
    with every film. The window always stays centred and fits the screen.
    (On a fixed or custom stop, Snap window resizes to that shape.)

11. **Small extras**:
    - The sliders **smoothly slide** into a new curve (not a jump) — also
      when Auto EQ applies a preset at file load.
    - A small **curve line** above the band sliders shows the EQ shape at
      a glance.
    - Double-tap any slider (audio band or picture) to reset it to zero.
    - A floating label on each continuum always names what the knob is
      on: the stop's name, or the exact custom value ("1.52:1", "1.37×",
      "Pop ↔ Rock").

12. **Safe by design** — the button is greyed out (never hidden) for
    live channels / URLs, same rule as the subtitle button. On
    audio-only files the video parts of the panel are dimmed. Esc closes
    the panel. Nothing here can break normal playback.

---

## 2. The full preset lists (locked)

Bands = 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz. Gains in dB
(−12 … +12; 0 = no change). Values below are the starting curves — final
numbers are tuned by ear during the build.

### Audio file set (13 preset stops + My)

| # | Preset | Label on the line | 31 | 62 | 125 | 250 | 500 | 1k | 2k | 4k | 8k | 16k |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Flat** | Flat | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2 | **Pop** | Pop | +1 | +2 | +3 | +5 | +3 | +1 | −1 | −2 | −1 | 0 |
| 3 | **Rock** | Rock | +5 | +4 | +3 | +1 | −2 | −1 | +2 | +3 | +4 | +5 |
| 4 | **Jazz** | Jazz | +4 | +3 | +1 | 0 | −2 | −2 | 0 | +1 | +2 | +3 |
| 5 | **Classical** | Class | +5 | +4 | +3 | +2 | −2 | −3 | −3 | −1 | +2 | +4 |
| 6 | **Bass Boost** | Bass | +10 | +8 | +6 | +3 | 0 | −1 | −2 | −2 | −1 | 0 |
| 7 | **Treble Boost** | Treb | −1 | −1 | 0 | 0 | +1 | +2 | +4 | +6 | +8 | +10 |
| 8 | **V-Shape** | V-Shape | +8 | +6 | +3 | +1 | −2 | −2 | +1 | +4 | +7 | +9 |
| 9 | **Vocal** | Vocal | −2 | −3 | −4 | −2 | 0 | +3 | +5 | +4 | +2 | 0 |
| 10 | **Lounge** | Lounge | +4 | +3 | +2 | +2 | 0 | −1 | −2 | −3 | −2 | −1 |
| 11 | **Live** | Live | +3 | +2 | +1 | 0 | +2 | +3 | +4 | +5 | +6 | +7 |
| 12 | **Dance** | Dance | +9 | +8 | +5 | +2 | −1 | −1 | +1 | +3 | +5 | +7 |
| 13 | **Phone** | Phone | −6 | −5 | −4 | −3 | −1 | +1 | +2 | +3 | +2 | 0 |
| — | **My** *(mark below the line)* | My | — | — | — | — | — | — | — | — | — | — |

### Video file set (4 preset stops + My)

| # | Preset | Label on the line | 31 | 62 | 125 | 250 | 500 | 1k | 2k | 4k | 8k | 16k |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Flat** | Flat | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2 | **Movie** | Movie | +4 | +3 | +1 | 0 | +1 | +2 | +3 | +4 | +3 | +2 |
| 3 | **Music Video** | Music V | +7 | +5 | +3 | +1 | 0 | +1 | +2 | +4 | +5 | +3 |
| 4 | **Documentary** | Doc | −3 | −3 | −2 | 0 | +1 | +3 | +4 | +3 | +1 | 0 |
| — | **My** *(mark below the line)* | My | — | — | — | — | — | — | — | — | — | — |

"Flat" is also the reset state: if all 10 bands are at 0, the equalizer
filter is removed from the engine completely (nothing extra in the audio
chain).

---

## 3. The continuum — the selection language (LOCKED)

One concept, used four times. A **thin line with labeled stops**:

**The shared behaviour (all four continua):**
- Every preset / look / ratio / speed is a tick **stop with a short
  label** under the line.
- The knob rests **on a stop** (named setting) or **between stops** — a
  blend, where the 10 band curves (or the 5 picture values, or the ratio,
  or the speed) are interpolated between the two neighbouring stops.
- The **floating label** always names the knob: the stop's name, or the
  exact custom value ("1.52:1", "1.37×", "Pop ↔ Rock").
- **Hover** (after ~0.3 s) = live preview on the playing media.
  **Leave** = revert, nothing saved. **Click or drag** = applies;
  **release** = keeps (persisted).
- Releasing within a small distance of a stop **snaps to the named
  stop**.
- Stops are evenly spaced along the line (one exception: speed, which is
  linear in value so 2×→3× feels no coarser than 0.5×→0.75×).

**The four lines:**

| Part | Stops (labels) | Between stops = |
|---|---|---|
| **Audio EQ** | the preset set of the playing file (section 2) | a blended EQ curve |
| **Picture** | Original · Vivid · Night · Faded · Warm · Cool | a blended picture (all 5 values) |
| **Aspect** | Auto · 4:3 · 16:9 · 1.85 · 2.35 · 21:9 · 1:1 · 9:16 | a custom ratio ("1.52:1") — Auto stop = the file's own shape |
| **Speed** | 0.5× · 0.75× · 1× · 1.25× · 1.5× · 2× · 3× (line runs 0.25×–3.0×, linear in value) | any speed ("1.37×") |

**Around the lines (not on them):**
- Audio line: the 10 band sliders below it (fine-tune), the My mark +
  save mark, the curve-on-video mark.
- Picture line: the 5 fine sliders below it (section 4).
- Aspect line: the "Snap window" toggle at the right of its row.
- Speed line: the "Keep pitch" toggle at the right of its row.
- Panel footer: the reset-all mark (point 13).

> The glyph and dial candidates (previewed in `design/eq-preview/`) are
> **dropped** — the labeled continuum is the final selection language for
> all four parts.

---

## 4. Picture — the 5 fine sliders (Saturation · Gamma · Contrast · Brightness · Hue)

Part 2 mirrors Part 1 exactly: **continuum on top, fine sliders below.**

The 5 sliders (each −100 … +100, 0 = neutral) are the **fine-tune layer**:

- **Always live-bound** — they display the current values whether the
  knob is on a look, on a blend, or free.
- **Drag one = custom picture.** The continuum knob moves to the nearest
  look and its label reads "Custom"; dragging the line back takes over
  again. Dragging a slider while a look is "active" simply releases the
  knob.
- **Double-tap any slider = 0.** Hover shows the value chip (the house
  bar language — bars breathe, icons glow).
- **A/B compare for free** — hovering the **Original** stop shows the
  untouched picture; leaving returns your adjusted one. No extra control
  needed.
- **Phase-2 candidate (owner's call, NOT in v1) — live tone histogram:**
  a small luminance histogram drawn behind the Brightness + Gamma
  sliders, computed from the actually-playing frame (mpv's built-in
  screenshot command → downscaled in pure Dart → histogram). You see
  where the content's tones sit and where your adjustment pushes them —
  the camera-scope feel. No new dependency needed (mpv screenshot +
  Flutter's own image decode); it is extra work, so it stays a future
  phase unless the owner pulls it forward.

---

## 5. Auto EQ (owner's idea) — how it works

One switch in Settings: **Auto EQ: On / Off** (default **Off**) — sits
with the Resume and Folder auto-load options.

When ON, the moment a file loads, SALU makes its best guess, in this
order:

1. **Music file with a genre label** (the "Jazz" / "Rock" / "Hip Hop"
   label stored inside the file) → the matching preset.
2. **Video with 5.1 or 7.1 surround sound** → Movie.
3. **Short video + stereo** (under ~20 min) → Music Video.
4. **Long video** (over ~90 min) → Movie; if the name says
   "documentary / interview / lecture" → Documentary.
5. **Name words** ("concert", "podcast", "documentary") → adjust the
   guess.
6. **Nothing matches** → Flat.

**It learns from you.** If Auto picks "Rock" and you tap "Jazz", SALU
remembers "this kind of file → this person likes Jazz" (saved on disk,
per file type + genre). Within a week the picks feel like it knows your
taste.

**The rules that keep it safe:**
- Auto only speaks at file load. A manual tap always wins, instantly.
- Hovering a control never counts as a choice — only a kept click/drag
  teaches the learning map.
- Turning the switch off leaves the current settings exactly as they are.

**The indicator.** When Auto makes its pick, a tiny dot appears beside
the audio line's label (tooltip: "Auto EQ · <preset>"). One pixel of
honesty — you can see the automation working and exactly what it chose.

**Learning map — data policy (bounded, owner-approved):**
- Stored **on-device only** — one JSON blob inside the existing settings
  entry. No network, no privacy surface.
- One entry = key (file type + genre/series) → the kept choice (preset
  name in v1, the full curve in Phase 2) + last-used time. ≈ 100 bytes.
- The key space is naturally small (a user meets dozens of genres and a
  few hundred series over years) — an absolute worst case is ~1,000
  entries ≈ 100 KB. It grows with *kinds of content seen*, never with
  playback count.
- **LRU cap: 500 entries** — beyond that, the least-recently-used entry
  is evicted (every pick/teach already touches the entry, so tracking is
  free).
- **Staleness: entries unused for 90+ days** are pruned at app start —
  taste moves on; stale taste is worthless data.
- **Manual clear:** Settings gets a "Clear EQ memory" row — one tap
  wipes the whole map, with the house **Undo toast** (no confirm
  dialog). Full owner control, always.

**The honest limit (owner-aware):** SALU cannot actually *listen* to the
audio and analyse it — mpv does not hand out the sound data, and adding
that would mean a brand-new native dependency. Auto EQ works from the
file's labels and facts (genre tag, length, sound layout, name). A deeper
"listening" auto-EQ is a future phase, not now.

---

## 6. How it works under the hood (short version)

- All four parts drive **mpv directly, live**:
  - Audio EQ → one mpv filter (`anequalizer`, the verified multi-band
    filter; the old `audio-equalizer` options no longer exist in the mpv
    build that media_kit ships). The same filter can draw its curve on
    the video (the "curve on the video" feature).
  - Picture → mpv's `saturation` / `gamma` / `contrast` / `brightness` /
    `hue` options (range −100…+100, 0 = neutral — verified for this
    build).
  - Aspect → mpv's `video-aspect-override`; it accepts any decimal ratio,
    so the continuum's in-between values ("1.52:1") go straight to the
    engine. The file's *actual* shape (width, height, pixel aspect) is
    read from mpv's video info the moment a file loads — that is what
    "the window is the screen" uses.
  - Speed → mpv's `speed`; pitch stays natural by default (mpv's built-in
    pitch correction); the "Keep pitch" switch turns that off for the
    classic tape-style shift.
- **The continua are pure math in `core/tune_service.dart`** — stop
  positions, blending, snapping and labels are unit-testable Dart with
  zero engine involvement; the engine only ever receives the same single
  property write as before.
- One core service owns all values — the button, the panel and the
  engine can never disagree.
- One settings entry, persisted with `shared_preferences` (+ the Auto EQ
  learning map).
- Unit tests: blend math, snap/label logic, the anequalizer filter-string
  builder, persistence round-trip.

---

## 7. Build order

1. This spec (`eq_imp.md`) + the interactive preview
   (`design/eq-preview/`) — done. Owner locked the labeled continuum for
   all four parts.
2. Core logic: `tune_service.dart` + both preset sets + continuum math
   (blends, snaps, labels) + persistence + unit tests.
3. Button + panel shell + Esc / one-popup wiring.
4. The panel: four labeled continua + 10 band sliders + 5 picture fine
   sliders + My/save + curve-on-video mark + reset-all mark + silent
   keyboard tier (Ctrl+E, Ctrl+↑/↓), one part at a time.
5. Auto EQ: heuristics + learning + the Settings switch + auto-pick
   indicator + the learning-map data policy (LRU cap, 90-day prune,
   "Clear EQ memory" with Undo toast).
6. Polish: slider glide animation, response curve line,
   window-is-the-screen.
7. *(Phase 2 — owner-approved candidates)*
   a) live tone histogram behind the Brightness + Gamma sliders
      (section 4);
   b) **scenes** — one mark moves all four lines together (Cinema:
      window snap + Night look + Movie EQ · Podcast: Vocal EQ + 1× ·
      Vivid: Vivid look + Flat);
   c) **learning that remembers full custom curves** per genre/series
      instead of preset names (the data policy in section 5 already
      bounds it).