# SALU — lrc.md (Lyrics, audio display & visualizer decisions & implementation contract)

> **Purpose:** The single decision log for everything audio-lyrics related in
> SALU — the `.lrc` sidecar file, the audio display (metadata + album art),
> the mpv audio visualizer, and the toggles that drive them. Every decision
> the owner locks in chat lands here first, then in code. `follow.md` (hard
> rules) and `cc.md` (subtitle contract) still bind everything below — this
> file only adds the lyrics/audio-display layer, and it never touches the
> video subtitle pipeline.
>
> **Status:** DECISIONS LOCKED L1–L28 (owner 2026-09-14). **NOT YET
> IMPLEMENTED** — this is the contract the implementation will be built
> against. `cc.md` remains the authority for subtitles; lyrics and the audio
> display are a separate, audio-only feature by design (see §1 — lyrics are
> NOT subtitles).

---

## 0. The one principle that governs everything here

**Lyrics are not subtitles, and audio is not video.** Subtitles belong to
video and render through mpv's libass (`cc.md` D16). Lyrics belong to audio,
render as a Flutter overlay, and never flow through the subtitle pipeline.
A `.lrc` file is **parsed directly** — it is never converted to SRT, never
added to `MediaUtils.subtitleExtensions`, and never appears in the video
track panel. This one rule keeps the two worlds from ever mixing.

The audio canvas has **three possible renders, one at a time** (never mixed,
never layered on top of each other):
- **mpv video** → the audio visualizer (mode B),
- **Flutter** → metadata + album art (mode C),
- **Flutter** → lyrics (mode A).

Which one shows is decided by §2's precedence table.

---

## 0.5 Reconfirmed decisions — the full index (L1–L28)

One line per locked decision, for at-a-glance reconfirmation. Each maps to
the section where it is explained in full.

| # | Decision (one line) | § |
|---|---|---|
| L1 | Lyrics are audio-only, local-only, sidecar `.lrc` only, no online fetch | 1 |
| L2 | Mode C shows album art + title/artist/album | 3 |
| L3→L21 | Tag reader is for **cover-art bytes only**; text comes from mpv | 3 |
| L4 | Text fallback to file name; never blank | 3 |
| L5 | Missing art → SALU-logo placeholder (generated look) | 3 |
| L6 | External `cover.jpg`/`folder.jpg` is a later phase | 3 |
| L7→L25 | `.lrc` is its own category; `.lyr` dropped | 5 |
| L8 | Parse `.lrc` directly, never convert to SRT | 5 |
| L9→L24 | Parse quirks; `[offset:]` is APPLIED | 5 |
| L10→L23 | Basename match; exact `song.lrc` beats `song.<lang>.lrc` | 5 |
| L10a | Discovery is sibling-based, not selection-based | 5 |
| L11 | Lyrics render full-window, karaoke highlight | 6 |
| L12→L20 | Sync offset reuse needs a Dart bridge (`subDelay`) | 6 |
| L13 | Fetch button → lyrics toggle on audio | 7 |
| L14 | Lyrics default OFF + dot badge (available ∧ off) | 8 |
| L15 | Three-mode precedence: lyrics > visualizer > metadata | 2 |
| L16→L22 | Visualizer is mpv's; `lavfi-complex` is primary | 4 |
| L17 | Visualizer = Settings toggle, default OFF, audio-only | 4 |
| L18 | Visualizer is disabled, not covered, by lyrics | 4 |
| L19 | `audio-display=no` — Flutter owns the audio canvas | 2 |
| L20 | (merged — see L12) | 6 |
| L21 | (merged — see L3) | 3 |
| L22 | (merged — see L16) | 4 |
| L23 | (merged — see L10) | 5 |
| L24 | (merged — see L9) | 5 |
| L25 | (merged — see L7) | 5 |
| L26 | Mode/lyric/metadata/visualizer re-evaluates every landing | 5 |
| L27 | Cover-art bytes cached by canonical path | 3 |
| L28 | Lyric lines are clickable → seek to that timestamp | 6 |

---

## 1. Scope — what lyrics means in SALU (L1)

