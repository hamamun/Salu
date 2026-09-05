# Outline — Transport marks · OSD deck · Volume bar · Resume memory

> **Status:** proposal for review — nothing below is implemented yet.
> Built from the current `main` (`5e88c5e`). The earlier attempt
> (`arena/01a0701b-salu`) was never pushed, so this outline starts clean
> and is cut into steps small enough that each one lands on its own.
>
> Every rule in `follow.md` applies. Items marked **▸ confirm** are the
> only open decisions — each carries a recommendation; silence = go with it.

---

## 0. Where the code stands today (what we build on)

| Area | Today | File |
|---|---|---|
| Chrome block | 40 px title bar + 108 px controller = **148 px**, fused scrim, slide/fade 300 ms, auto-hide 3 s | `home_screen.dart` (`_chromeBlockHeight`, private) |
| Controller rows | Row 1 timeline (48 px box, 23 px bar) · 8 px · Row 2 control row (36 px) | `controller_panel.dart` |
| Row 2 content | left `OpenMediaControl` · center stock `Icons.play_arrow/pause`, stock speaker icons, 120×6 px volume bar with no label | `controller_panel.dart` |
| Player API | `playOrPause / play / pause / seekTo / seekBy / toggleMute / setVolumeUI`; notifiers `position duration volumeLevel isMuted isPlaying hasMedia currentTitle` — **no stop state, no next/previous, no SALU-owned queue (mpv holds the playlist), no current path** | `player_service.dart` |
| Settings | one setting: `titleBarMode` (radio tiles in General → "Controls") | `settings_service.dart`, `settings_dialog.dart` |
| Icon family | plus, film frame, stacked frames, link, solid triangle (URL modal), triangle+tag, pencil, bin, tick, grip | `salu_marks.dart` |
| Icon recipe | `SaluIconButton` (gray→white glide, 1.06 hover, 0.90 press, `enabled:false` dims) | `salu_icon_button.dart` |
| Keyboard | Space, Ctrl+O / Ctrl+F / Ctrl+U — **every key wakes the chrome** | `home_screen.dart` `_onKeyEvent` |
| OSD / resume | nothing exists | — |

Environment note: this sandbox has no Flutter SDK, so I cannot compile
here. Each step below is sized to be reviewed statically and verified by
you with `flutter analyze` + `flutter run -d windows`; every step ends
with a short on-device checklist.

---

## 1. The Control Mark Line (new marks)

One stroke language, one painter for five of them.

| Control | Mark | Construction |
|---|---|---|
| Play | `>` | single chevron, round joins |
| Pause | `II` | two short vertical rules |
| Stop | `□` | hollow rounded square (stroke only) |
| Previous | `\|<<` | bar + double chevron, pointing left |
| Next | `>>\|` | double chevron + bar, pointing right |
| Seek backward | `<<` | double chevron only, left |
| Seek forward | `>>` | double chevron only, right |
| Mute / Unmute | `⊂))` | tiny speaker body + 1–2 arcs · muted = slash, no arcs |
| Restart (toast only) | `↻` | ¾ arc + small arrowhead |

The rules, as you wrote them, fall straight out of the geometry:

- **bar + double chevron** = skip *item* · **double chevron only** = skip
  *time* · **single chevron** = play · **two bars** = pause · **hollow
  square** = stop.
- One `_ChevronPainter(direction, count, bar)` draws `>`, `<<`, `>>`,
  `|<<`, `>>|`. Pause, Stop, Speaker, Restart get their own tiny painters.
- Stroke weight = the family's `_strokeFor(size)`; ink = `IconTheme`
  color, so `SaluIconButton` lights them exactly like the existing marks.
