# Outline — Transport marks · OSD deck · Volume bar · Resume memory

> **Status:** FINAL & IMPLEMENTED (2026-09-05). This is the binding spec
> for the transport cluster, OSD deck, volume bar and resume memory.
> Every decision below is locked; the decision record is §8.
> Built on `main` (`5e88c5e`). Every rule in `follow.md` applies.

---

## 0. Baseline (what the code builds on)

| Area | Fact | File |
|---|---|---|
| Chrome block | 40 px title bar + 108 px controller = **148 px** (`kChromeBlockHeight`), fused scrim, slide/fade 300 ms, auto-hide 3 s | `home_screen.dart`, `controller_panel.dart` |
| Controller rows | Row 1 timeline (48 px box, 23 px bar) · 8 px · Row 2 control row (36 px) | `controller_panel.dart` |
| Player API | `playOrPause / play / pause / seekTo / seekBy / toggleMute / setVolumeUI` + notifiers | `player_service.dart` |
| Icon recipe | `SaluIconButton` (gray→white glide, 1.06 hover, 0.90 press, dims when disabled) | `salu_icon_button.dart` |
| Keyboard | Space, Ctrl+O / Ctrl+F / Ctrl+U — today every key wakes the chrome | `home_screen.dart` |

---

## 1. The control mark line (new marks)

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
| Mute / Unmute | `⊂))` | tiny speaker body + arcs · **1 arc < 50 %, 2 arcs ≥ 50 %, slash + no arcs at 0 / muted** |
| Restart (toast only) | `↻` | ¾ arc + small arrowhead |

- bar + double chevron = skip *item* · double chevron only = skip *time* ·
  single chevron = play · two bars = pause · hollow square = stop.
- One `_ChevronPainter(direction, count, bar)` draws `>`, `<<`, `>>`, `|<<`,
  `>>|`; Pause, Stop, Speaker, Restart have their own painters.
- Stroke = `markStrokeFor(size)`; ink = `IconTheme` color (the shared
  helpers of `salu_marks.dart`, public). Optical sizes inside a 34 px hit
  target: chevrons 20, pause 18, stop 16, speaker 20, restart 15.
- Home: `lib/ui/widgets/transport_marks.dart`.
- The Open-URL modal keeps its solid/hollow **triangle** pair (Play /
  Play & Save); transport uses the chevron line. Both listed in
  `follow.md` §1.6.

---

## 2. Control row (Row 2) — final layout

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │  [ timeline ────────────────────────────────────────────────────── ]  │  Row 1 (unchanged)
 │                                                                      │
 │  +     >    □    |<<    >>|    <<    >>      ⊂))  [▓▓▓▓62%    ]      │  Row 2 (36 px, fixed)
 └──────────────────────────────────────────────────────────────────────┘
   left   ◄──────────── transport cluster ───────────►    sound group