1. **Audio only.** Lyrics exist only for local audio files (`.mp3`,
   `.flac`, `.m4a`, `.aac`, `.ogg`, `.opus`, `.wav`, … — `MediaUtils.isAudio`).
   Video never gets lyrics; it keeps subtitles.

2. **Local only.** Lyrics are read from a sidecar `.lrc` sitting next to
   the audio file, by basename match. They arrive through the existing local
   open paths (Open File… and drag & drop), which already funnel through the
   same open flow and are already fenced off from channel/stream mode by the
   `isChannelList` checks. Nothing here widens that.

3. **No online lyrics fetching.** The OpenSubtitles downloader in
   `subtitle_service.dart` stays video-only and is untouched. Lyrics are
   never fetched from the network in v1.

4. **Sidecar `.lrc` only (v1).** Embedded lyrics (ID3 `USLT`/`SYLT`, MP4
   `©lyr`) are noted as a later phase and out of scope now.

---

## 2. The audio display — three modes & precedence (L15)

Today audio plays through the same `Video` widget as video, which renders a
dark backdrop with nothing on it (`video_screen.dart`). There is no branch
for audio. This section replaces that empty backdrop with **one of three
mutually-exclusive modes**, decided by two independent switches (the lyrics
toggle, §7, and the visualizer toggle, §4):

| Lyrics | Visualizer | What shows on the audio canvas |
|---|---|---|
| **ON**  | any | **Lyrics only — full window** (no art, no metadata, no visualizer) |
| OFF | **ON**  | **Visualizer only — full canvas** (no art, no metadata) |
| OFF | OFF | **Metadata + album art** (§3) |

1. **L15 — precedence rule.** Lyrics win over everything; then visualizer;
   then metadata + album art as the fallback. The three modes are exclusive —
   exactly one renders at a time. This is the single authority the audio view
   reads; nothing else in the file may imply a different combination.

2. **Video is untouched** by all of this: video keeps the plain mpv canvas
   and subtitles, exactly as today.

3. **L19 — Flutter owns the audio canvas; mpv is turned off for it.** The
   "black window" for audio is only true for *artless* audio: mpv's default
   `audio-display=attached-picture` already renders **embedded cover art as
   the video stream**, so art-bearing audio shows a raw cover through the
   `Video` widget today. To stop that raw cover colliding with SALU's styled
   album art (mode C), SALU sets **`audio-display=no`** for audio. mpv then
   produces NO video for audio — except when the visualizer (mode B) is on,
   where the visualizer itself is the video. Flutter draws everything else
   (art + text + lyrics). This is the one rule that makes the three modes
   exclusive in practice, not just in the table.

---

## 3. Mode C — metadata + album art (the fallback, both toggles off) (L2–L6, L21, L27)

Shown only when the lyrics toggle is OFF **and** the visualizer toggle is
OFF. **Nothing in the project reads tags or album art yet** (no
metadata/cover dependency in `pubspec.yaml`, no tag-reading code); this
section is net-new work.

1. **L2 — the metadata + album art view.** When this mode is active, the
   canvas shows album art (large, centered), then title / artist / album
   underneath. It is not shown when lyrics or the visualizer are on.

2. **L3 / L21 — the tag reader is for art bytes ONLY; text comes from mpv.**
   Embedded album art bytes (ID3 `APIC`, FLAC `METADATA_BLOCK_PICTURE`, MP4
   `covr`) must be read by a metadata/tag package so the exact bytes can feed
   a Flutter `Image` — mpv renders art as video frames and does not hand the
   bytes to Dart, so a tag reader is required for the image. **But title /
   artist / album need no tag reader**: SALU already has
   `platform.getProperty(...)` plumbing, and mpv exposes `metadata` /
   `metadata/by-key/title` / `/artist` / `/album`. So the one new dependency
   has a single, narrow job — cover-art bytes — and the text is read from mpv
   for free.

3. **L4 — metadata text fallback.** Show title → artist → album from mpv
   metadata; when a field is empty, fall back to the file name
   (`MediaUtils.displayName`) and never leave the panel blank.