- Speaker arcs follow the level: **1 arc < 50 %**, **2 arcs ≥ 50 %**,
  **slash + no arcs when muted or 0 %** (same thresholds the stock icons
  use today, so behavior doesn't change — only the drawing).
- Optical sizes inside a 34 px hit target: chevrons 20, pause 18,
  **stop 16** (a closed square reads heavier), speaker 20, restart 15.

New file: `lib/ui/widgets/transport_marks.dart` (keeps `salu_marks.dart`
from growing past 1 000 lines; the two private helpers `_strokeFor` /
`_inkOf` become public `markStrokeFor` / `markInk` so both files share them).

**▸ confirm 1 — Play in the Open-URL modal.** The modal's Play / Play &
Save pair relies on *solid vs. hollow* triangle for emphasis; a chevron
cannot be "solid". Recommendation: transport uses the chevron line, the
URL modal keeps its triangle pair. `follow.md` §1.6 gets both listed.

---

## 2. Control row (Row 2) — final layout

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │  [ timeline ────────────────────────────────────────────────────── ]  │  Row 1 (unchanged)
 │                                                                      │
 │  +        |<<   <<    >    >>   >>|      □        ⊂))  [▓▓▓▓62%    ] │  Row 2 (36 px, fixed)
 └──────────────────────────────────────────────────────────────────────┘
   left      ◄──────── transport cluster ────────►    sound group