```

- Order after `+`: **Play/Pause · Stop · Previous · Next · Seek backward ·
  Seek forward**, then the sound group (speaker + volume bar), attached to
  the cluster; the row's right edge stays free for future controls.
- Pitch is the grouping: **6 px inside a group, 14 px between groups,
  26 px before the sound group**, 6 px between speaker and bar. Nothing
  is ever drawn around a group or an icon (`follow.md` §2 stands).
- Every control is a `SaluIconButton`: gray at rest, glide to white +
  1.06× hover (~120 ms), 0.90× press (seek marks hold 0.90 for the whole
  hold), disabled dims — never boxed. Hover-delay tooltips name controls.
- `>` ↔ `II` swap with the shared motion (fade + 0.96→1.0, 130 ms).
- Row height stays 36; nothing shifts (hard rule 5).

### Behaviors — `lib/core/transport_actions.dart`

One facade; buttons, keys and the video tap all call it. Bars call
`PlayerService` directly (they have their own live readout).

| Action | Player behavior | OSD card (§4) |
|---|---|---|
| Play / Pause | playing ⇄ paused · **stopped → resumes from the stop memory** | `>` / `II` · after Stop: the Resume toast |
| Stop | third state — engine releases the item, queue stays, position remembered; canvas → initial window | none (canvas change is the feedback) |
| Previous | one rule in every state: position (stop memory while stopped) > 3 s, or first item → plays *this* item from `0:00`; else previous item | `\|<<` + title (or `00:00:00` on restart) |
| Next | plays the next item — dimmed when there is none | `>>\|` + title |
| Seek ± | **seek ramp** (below) | `<<` / `>>` + the step just applied + new time |
| Volume ± | `setVolumeUI(level ± 5)` (unmutes) | volume card |
| Mute | `toggleMute()` | mute / unmute card |

### Stop — the third state (Stop ≠ Start Over)

Transport has four states: **idle · stopped · paused · playing**.

**Stop does:** keep the queue loaded (index stays) · release the item and
clear the canvas → the **initial SALU window** (logo + wordmark; title bar
and window title read `SALU` — never the parked item's name) · zero the
timeline (`00:00:00 / 00:00:00`, inert) · hide the bottom progress
hairline · remember the exact position in the session stop memory **and**
flush it to the resume store on disk · keep Prev / Next / Play / sound
live; Stop and both Seeks dim.

**Play after Stop:** starts from the last played position and shows the
Resume toast (§5). Threshold (one rule for both memories): a position
under 5 s, inside the last 10 s of the file, or on a live stream (no
duration) → start from `0:00` with the plain `>` card, no toast.

**Enable matrix** (the cluster reads one `TransportState` notifier):

| control | idle | stopped | paused | playing |
|---|---|---|---|---|
| `+` open | on | on | on | on |
| `>` / `II` | off | on (`>`) | on (`>`) | on (`II`) |
| `□` stop | off | **off** | on | on |
| `\|<<` previous | off | on | on | on |
| `>>\|` next | off | has next | has next | has next |
| `<<` seek back | off | **off** | on | on |
| `>>` seek forward | off | **off** | on | on |
| speaker + volume bar | on | on | on | on |
| timeline | inert | inert, zeros | live | live |
| bottom hairline | — | hidden | when chrome hidden | when chrome hidden |
| video-canvas tap | — | play (resume) | play | pause |
| Space / S / ←→ / PgUp PgDn | — | play / — / — / prev next | all | all |

**SALU owns the queue.** `lib/core/queue_service.dart` (`paths`, `index`,
`hasNext`, `hasPrevious`) is the source of truth; `PlayerService` hands
mpv the full playlist while playing (native auto-advance and gapless stay)
and mirrors mpv's index into the queue; after a Stop it re-opens the queue
at the target index with the stop memory as `Media(start:)`.

`PlayerService`: `stop()`, `next()`, `previous()`, `playFromStop()`,
`stepVolume()`, `currentPath`, `transportState`, `stopMemory`. `hasMedia`
means "the engine holds an item" (false after Stop — that is what shows
the landing canvas); `QueueService` answers "is anything loaded".

Landing canvas = logo + wordmark only — no instruction line (hard
rule 1).

### Seek behavior — `SeekRamp`

Shared by the two buttons, the arrow keys and anything else that seeks by
a step. Forward and backward are independent instances.

- Quick tap: `±5 s`.
- Rapid clicks: `5 s, 10 s, 15 s, 20 s…` — step *n* = *n* × 5 s, no
  ceiling (`seekTo` clamps at the media bounds).
- A gap > **400 ms** since the previous fire resets to 5 s.
- Press-and-hold: first fire on pointer-down, then every **300 ms**, each
  the next step — a hold climbs exactly like fast clicking. Arrow keys:
  OS auto-repeat supplies the hold.
- Backward is the perfect mirror.
- The OSD card shows the step just applied next to the new time:
  `>>  +15s  01:12:34`.
- Every other transport action (and a timeline click) resets both ramps.
- `SaluIconButton` gains `onHoldRepeat` for this; the 0.90 press-scale
  stays down for the whole hold. Nothing else about the recipe changes.

### Silent keyboard set (never printed — hard rule 2)

| Key | Action |
|---|---|
| Space | play / pause — while stopped: resume from the stop memory |
| ← / → | seek back / forward via the ramp (hold to climb) |
| ↑ / ↓ | volume +5 / −5 |
| M | mute toggle |
| S | stop (no-op while stopped or idle) |
| Page Up / Page Down | previous / next item |
| Esc | dismiss the Resume toast |
| Ctrl+O / Ctrl+F / Ctrl+U | open file / folder / URL (existing) |

Transport keys drive the **OSD only** and never wake the chrome. One
exception: in **Pin (playback off)** mode a pause or stop still pins the
chrome (`HomeScreen` watches `transportState`). All other keys keep
waking the chrome.

---

## 3. Volume bar — `lib/ui/osc/volume_bar.dart`

Same widget reused read-only inside the OSD volume card.

- One thin **horizontal** bar, timeline family: **140 × 14 px** (16 px on
  hover — it breathes inside its fixed 34 px hit box), radius 4,
  `barTrack` / `barFill`, same translucent fill as the timeline. The
  read-only OSD copy is 120 × 14.
- No endpoint numerals. The value sits *inside* the bar — `62%`, 10 px,
  tabular figures, single tone, faint shadow — pinned at the right edge
  of the fill: `labelX = max(pad, fillEnd − labelWidth − pad)`; when the
  fill is too short (muted / 0 %) it rests at the left edge.
- Quiet at rest (`iconIdle` tone), brightens to `textPrimary` while
  hovering or dragging; the fill brightens one notch too.
- Hover chip = the timeline's chip (`lib/ui/osc/hover_chip.dart`, shared).
  Chip = value under the cursor; in-bar number = current value.
- Wheel over the bar: ±5 % per notch. Drag is horizontal only. Dragging
  rightward out of silence unmutes (kept).
- Speaker mark to its left is the Mute control (arcs track the level).

---

## 4. OSD deck — one slot, two "feels"

- Anchor: `osdTop = kChromeBlockHeight + 8 = 156 px`, horizontally
  centered. `kChromeBlockHeight` is a public constant computed as
  `CustomTitleBar.height + ControllerPanel.height`.
- Controller visible → reads as a drawer popping down from the block;
  hidden → a small system deck at top center. Same anchor, same motion.
  A chrome reveal mid-toast never covers it.
- Motion: enter fade 0→1 + translateY −10→0, **160 ms** ease-out cubic,
  clipped at y = 148; exit fade + 0→−6, **120 ms** ease-in. Replacing a
  card cross-fades in place, 100 ms, no re-slide.
- Material: glass capsule (`lib/ui/widgets/glass_capsule.dart`,
  `ClipRRect` + `BackdropFilter(blur 18)` + `AppColors.glass` +
  `surfaceOutline` hairline — the Open pill's material, shared). Radius
  10 (a deck, not a pill). Height 36 transient / 40 toast. Padding 14.
  Min width 96, max 360 (titles ellipsize).
- Transient cards are `IgnorePointer`; only the Resume toast is
  interactive. The deck never wakes the chrome and never takes focus.

| Card | Content | Lifetime |
|---|---|---|
| Transport | mark 18 px + optional text (time `hh:mm:ss` tabular, or item title) | 1 000 ms, restarted by repeats |
| Volume | speaker mark + the same `VolumeBar` (read-only, 120 × 14) | 1 000 ms |
| Resume | `[>]  12:34        [↻ Restart]` — §5 | 4 000 ms · click-outside · Esc |

- One slot — the latest card replaces whatever is up; a transport action
  while the toast shows dismisses the toast (except Stop, which dismisses
  it *and* parks the item where it was).
- Discrete actions (buttons, keys, video tap) flash the deck; bars never
  do.

Files: `lib/ui/osd/osd_controller.dart` (singleton notifier + TTL),
`lib/ui/osd/osd_deck.dart` (the widget).

---

## 5. Resume memory

Two memories, one rule, one toast:

| memory | lives | filled by | consumed by | governed by |
|---|---|---|---|---|
| **Stop memory** | session (`PlayerService.stopMemory`) | `□` Stop | Play / Space / canvas tap while stopped | nothing — part of the Stop state |
| **Disk memory** | `shared_preferences` | every play (throttled) + pause / stop / switch / close | `openPath / openPaths` on any later open | Settings → Resume mode (§6) |

Both keep an entry only while `5 s ≤ position ≤ duration − 10 s` (local
files only; files shorter than 30 s are never remembered), and both
surface through the same Resume toast.

### Engine — `lib/core/resume_service.dart`

- Storage: one JSON map under `resume_positions`:
  `{path: [posMs, durMs, updatedEpochMs]}`. Capped at 1 000 entries,
  oldest pruned. Loaded once at startup, synchronous lookups afterwards.
- Save rule: keep while inside the window, otherwise **remove** — a
  finished file (or a deliberate jump to `0:00` followed by a close)
  starts over next time. No special cases.
- Write cadence: memory on every position tick; disk throttled to 5 s
  while playing, immediate on pause, Stop, item switch and window close
  (`setPreventClose(true)` + close hook → flush → `destroy()`).
- The mode gates both saving and resuming, per file kind
  (`MediaUtils.isVideo / isAudio`).

### Resuming without a visible jump

`openPath / openPaths / playFromStop` build `Media(path, start: saved)`;
the service tracks which items were given a `start`, and when the
playlist stream lands on one, the Resume toast fires with that time.
Fallback: if `start` is ignored for a container, seek once on the first
`duration > 0` event for that item.

### The Resume toast

```
[ > ]  12:34                    [ ↻  Restart ]
```

- Left: play chevron 16 px + compact time (`12:34`, `1:02:34` — no
  zero-padded hours), 13 px tabular. `formatClockCompact` lives beside
  `formatClock` in `lib/core/clock_format.dart`.
- Right: `↻` + the word **Restart** (toast actions may carry one word;
  controls never do) — one hover target, quiet gray, mark and word light
  to white together, no box. Click → `seekTo(0)` + `play()` + toast gone.
- Auto-dismiss 4 s · click-outside = **dismiss only** (never triggers
  Restart, never swallows the click — the click still does its job
  underneath) · Esc dismisses.
- It does not lock the chrome: if the chrome auto-hides during the 4 s,
  the toast simply becomes the top-center deck.

---

## 6. Settings → General → "Resume" section (below "Controls")

Same anatomy as Controls; `_OptionTile<T>` shared by both pickers.

**Resume** — *Which files continue from where you stopped.*

| Tile | Helper | Value |
|---|---|---|
| **All files** · Recommended | Video and audio pick up where they stopped. | `ResumeMode.all` (default) |
| **Video only** | Video resumes; audio starts from the beginning. | `ResumeMode.videoOnly` |
| **Audio only** | Audio resumes; video starts from the beginning. | `ResumeMode.audioOnly` |
| **Off** | Everything starts from the beginning. | `ResumeMode.off` |

- `SettingsService.resumeMode` (key `resume_mode`, default `all`),
  persisted instantly — mirrors `titleBarMode`.
- Switching to Off stops saving *and* resuming but does not wipe stored
  positions.
- Tiles use stock outline icons, matching the Controls tiles.

---

## 7. Steps (all implemented)

| # | Step | Touches |
|---|---|---|
| **A** | Transport marks | `transport_marks.dart`; `salu_marks.dart` (public `markStrokeFor` / `markInk`) |
| **B** | Control row + actions + keys + three-state transport | `queue_service.dart`, `player_service.dart`, `transport_actions.dart`, `transport_cluster.dart`, `salu_icon_button.dart` (`onHoldRepeat`), `controller_panel.dart`, `media_timeline.dart`, `video_screen.dart`, `home_screen.dart` |
| **C** | Volume bar | `volume_bar.dart`, `hover_chip.dart`, `media_timeline.dart`, `controller_panel.dart` |
| **D** | OSD deck | `osd_controller.dart`, `osd_deck.dart`, `glass_capsule.dart` (+ Open pill switched to it), `home_screen.dart`, `transport_actions.dart` |
| **E** | Resume engine + setting | `resume_service.dart`, `clock_format.dart`, `settings_service.dart`, `player_service.dart`, `main.dart`, `settings_dialog.dart` |
| **F** | Resume toast | `osd_controller.dart` / `osd_deck.dart`, `transport_actions.dart`, `home_screen.dart` |
| **G** | Docs | `follow.md`, `phase_3_details.md`, `phase_5_details.md`, `README.md` |

On-device verification (no Flutter SDK in the authoring sandbox):
`flutter analyze` → 0 issues, then the checklist — marks with mouse and
keys; seek ramp tap / fast-click / hold / mirror; enable matrix in all
four states; Stop → landing canvas, queue intact, Play resumes at the
exact position; Prev / Next while stopped; volume survives Stop; volume
bar hover / drag / wheel / mute; deck appears at 156 px with chrome
hidden and never wakes it; resume after close; four modes gate; finished
files start over; toast 4 s / click-outside / Esc; Restart → `0:00`.

---

## 8. Decision record (all locked, 2026-09-05)

1. Transport Play = chevron; Open-URL modal keeps its triangle pair.
2. Row order: `+ > □ |<< >>| << >>` + sound group; seek pair **backward
   first**.
3. Sound group attached to the center cluster; right edge stays free.
4. Title bar reads `SALU` while stopped — never the parked item's name.
5. Transport keys drive the OSD only; never wake the chrome (Pin-mode
   pause/stop still pins).
6. Phase 3's center play/pause animation is superseded by the deck card
   — not built.
7. "Restart" joins "Undo" as toast-only word-actions.
8. Toast time is compact (`12:34`).
9. Click-outside = dismiss only — never triggers the toast action, never
   swallows the click.
10. Resume tiles use stock outline icons.
11. Grouping = pitch only (6 / 14 / 26 px) — no hover boxes, `follow.md`
    §2 untouched.
12. Volume bar horizontal; value inside the bar; hover chip shared with
    the timeline.
13. Seek ramp `5 s → 10 s → 15 s…` (400 ms gap, 300 ms hold repeat);
    backward mirrors.
14. Stop ≠ Start Over: Stop parks the queue; Play resumes at the exact
    position; Restart (toast) is the only way Stop becomes "start over".
15. Landing/stopped canvas = logo + wordmark, no instruction line.