4. **L5 — missing-art placeholder (SALU-generated image).** Not every track
   has embedded art. Show a **SALU-branded generated image** — the SALU logo
   (`assets/images/salu_logo.png`, the same mark the landing canvas uses) as
   the placeholder, on the dark backdrop, never a broken or empty box. A
   dedicated generated audio placeholder image can replace the bare logo later
   if a distinct "no art" look is wanted, but the logo is the v1 placeholder.

5. **L6 — external art is a later phase.** `cover.jpg` / `folder.jpg` beside
   the file is a nice-to-have; skip for v1, embedded art first.

6. **L27 — cover-art bytes are cached by canonical path.** Reading art on
   every landing is wasteful on fast zapping; cache decoded art per
   `MediaUtils.canonicalPath`, invalidated when a file changes.

**Layout (SALU's design language — `app_theme.dart`):** centered vertical
stack — album art (rounded, faint `surfaceOutline` ring, soft shadow, roughly
`min(55–60% of height, width-limited)`), then Title (`#EDEDED`, ~22–24px
semibold), Artist (`#9A9A9A`, ~16px), Album (dimmer, ~14px). No icons, no new
colors — text + thin marks only, consistent with the rest of the app.

---

## 4. Mode B — the mpv visualizer (L16–L18, L22)

1. **L16 / L22 — the visualizer is mpv's, not Flutter's — `lavfi-complex` is
   the primary path.** mpv synthesizes the visualization into its own video
   output — the same canvas SALU's `Video` widget already renders — so no new
   Flutter drawing is needed. Two ways exist:
   - **`--lavfi-complex`** with ffmpeg filters (`showfreqs` = bars,
     `showspectrum`, `showcqt`, `showwaves`, `avectorscope`) — **this is the
     primary, guaranteed path**: `media_kit_libs_windows_video` ships a full
     libmpv with ffmpeg filters compiled in, so it always works and offers
     full control.
   - the built-in `--audio-visualizer` option (mpv 0.36+; `showfreqs` /
     `showspectrum`) — noted only as a possible simplification **if** the
     bundled libmpv is confirmed ≥ 0.36; otherwise ignore it.

   SALU already sets mpv properties via `platform.setProperty(...)` (used for
   `track-list`, `sub-delay`, `hwdec-current`, `keep-open`), so wiring
   `lavfi-complex` is the same one-line pattern.

   **Styling** is plain color, driven to SALU's palette (monochrome or the
   `#4C9EEB` accent on the `#121212` backdrop) — the "bar type / plain
   color / elegant" look the owner asked for. No spectrum-style color themes.

2. **L17 — a Settings toggle, default OFF.** `Visualizer` lives in Settings
   as a simple on/off. OFF by default (no cost until asked). **Audio-only**:
   it applies to local audio files and never to video or channel/stream mode
   (consistent with §1). It is not a per-file state — one global toggle.

3. **L18 — the visualizer is disabled, not merely covered.** When the lyrics
   toggle turns ON over an active visualizer, the visualizer must be
   **actually stopped** (unset `lavfi-complex` / `audio-visualizer`), not
   hidden behind an opaque overlay — mpv would otherwise keep generating
   frames nobody sees and burn CPU/GPU. "Lyrics fully replace the visualizer"
   means the engine stops producing it while lyrics are shown, and resumes
   when lyrics turn OFF (if the visualizer toggle is still ON).

---

## 5. The lyrics file — `.lrc` support (L7–L10a, L23–L26)

1. **L7 / L25 — `.lrc` is its own category — `.lrc` ONLY (drop `.lyr`).** Add
   a lyrics extension set (`.lrc`) to `MediaUtils` as a **separate**
   `isLyrics`/`lyricExtensions` concept — NOT into `subtitleExtensions`. This
   is the concrete line that keeps lyrics out of the subtitle world. **`.lyr`
   is dropped for v1**: it is a *different* karaoke format, not another LRC
   spelling, and including it invites format confusion. One format, `.lrc`,
   only.