```

- Pitch inside the cluster: 34 px targets + 6 px gaps. **18 px** before `□`,
  **26 px** before the sound group, 6 px between speaker and bar.
- `>` ↔ `II` swap with the shared motion (fade + 0.96→1.0, 130 ms) — no
  morphing gimmick.
- Disabled states use `SaluIconButton(enabled:false)` (dims, never boxes)
  and follow the **enable matrix** under "Stop — the third state" below:
  with no queue only `+` and the sound group are live; while **stopped**,
  Stop and both Seeks dim but Prev / Next / Play stay on; `>>|` dims
  whenever there is no next item (single file = always dim: honest);
  `|<<` never dims while a queue exists (it can always restart the item).
- Row height stays 36; nothing shifts (hard rule 5).

**▸ confirm 2 — Stop placement.** Right end of the cluster with the wider
gap (keeps `|<< << > >> >>|` symmetric around Play). Alternative: left end.

**▸ confirm 3 — Sound group position.** Stays attached to the center
cluster (current arrangement, minimal change). Alternative: anchor it to
the right edge as a third zone — but the right edge is where the future
tracks / PiP / fullscreen / panel toggles will cluster, so I'd keep it free.

### Behaviors (one place, used by buttons *and* keys)

New `lib/core/transport_actions.dart` — a thin facade so every action is
defined once (player call + OSD card). Buttons, keys, and the video tap
all call it; the timeline and the volume bar keep calling `PlayerService`
directly (bars have their own live readout — no deck for them).

| Action | Player behavior | OSD card (see §4) |
|---|---|---|
| Play / Pause | playing ⇄ paused: `playOrPause()` · **stopped → Play resumes the current item from the stop memory** (see "Stop — the third state") | `>` or `II` · after Stop: the Resume toast instead (§5) |
| Stop | **third state (locked)** — the engine releases the item, the queue stays loaded, SALU remembers the exact position; canvas → initial SALU window | none (the canvas change is the feedback) |
| Previous | one rule in every state: position (stop memory when stopped) > 3 s, or first item → plays *this* item from `0:00`; else plays the previous item | `\|<<` + item title (or `00:00:00` on restart) |
| Next | plays the next item — dimmed when there is none; identical in every state | `>>\|` + item title |
| Seek ± | **seek ramp** (locked — see below): `+5 s`, then `+10 s`, `+15 s`, `+20 s`… while the clicks keep coming; a gap resets to `+5 s`; press-and-hold keeps the sequence firing; `<<` is the exact mirror | `<<` / `>>` + the step just applied + new time — `>>  +15s  01:12:34` |
| Volume ± | `setVolumeUI(level ± 5)` (unmutes) | speaker + bar + `%` |
| Mute | `toggleMute()` | speaker-slash + empty bar + `0%` / restored level |

### Stop — the third state (locked: **Stop ≠ Start Over**)

Transport has three states, not two: **playing · paused · stopped**
(plus *idle* = nothing loaded at all). Stop is neither "pause" nor
"start over" — it is a parked queue.

**Stop does:**
- **Not** clear the queue. Every item stays loaded, the index stays put.
- Release the item in the engine and clear the canvas → the **initial SALU
  window** (logo + wordmark); title bar reads `SALU`, window title `SALU`.
- Reset the timeline to `00:00:00 / 00:00:00`, empty fill, inert. The
  bottom progress hairline disappears (and does not come back while the
  chrome is hidden — there is no progress to draw).
- Remember the exact last position internally (`stopMemory`: path,
  position, duration) *and* flush it to the resume store on disk, so a
  close after a Stop still remembers.
- Keep **Prev / Next / Play** enabled (the queue is still there). **Stop
  and Seek dim** until you play again. **Mute + volume stay enabled.**

**Play again after Stop:**
- Starts from the **last played position**, not `0:00`.
- Shows the short-lived **Resume toast** (§5): play mark · the time you
  resumed at (`12:34`) · the **Restart** action → `0:00` and plays from
  the beginning.
- Same threshold as the disk memory: a stop memory under `5 s`, or inside
  the last `10 s` of the file, or on a live stream (no duration) → Play
  simply starts the item from the beginning with the plain `>` card, no
  toast. One rule for both memories (§5).
- The in-session stop memory is part of the Stop *state* — it applies
  regardless of the Settings → Resume mode. The mode governs what is
  remembered **across** sessions (disk), nothing else.

**Prev / Next while stopped** behave exactly as they do while playing,
one rule in every state: `|<<` → if position (here: the stop memory)
> 3 s or this is the first item → plays *this* item from `0:00`, else
plays the previous item; `>>|` → plays the next item (dimmed when there is
none). An item entered this way follows the normal open path — if the disk
remembers it, it resumes with the toast.

**Enable matrix** (the cluster reads one `TransportState` notifier):

| control | idle (no queue) | stopped | paused | playing |
|---|---|---|---|---|
| `+` open | on | on | on | on |
| `\|<<` previous | off | on | on | on |
| `<<` seek back | off | **off** | on | on |
| `>` / `II` | off | on (`>`) | on (`>`) | on (`II`) |
| `>>` seek forward | off | **off** | on | on |
| `>>\|` next | off | has next | has next | has next |
| `□` stop | off | **off** | on | on |
| speaker + volume bar | on | on | on | on |
| timeline | inert | inert, zeros | live | live |
| bottom hairline | — | hidden | when chrome hidden | when chrome hidden |
| video-canvas tap | — | play (resume) | play | pause |
| `Space` / `S` / `←→` / `PgUp PgDn` | — | play / — / — / prev next | all | all |
| Resume toast on Play | — | yes (stop memory) | — | — |

**Architecture consequence — SALU owns the queue.** media_kit's
`Player.stop()` clears the engine's own playlist, so a queue that survives
Stop has to live above the engine: new `lib/core/queue_service.dart`
(`paths`, `index`, `hasNext`, `hasPrevious`) is the source of truth for
the UI; `PlayerService` still hands mpv the full playlist while playing
(so mpv's native auto-advance and gapless audio stay), mirrors mpv's
index into the queue while an item is loaded, and after a Stop re-opens
the queue at the target index (`Playlist(medias, index:)` with the
current item's `Media(start:)` carrying the stop memory). This is the
same queue the Phase 4 playlist panel and Phase 5 smart queuing will read.

`PlayerService` additions: `stop()`, `next()`, `previous()`,
`playFromStop()`, `stepVolume()`, `currentPath`, `transportState`
(`idle · stopped · paused · playing`), `stopMemory`; `hasMedia` now means
"the engine holds an item" (false after Stop — that is what shows the
landing screen), the new `QueueService` answers "is anything loaded".

Pitfall to verify on device: `Player.stop()` in media_kit 1.2.6 resets its
state object — if the volume stream re-emits `100` after stop, re-apply
`volumeLevel` right after. The stale last frame is already covered (the
`_EmptyState` container is opaque).

Housekeeping that comes with it: the landing screen still carries the
Phase-2 line *"Drop a video or audio file anywhere to start playing"*,
which breaks `follow.md` hard rule 1 (no instruction text). Since Stop now
lands people there routinely, Step B trims it to logo + wordmark.

**▸ confirm 4 — title bar while stopped reads `SALU`** (the literal
"initial window"). Alternative: keep the parked item's name in the title
bar so you can see what Play will resume. *(rec: `SALU` — the toast names
the moment, the title returns the instant you press Play.)*

### Seek behavior (locked)

One tiny state machine — `SeekRamp` in `transport_actions.dart` — shared by
the two buttons, the two arrow keys and (later) anything else that seeks by
a step. Forward and backward are two independent instances, so `>>` then
`<<` never continue each other's ramp.

- **Quick tap:** `+5 s`.
- **Rapid continuous clicks:** `+5 s`, then `+10 s`, `+15 s`, `+20 s`, … —
  step `n` = `n × 5 s`, no ceiling (`seekTo` already clamps at the media
  bounds).
- **Gap between clicks = reset to `+5 s`.** "Gap" = more than **400 ms**
  since the previous fire (`SeekRamp.gap`, one constant to tune on device).
- **Press-and-hold:** the same escalating sequence keeps firing while held —
  first fire on pointer-down (instant response), then a repeat every
  **300 ms** (`SeekRamp.repeat`, shorter than the gap so a hold can never
  reset itself). Each repeat is the next step in the sequence, i.e. holding
  runs `+5 s, +10 s, +15 s, +20 s…` exactly like fast clicking.
- **Seek back is a perfect mirror:** `−5 s, −10 s, −15 s…`, same gap, same
  repeat.
- Keyboard: ← / → go through the same instances; Windows key auto-repeat
  supplies the "hold" (each repeat event = next step; the gap reset applies
  unchanged on release).

Interaction consequences, so no surprises later:
- The buttons need press-and-hold, which `SaluIconButton` (tap-only) does
  not offer. It gains an optional `onHoldRepeat` (raw pointer down/up, a
  `Timer.periodic` while held); the 0.90 press-scale stays down for the
  whole hold — a physical held button. Nothing else about the recipe
  changes.
- The OSD card for a seek always shows the **step just applied** next to
  the new time, so escalation is visible: `>>  +15s  01:12:34`.
- The ramp resets on every *other* transport action (play/pause, stop,
  prev/next, a timeline click), not only on time gaps.

`follow.md` will carry the seek ramp verbatim (§5 container outline) so it
cannot be silently "simplified" to a fixed step later.

### Silent keyboard set (never printed anywhere — hard rule 2)

| Key | Action |
|---|---|
| Space | play / pause — while stopped: play (resumes from the stop memory) |
| ← / → | seek back / forward — the seek ramp above (`5 s, 10 s, 15 s…`; hold the key to keep climbing) |
| ↑ / ↓ | volume +5 / −5 |
| M | mute toggle |
| S | stop (no-op while stopped or idle) |
| Page Up / Page Down | previous / next item |
| Esc | dismiss the Resume toast |
| Ctrl+O / Ctrl+F / Ctrl+U | (existing) open file / folder / URL |

**▸ confirm 5 — transport keys no longer wake the chrome.** Today every key
reveals the chrome; with the deck in place, transport keys show *only* the
OSD (that is the whole point of the "controller hidden" slot). All other
keys keep waking the chrome. One consequence handled: in **Pin (playback
off)** mode, pausing from the keyboard must still pin the chrome — so
`HomeScreen` listens to `transportState` and wakes the chrome whenever it
leaves `playing` (pause *and* stop) in that mode.

---

## 3. Volume bar (redesign)

Extracted to `lib/ui/osc/volume_bar.dart`; same widget is reused read-only
inside the OSD volume card so the two can never drift apart.

- **One thin horizontal bar, timeline family** (locked: horizontal, never
  vertical — it lies in the control row exactly like the timeline lies in
  Row 1, and the fill grows left → right): **140 wide × 14 px tall** (16 px
  on hover — the bar "breathes" inside its fixed 34 px hit box, so nothing
  around it moves), radius 4, `barTrack` / `barFill`, same translucent fill
  as the timeline. The read-only copy inside the OSD volume card is the same
  horizontal bar at 120 × 14.
- **No `0` / `100` endpoints.** The current value sits *inside* the bar:
  `62%`, 10 px, tabular figures, single tone, faint shadow — the timeline's
  label style scaled down.
- **Pinned at the right edge of the filled portion:**
  `labelX = max(pad, fillEnd − labelWidth − pad)` — so it rides the fill's
  end and, when the fill is too short to hold it (incl. muted / `0%`), it
  rests at the left edge. One rule covers every case you listed.
- Quiet at rest (`iconIdle` tone), brightens to `textPrimary` while
  hovering or dragging; the fill brightens one notch too.
- **Hover chip = the timeline's chip**, extracted into a shared
  `HoverChip` widget (`lib/ui/osc/hover_chip.dart`) and used by both
  bars. Semantics match the timeline exactly: chip = value *under the
  cursor*; in-bar number = *current* value (they coincide while dragging).
  The chip floats below the bar, over the video; it never reflows the row.
- Mouse wheel over the bar: ±5 % per notch (mirrors the timeline's ±1 s).
  Drag is horizontal only — pointer x maps to the level; y is ignored.
- Dragging the level rightward out of silence unmutes (existing behavior,
  kept).
- Speaker mark to its left is the Mute control from §1 (arcs track level).

---

## 4. OSD deck — one slot, two "feels"

### Anchor
`osdTop = kChromeBlockHeight + 8 = 156 px`, horizontally centered.
`kChromeBlockHeight` becomes a public constant computed as
`CustomTitleBar.height + ControllerPanel.height` (so it can never drift
from the real block). Subtitles are bottom-anchored (media_kit default) —
no collision possible; the video's visual center is never touched.

```
  y=0   ┌─────────────── title bar ───────────────┐
  y=40  ├────────────── controller ───────────────┤
  y=148 └───────────────┬─────────────┬───────────┘  ← scrim melts out here
  y=156                 │  >  01:12:34 │              ← the deck, both states
                        └─────────────┘
```

- **Controller visible** → reads as a drawer popping down from the block.
- **Controller hidden** → reads as a small system deck at the top center.
- Same anchor, same motion, one mental slot. Because it sits *below* the
  block, a chrome reveal mid-toast never covers it — it just looks like the
  deck was already where the controller pops down. (Hovering the deck does
  wake the chrome, as your caveat describes; that is fine.)

### Motion (identical in both states)
- Enter: fade 0→1 + translateY −10 → 0, **160 ms** ease-out cubic, clipped
  at y = 148 so the top edge never paints over the block.
- Exit: fade + translateY 0 → −6, **120 ms** ease-in cubic.
- Replacing a card while one is up (e.g. repeated volume presses):
  cross-fade content in place, 100 ms, no re-slide — no jitter.

### Material & anatomy
- Glass capsule: `ClipRRect` + `BackdropFilter(blur 18)` + `AppColors.glass`
  + `surfaceOutline` hairline — the Open pill's material, extracted into a
  shared `GlassCapsule` widget. Radius **10** (a deck, not a pill — keeps
  it visually distinct from the Open pill's 21).
- Height 36 (transient) / 40 (Resume toast). Horizontal padding 14.
  Min width 96, max 360 (titles ellipsize).
- Transient cards are `IgnorePointer`; only the Resume toast is interactive.

### Cards

| Card | Content | Lifetime |
|---|---|---|
| Transport | mark 18 px, optionally `+ 12 px gap + text` (time `hh:mm:ss` tabular, or item title) | 1 000 ms, restarted by repeats |
| Volume | speaker mark + the **same `VolumeBar` widget** (read-only, 120 × 14, number inside) | 1 000 ms |
| Resume | `[>]  12:34        [↻ Restart]` — see §5 | 4 000 ms · click-outside · Esc |

Rules:
- One slot — the latest card replaces whatever is up (a transport action
  while the Resume toast shows dismisses the toast; you've started watching
  — except Stop, which dismisses it *and* parks the item where it was).
- Discrete actions (buttons, keys, video tap) flash the deck; **bars never
  do** (timeline & volume bar already show their live chip).
- The deck **never wakes the chrome** and never takes focus.
- Nothing about it is anchored to a widget — it's screen-positioned in
  `HomeScreen`'s stack (`Positioned(top: 156)`), so none of the
  `CompositedTransformFollower` / Tooltip problems from PR #15 can recur.

Files: `lib/ui/osd/osd_controller.dart` (singleton `ValueNotifier<OsdCard?>`
+ `show(card)` / `dismiss()`, sealed `OsdCard` classes, TTL timers) and
`lib/ui/osd/osd_deck.dart` (the widget).

**▸ confirm 6** — Phase 3's separate "center play/pause animation"
(Step 5) is superseded by the deck's `>` / `II` card. I'd not build it.

---

## 5. Resume memory (remember position)

Two memories, one rule, one toast:

| memory | lives | filled by | consumed by | governed by |
|---|---|---|---|---|
| **Stop memory** | in session (`PlayerService.stopMemory`) | `□` Stop | Play / Space / canvas tap while stopped | nothing — part of the Stop state |
| **Disk memory** | `shared_preferences` | every play (throttled) + pause / stop / switch / close | `openPath / openPaths` on any later open | Settings → Resume mode (§6) |

Both use the same keep-threshold (`5 s ≤ position ≤ duration − 10 s`, local
files only) and both surface through the same Resume toast — the user never
sees two systems, just "SALU picks up where I stopped".

### Engine — `lib/core/resume_service.dart`
- Storage: `shared_preferences`, one JSON map under `resume_positions`:
  `{"<absolute path>": [posMs, durMs, updatedEpochMs]}`. Local files only
  (anything with `://` is skipped — live streams have no position to keep).
  Capped at **1 000** entries, oldest pruned (a later "Recent" list can read
  this same map).