2. **L8 — parse `.lrc` directly, never convert.** The format is trivial
   (`[mm:ss.xx] text` per line). SALU parses it itself; there is no
   SRT round-trip and no reliance on mpv's own LRC support (which is
   version-dependent — 0.35+ — and anyway renders into a video frame audio
   does not have).

3. **L9 / L24 — real-world LRC quirks.** The parser must handle:
   - multiple timestamps on one line (`[00:10.00][00:20.00] line`),
   - enhanced LRC word timing (`<00:10.00>` inline tags) — degrade gracefully,
   - header tags (`[ti:]`, `[ar:]`, `[al:]`, `[by:]`, `[offset:]`),
   - blank lines and lines without timestamps.
   **The `[offset:]` header is APPLIED, not ignored** — it is the file
   author's declared correction, so it shifts every timestamp by its value
   (positive or negative) before lines are timed.

4. **L10 / L23 — basename match, audio only, with a fixed precedence.**
   `song.lrc` (and, as a convenience, `song.<lang>.lrc`) next to `song.mp3`
   is the lyric for that track. When more than one candidate exists, the pick
   order is fixed: **exact `song.lrc` first**, then any `song.<lang>.lrc`
   (first found in natural order). Never ambiguous, never random.

5. **L10a — discovery is sibling-based, not selection-based.** SALU never
   "opens" the `.lrc` — it **discovers** it. The moment a local audio file
   lands in the player, SALU looks in that audio's own folder for the
   matching basename, **regardless of how the audio got there** (Open File…,
   Open Folder…, or drag & drop). The `.lrc` is never queued, never played,
   and never a drop target of its own in v1.

   - **Open File… / Open Folder… with a `.lrc` present** → auto-discovered:
     the folder scan (`DropHandler.scanFolderForMedia`) collects *media
     files only*, so the `.lrc` is not selected or queued — it is simply
     found sitting next to the audio when that audio lands.
   - **Drag only the audio file** → identical result: SALU plays `song.mp3`
     and finds `song.lrc` in the same folder. Dragging the audio alone loses
     nothing, because the sidecar lives next to the audio, not in the drop.
   - **Dropping a `.lrc` directly onto the window** (e.g. onto a playing
     song) is a possible later convenience but **out of scope for v1** —
     sibling discovery already covers the normal workflow.

6. **L26 — the lyric lookup re-runs on EVERY landing.** Mode + lyric
   discovery + metadata + visualizer state must re-evaluate on every
   `start-file` / playlist advance, not just the first open — exactly the
   trigger `SubtitleService.onMediaLanded` already uses. A zapped-to track
   must never inherit the previous track's lyric, art, or mode.

---

## 6. How lyrics show (L11–L12, L20, L28)

1. **L11 — full-window Flutter overlay, karaoke style.** When lyrics are
   ON, they are the **only** thing on the audio canvas — no album art, no
   metadata, no visualizer. Centered in the window, the **current line is
   highlighted** with a line or two of context above/below. Audio has no
   video frame, so this is the one place Flutter rendering is correct —
   video keeps mpv/libass, audio keeps this overlay, and the two never meet.

2. **L12 / L20 — sync offset reuse needs a bridge.** The existing
   subtitle-sync mechanism (`sub-delay`, the Z/X keys,
   `player_service.dart`'s sync authority) is reused so a viewer can nudge a
   drifting lyric into sync. **But `sub-delay` only shifts mpv-rendered
   subtitles — it will NOT move Flutter-rendered lyrics on its own.** The
   lyric line-lookup must therefore read `PlayerService.subDelay` and add it
   to the playback position before selecting the current line. This bridge is
   what actually makes the Z/X keys work for lyrics; without it the sync
   feature silently does nothing.

3. **L28 — lyric lines are clickable.** Each rendered lyric line is a tap
   target; clicking it seeks playback to that line's timestamp (applied to
   mpv via the existing `PlayerService.seekTo`). Only a real seek — no OSD
   card, no panel; the jump is the feedback, matching the track-switch rule
   (cc.md §6.6 "no OSD on switch"). The current-line highlight and the tap
   target are independent: a line may be clicked whether or not it is the
   active one.

---