- Loaded once at startup (`main.dart`, right after `SettingsService.load()`),
  kept in memory, so lookups at open time are synchronous.
- **Save rule** (the only rule): keep the entry while
  `5 s ≤ position ≤ duration − 10 s`; otherwise **remove** it — a finished
  file starts over next time, and a deliberate jump to `0:00` (Restart,
  `|<<`, timeline) followed by a close also starts over, with no special
  cases.
- **Write cadence**: memory updated on every position tick; disk write
  throttled to every 5 s while playing, and immediately on pause, **Stop**
  (the stop memory is mirrored to disk the moment it is taken), item
  switch, and window close. Window close: `setPreventClose(true)` +
  `onWindowClose → flush → destroy()` (covers the × button and Alt+F4).
  Files shorter than 30 s are never remembered.
- **Gating by mode** (§6): the mode gates *both* saving and resuming, per
  file kind, decided by `MediaUtils.isVideo / isAudio` on the path.

### Resuming without a visible jump
`PlayerService.openPath / openPaths` — and `playFromStop()` — build
`Media(path, start: saved)` —
media_kit's per-item `start` hands mpv the offset before the first frame,
so there is no seek flash. The service remembers which items were given a
`start`; when the playlist stream lands on one of them, the Resume toast
fires with that time. Works identically for the first file, later playlist
items, and drops / pickers / URL dialog (they all go through the same two
methods — no other call sites need changes).

Fallback noted for implementation: if `start` is ignored for some
container, seek once on the first `duration > 0` event for that item.

### The Resume toast
```
[ > ]  12:34                    [ ↻  Restart ]
```
- Left: play chevron 16 px + resumed time (13 px, tabular). Time format is
  compact for the toast: `12:34`, `1:02:34` (no zero-padded hours — nothing
  ticks here, so no wiggle to guard against). Small `formatClockCompact`
  next to `formatClock`, both moved to `lib/core/clock_format.dart`.
- Right: `↻` mark + the word **Restart** — the start-over action — one
  hover target, quiet gray at rest, mark and word light to white together
  (no scale on the word, no box behind anything). Click → `seekTo(0)` +
  `play()` + toast gone. Identical whether the resume came from a Stop or
  from disk.
- Auto-dismiss after 4 s · **click anywhere outside dismisses without
  swallowing the click** (a translucent listener behind the toast, so a
  click on the controller still does its job) · Esc dismisses.
- It does not lock the chrome: if the chrome auto-hides during the 4 s, the
  toast simply becomes the top-center deck — the same slot by design.

**▸ confirm 7 — the word "Restart" joins "Undo" as a toast word-action.**
`follow.md` §1.6 says "no text buttons for actions", yet the URL modal's
delete toast already carries the word **Undo** — toasts are the one place
a bare mark would be ambiguous. Restart follows the same pattern (mark +
word, no box, lights instead of highlights), and `follow.md` gets the rule
written down: *toast actions may carry one word; controls never do.*
**▸ confirm 8** — compact time in the toast (`12:34`) vs. the timeline's
`00:12:34`. **▸ confirm 9** — click-outside does not swallow the click.