## 7. The lyrics toggle — the subtitle (Fetch) button becomes the lyric switch (L13)

The control row's Fetch button (`fetch_control.dart`) currently opens the
track panel and is greyed out for audio (its enabled check literally requires
`MediaUtils.isVideo`). Its job changes by media kind:

1. **Video** → unchanged: opens the track panel (`Tracks` tooltip).

2. **Audio with lyrics available** → becomes a **lyrics on/off toggle**
   (`Lyrics` tooltip), and the enabled check grows to `isVideo || (isAudio &&
   lyricAvailable)`.

3. **Audio with no lyrics** → stays greyed out and inert, exactly as today.

4. The tooltip must switch between `Tracks` (video) and `Lyrics` (audio) or
   the button will read as broken.

---

## 8. Default state + the dot badge (L14)

1. **Lyrics default OFF.** Showing lyrics is always opt-in per the toggle.

2. **Dot badge = "lyrics available and currently off."** The badge appears
   on the button when a lyric exists but is not being shown. It disappears
   when the user toggles lyrics ON, and **returns** when they toggle OFF
   again. So: badge present ⟺ (lyric available ∧ not shown); badge absent ⟺
   (no lyric) ∨ (lyric currently shown).

3. **One global default, not per-file memory (v1).** A simple
   "lyrics default on/off" is less surprising than remembering per song;
   per-file memory can come later if it is ever wanted.

4. **The visualizer has no badge.** It is a Settings toggle (§4 L17), not a
   control-row button, so it carries no dot — the two switches are
   deliberately different shapes.

---

## 9. Implementation checklist (the order of work)

1. **MediaUtils** — add `lyricExtensions` (`.lrc` only — L25) + `isLyrics()`.
2. **Tag reader dependency** — add the metadata package for **cover-art bytes
   only** (L21); title/artist/album come from mpv `metadata`.
3. **Lyrics service** — new `lyric_service.dart`: sibling lookup by basename
   (L10/L23 precedence), `.lrc` parsing (L9/L24 incl. `[offset:]`),
   current-line lookup against `position + subDelay` (L20), a `ValueNotifier`
   for (available, shown, current line), and per-line timestamp lookup for
   click-to-seek (L28).
4. **Audio display branch** — a mode switch in `video_screen.dart` (or a
   sibling widget) implementing §2's three-mode precedence table, with
   `audio-display=no` for audio (L19).
5. **Metadata + album art view** — mode C (L2–L6, L21, L27) + SALU-logo
   placeholder.
6. **Visualizer** — mode B (L16–L18, L22): mpv `lavfi-complex` wiring,
   monochrome/accent palette, stop-when-covered.
7. **Lyrics overlay** — mode A, full-window karaoke text driven by the lyrics
   service (L11), honoring the toggle, with click-to-seek (L28).
8. **Fetch button** — repurpose per §7 (L13) with the `Lyrics` tooltip and
   the enabled-condition change.
9. **Badge** — the dot on the button per §8 (L14).
10. **Visualizer settings toggle** — the on/off switch per §4 (L17), default
    OFF, persisted like the other settings.
11. **Sync bridge** — the lyric lookup applies `subDelay` itself (L20), so
    Z/X moves the Flutter-rendered lines.
12. **Re-evaluate on landing** — hook the mode/lyric/metadata/visualizer
    re-run to the same start-file trigger `onMediaLanded` uses (L26).
13. **Drop/open wiring** — verify both Open File… and drag & drop reach the
    lyric lookup with no extra work (they share the local open path; see
    L10a — discovery is sibling-based, so no selection plumbing is needed).

---

## 10. Out of scope / later phases (noted, not built)

- Embedded lyrics (ID3 `USLT`/`SYLT`, MP4 `©lyr`).
- External art (`cover.jpg` / `folder.jpg`).
- Online lyrics fetching (provider integration).
- Per-file lyrics toggle memory.
- Word-level (enhanced LRC) highlighting beyond graceful degradation.
- Dropping a `.lrc` file directly onto the window (sibling discovery covers it).
- Visualizer color-theme presets beyond the monochrome/accent default.