---

## 6. Settings → General → new section below "Controls"

Same anatomy as the existing "Controls" section (title · one-line
description · radio tiles with icon chip, label, helper, radio dot,
"Recommended" pill on the default). The existing `_ModeOptionTile` is
generalized to `_OptionTile<T>` so both pickers share one widget.

**Resume** — *Which files continue from where you stopped.*

| Tile | Helper | Value |
|---|---|---|
| **All files** · Recommended | Video and audio pick up where they stopped. | `ResumeMode.all` (default) |
| **Video only** | Video resumes; audio starts from the beginning. | `ResumeMode.videoOnly` |
| **Audio only** | Audio resumes; video starts from the beginning. | `ResumeMode.audioOnly` |
| **Off** | Everything starts from the beginning. | `ResumeMode.off` |

- `SettingsService.resumeMode` (`ValueNotifier<ResumeMode>`), key
  `resume_mode`, default `all`, loaded in `load()`, `setResumeMode()`
  persists instantly — mirrors `titleBarMode` exactly (incl. the
  `values.asNameMap()` lookup from PR #10).
- Switching to Off stops saving *and* resuming but does not wipe stored
  positions (switching back restores your memory).

**▸ confirm 10** — tile icons: stock outline icons like the neighboring
Controls tiles (`Icons.movie_outlined`, `audiotrack_outlined`, …) for
consistency inside the settings window, or SALU marks. I'd match the
neighbor.

---

## 7. Steps (each lands on its own; nothing half-wired at a step boundary)

| # | Step | Touches | Done when |
|---|---|---|---|
| **A** | Transport marks | new `transport_marks.dart`; `salu_marks.dart` (public helpers) | analyzer clean; marks render at 20 px in a scratch row you eyeball once, then the row is deleted |
| **B** | Control row + actions + keys + the three-state transport | new `queue_service.dart`, `player_service.dart` (`transportState`, `stopMemory`, stop / next / previous / playFromStop, `currentPath`), new `transport_actions.dart` (incl. `SeekRamp`), new `transport_cluster.dart`, `salu_icon_button.dart` (`onHoldRepeat`), `controller_panel.dart`, `media_timeline.dart` (inert zeros while stopped), `video_screen.dart` (landing screen loses its instruction line), `home_screen.dart` (keys, canvas tap → facade, hairline hidden while stopped, `transportState` pin rule) | all six marks work with mouse and keys; seek ramp: tap = 5 s, fast clicks / hold climb 5→10→15…, a pause resets, `<<` mirrors; enable matrix correct in all four states; Stop shows the landing screen with the queue intact; Play after Stop resumes at the exact position (toast arrives in F); Prev / Next work while stopped; volume survives Stop |
| **C** | Volume bar | new `volume_bar.dart`, new `hover_chip.dart`, `media_timeline.dart` (uses `HoverChip`), `controller_panel.dart` | number rides the fill edge; `0%` sits left when muted; chip on hover/drag; wheel ±5 % |
| **D** | OSD deck | new `osd_controller.dart`, `osd_deck.dart`, `glass_capsule.dart` (Open pill switched to it), `home_screen.dart` (`kChromeBlockHeight`, deck layer, transport keys stop waking chrome), `transport_actions.dart` (emits cards) | deck pops down under a visible controller and appears at 156 px when hidden, same motion; repeats don't jitter; chrome never wakes from the deck |
| **E** | Resume engine + setting | new `resume_service.dart`, new `clock_format.dart`, `settings_service.dart` (`resumeMode`), `player_service.dart` (`Media(start:)`, tracking, flush hooks), `main.dart` (load + close hook), `settings_dialog.dart` (Resume section, `_OptionTile<T>`) | silent resume works for file / folder / drop / playlist advance; the four modes gate correctly; finished files start over; close flushes |
| **F** | Resume toast | `osd_controller.dart` / `osd_deck.dart` (interactive card), `transport_actions.dart` (Restart), `home_screen.dart` (Esc, click-outside layer) | toast shows the resumed time after a Stop → Play *and* after a fresh open of a remembered file; Restart goes to 0:00 and plays; 4 s / click-outside / Esc all dismiss; toast survives a chrome auto-hide in place |
| **G** | Docs | `follow.md` (§1.6 mark line + Restart exception, new OSD-slot and volume-bar rules, §5 container outline), `phase_3_details.md` (Steps 4/5/6), `phase_5_details.md` (Step 3 → mode picker), `README.md` status | contract matches the code |

Order is by dependency: **A → B → C → D → E → F → G**. B is the largest;
if it feels heavy in review I'll split it into B1 (player + facade + keys)
and B2 (row widgets).

### On-device checklist per step (you run; I can't compile here)
- `flutter analyze` → 0 issues (lints: `prefer_single_quotes`,
  `directives_ordering`).
- A: nothing visible changes. B: click each mark; Space / arrows / M / S /
  PageUp-Down; open a folder and confirm `>>|` enables; tap `>>` once
  (5 s), click it five times fast (5+10+15+20+25 = 75 s total), wait a
  second and tap again (back to 5 s), hold it for 2 s (climbs while held),
  hold → for 2 s (same); `<<` mirrors each of those. Stop: open a folder,
  play the 2nd file to ~1:00, press `□` → landing screen, timeline zeros,
  no hairline, `□ << >>` dim, `|<< > >>|` live; `>>|` → 3rd file plays;
  `|<<` twice → back to the 2nd from `0:00`; play to 1:00, `□`, `>` →
  resumes at ~1:00; `□` then close SALU, reopen the 2nd file → resumes. C: hover, drag,
  wheel, mute. D: press → with the mouse still → deck appears at 156 px
  with the chrome hidden; move the mouse → chrome reveals above it.
  E: watch 1 min, close with ×, reopen → resumes; set Off → starts over.
  F: toast shows, Restart works, Esc / click / 4 s dismiss.

---

## 8. Decisions to confirm (recap — silence = recommendation)

1. Transport Play = chevron; Open-URL modal keeps its triangle pair. *(rec: yes)*
2. Stop sits at the right end of the cluster. *(rec: yes)*
3. Sound group stays attached to the center cluster. *(rec: yes)*
4. Title bar reads `SALU` while stopped (not the parked item's name). *(rec: yes)*
5. Transport keys drive the OSD only and don't wake the chrome. *(rec: yes)*
6. Center play/pause animation superseded by the deck. *(rec: yes)*
7. "Restart" joins "Undo" as a toast-only word-action. *(rec: yes)*
8. Toast time compact (`12:34`). *(rec: yes)*
9. Toast click-outside doesn't swallow the click. *(rec: yes)*
10. Resume tiles use stock outline icons like the Controls tiles. *(rec: yes)*

Locked by owner (no longer open): **volume bar is horizontal**; **seek
ramp** `5 s → 10 s → 15 s…`, gap resets, hold keeps climbing, back mirrors;
**Stop ≠ Start Over** — Stop parks the queue (canvas → initial window,
timeline zeros, hairline gone, Stop + Seek dim, Prev / Next / Play / sound
live), Play resumes at the exact position with the Resume toast, and its
Restart action is the only way Stop ever becomes "start over".
