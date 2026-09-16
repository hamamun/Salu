# MINI BAR MODE

**Status:** ✅ FINAL (v5) — locked. Next step: implement against this doc.
**Scope:** UI-only shell over the existing engine. Nothing here touches mpv,
queue, resume memory, channel logic, or any service.

---

## 1 · Concept

Mini means **mini**. Salu's full window collapses into a single floating
strip with the height of a Windows title bar. It carries the complete
transport, the track title, and a seek line — and nothing else. A video
file opened in mini mode behaves like audio: it plays, but nothing is
shown.

---

## 2 · Window contract

| Rule | Decision |
|---|---|
| Height | **32 px** — the Windows caption height (DPI-aware, scales with the monitor) |
| Width | Fixed. Whatever the items need (~488 px in this design); measured once, then locked |
| Resize | **None.** `minSize = maxSize`. No drag edges, no maximize, ever |
| Caption buttons | **None.** No Close, no Minimize, no Maximize. Taskbar/Alt+F4 still work |
| Always-on-top | **ON** for the whole mini session. That's the point of the bar |
| Native chrome | Stays off (Salu is already borderless) |
| Position | Fully draggable. Remembered per-mode, restored on relaunch, clamped inside the visible screen (multi-monitor + DPI safe) |

---

## 3 · Layout (left → right)

Salu's own sequence is preserved — mini uses the exact transport order of
the full window.

```
             ← 2 px progress line along the TOP edge, full width →
┌────────────────────────────────────────────────────────────────┐
│ [S] │ > ‖ □ │ |<< >>| │ << >> │ ⊂)) (◔) │ Track title — artist… │ ⤢ │
└────────────────────────────────────────────────────────────────┘
                           (◔) = volume wheel — thin ring dial
```

1. **SALU icon** — one job beyond identity: it's the **drag handle**.
2. **Transport — Salu group order, unchanged, and the SAME marks:**
   - Group 1 · playback: **Play/Pause · Stop**
   - Group 2 · items: **Previous · Next**
   - Group 3 · seeks: **Seek backward · Seek forward** (hold-to-climb keeps working)
   - **Identical glyphs, one source of truth.** Mini renders the very same
     `transport_marks.dart` painters (single chevron = play, two rules =
     pause, hollow rounded square = stop, `|<<` / `>>|` = items,
     `<<` / `>>` = seeks) at 18 px with the same `markStrokeFor` stroke.
     No mini-specific redraws, ever.
   - **Identical hover recipe** (`SaluIconButton`, **26×30 px hit** in mini
     vs 34□ in full): the mark itself glides `iconIdle → textPrimary` in
     ~120 ms with a 1.06 scale (0.90 pressed). **Never a background box.**
   - Group pitch is a compressed echo of the full cluster, same rhythm
     (~1 : 2.2 : 3.7): in-group **5**, between-groups **11**,
     before-sound **20** (full mode: 6 / 14 / 26). Rule of the trim:
     shrink the space, never the glyphs — floor is 26 px hits,
     5 px in-group gaps.
   - Same dim rules as full mode (Stop dims idle, Prev/Next dim at queue/group
     edges, seeks dim when stopped).
   - Group 4 · sound: **speaker glyph + volume wheel**, 5 px apart. The
     speaker follows volume exactly like full mode: 1 arc below 50 %,
     2 arcs at 50 %+, slash when muted/0.
     The **wheel is a thin ring dial** (20 px, same stroke family as the
     marks): a dim track ring, a level arc filling clockwise from
     12 o'clock, and a tiny tick at the head of the arc. **Wheel ±5 %
     only** (rolling over the speaker or the ring both work) — no
     click/drag, and no number printed on the dial: the exact value
     rides the title swap (§6).
3. **Track title** — full width of what remains, ellipsis truncation. Channel mode shows the **channel name**.
4. **Restore button** — icon-only glyph in its own slot at the far right. Exits mini mode. This is the bar's only "caption" control.

**No tooltips in mini.** The bar is 32 px tall — a hover popup cannot fit
inside a window that tall, it renders cut off — so the bar drops every
tooltip: transport buttons, seek line, volume wheel, title. Full mode
keeps its hover-delay tooltips; in the bar the marks speak for themselves
and the title swap (§6) stays the only feedback.

**Group spacing** reads from pitch alone — mini's compressed 5 / 11 / 20
keeps the same visual law as the full cluster (6 / 14 / 26).

**Edge meter.** One edge, one dial: **position rides the TOP edge** — a
2 px strip along the top edge of the bar (`#80FFFFFF` fill on `#35353C`
track), full width. Click and drag to jump; the invisible hit zone is
~10 px tall hanging from the top.

**Dragging** — the icon *and* all dead space (group gaps, title area)
drag the bar. Controls never drag.

---

## 4 · Enter / exit

**Enter mini:**
- Toggle glyph in the full-mode title strip, placed **immediately left of
  the Settings glyph**.
- Keyboard: `M`.

On entering: **save the full window's geometry** (position, size,
maximized state) *before* shrinking to the fixed mini rect.

**Exit mini — three ways:**
1. **Restore button** (primary, always visible).
2. Double-click any dead space.
3. `Esc`.

On exiting: restore the saved full geometry **exactly**.

---

## 5 · Runtime behavior

- **Video plays as audio.** No video surface, no subtitles, no lyrics, no
  album art. mpv keeps running; the video widget simply isn't mounted.
- **Queue unaffected.** Next/Previous walk the queue; in channel mode they
  follow the channel list with the existing group-dim rules.
- **Files opened from Explorer** while in mini (single-instance routing)
  play instantly and the window **stays in mini**.
- **Drag & drop stays.** Dropping file(s) or a folder onto the bar follows
  the exact rules of full mode.
- **Hotkeys stay live** while the bar has focus (space, arrows, seek keys).
- **Stop parks the queue** exactly as in full mode.
- Resume memory, EQ/tune state, and per-file subtitle offsets keep working
  silently underneath.
- **Closing while in mini** (taskbar, Alt+F4) → next launch opens **in
  mini mode**, at the last mini position. The full-mode geometry is
  remembered separately and comes back on the next restore.

---

## 6 · Feedback within the no-toast rule

The OSD deck does not exist in mini. One feedback channel replaces it:
the **title area swaps** to the transient message for ~1.2 s, then fades
back to the real title.

| Event | Swap text |
|---|---|
| Volume wheel | `Volume 45 %` |
| Mute toggle | `Muted` / `Volume 45 %` |
| Seek buttons | `+15 s · 01:12:34` |
| Stop | `Stopped — queue parked` |
| Prev/Next | next track / channel name |
| Line click | `→ 01:23 · 02:19 left` |

Subtle, same size, same color family — never a card, never an overlay.

---

## 7 · Idle appearance — ALWAYS ALIVE (decision)

The mini bar **never fades, never sleeps, never collapses**. You put it
where you want it; it stays exactly as you left it, fully alive, for as
long as mini mode is on. If the user wants it gone, the answer is the
mode itself (restore / close), not a half-hidden state.

Every pixel of the bar is persistent — nothing reveals, hides, or
repositions inside it or around it during a mini session.

Alternatives evaluated in the preview and rejected: *hairline collapse*
(folds into the progress line; hides controls the user asked to always
have) and *ghost fade* (controls dim but the strip still claims 32 px).
Both lived in earlier preview versions; git history holds them.

---

## 8 · Explicitly OUT of mini

Hard bans — if it's on this list it does not exist in mini mode:

- ❌ Close / Minimize / Maximize buttons
- ❌ Video surface of any kind
- ❌ OSD toasts and cards
- ❌ Lyrics, album art, subtitle rendering
- ❌ Playlist, Fetch, EQ/tune, Settings panels
- ❌ Window resize or maximize
- ❌ OS chrome of any kind

---

## 9 · Implementation notes

- One owner: a `WindowMode { full, mini }` flag, persisted by
  `window_state_service` next to existing window state.
- `window_manager` on enter: `setAlwaysOnTop(true)` →
  `setMinimumSize(miniSize)` + `setMaximumSize(miniSize)` →
  `setSize(miniSize)` → move to last mini point. Reverse the lock on exit.
- `HomeScreen`'s root swaps to a new `MiniShell` widget when in mini;
  the rest of the tree (panels, video view) is simply not built.
- Reuse existing pieces: mark painters from `transport_marks.dart`
  **imported unchanged** (mini draws with them at 18 px via the same
  `markStrokeFor` helper), `SaluIconButton` with a **26×30 hit** for the
  identical hover recipe, dim states from the transport cluster, the
  SALU glyph for the handle. Group pitch constants are mini's own
  (5 / 11 / 20); do NOT import the cluster's 6 / 14 / 26.
- Mini does not reuse `VolumeBar`; it gets a new tiny `VolumeWheel`
  painter (track ring + level arc + head tick, drawn with the same
  `markStrokeFor` weight). Both it and the speaker feed
  `PlayerService.stepVolume`.
- **The mini window never resizes during a session.** Size changes happen
  only on enter (full rect → mini rect) and exit (mini rect → full rect).
  No dynamic growth-overlays of any kind.
- New code only: the shell, `MiniProgressStrip` painter (top edge) + hit
  zone, the title-swap controller.
- The full-mode toggle lives in `custom_title_bar.dart`, one glyph left
  of Settings — thin Segoe-style mark, same family as caption buttons.
- Persist **both** geometries independently (full rect + mini point),
  logical-pixel aware.

---

## 10 · Acceptance checklist

- [ ] Bar is 32 px tall, fixed width, refuses resize and maximize
- [ ] **Always alive**: never fades, sleeps, or collapses in any state
- [ ] Controls are the exact full-mode marks & hover recipe (no mini variants,
      no hover boxes); dim rules identical
- [ ] Mini rhythm compressed but familiar: 26×30 hits, pitch 5 / 11 / 20,
      glyphs 18 px unchanged; bar ≈ 488 px, title keeps ~141 px
- [ ] All seven transport controls behave exactly as full mode
- [ ] Progress line on the TOP edge, click/drag seeks, hit zone ≥ 8 px
- [ ] Volume wheel sits in the row right after the speaker — thin ring
      dial, level arc + head tick, wheel ±5 % only; value via title swap
- [ ] Title truncates with "…"; no tooltips anywhere in the bar (32 px
      has no room for a popup); channel name in IPTV
- [ ] Restore button, double-click dead space, and `Esc` all exit mini
- [ ] Full geometry restored exactly on exit; both geometries persisted
- [ ] Always-on-top the entire mini session
- [ ] Drag works from icon + dead space; controls never drag
- [ ] Title-swap is the only feedback; zero toasts appear
- [ ] Video files play as audio; drop/hotkeys/single-instance verified
- [ ] Matches `design/mini-bar-preview/index.html`

---

## 11 · Change log

**v3 — preview feedback pass (this session)**
- **Previous mark corrected** — the preview's Previous glyph carried its
  bar at the wrong end. Fixed to the exact mirror of Next (`|<<`,
  bar rides the pointing edge), matching `transport_marks.dart`.
- **Volume reveal lip abandoned.** Trials in the preview proved the lip
  "couldn't be caught": the gap between the bar and the lip broke hover
  before the pointer arrived (classic dropdown death-roll). The volume
  bar moves back **in the row, directly after the mute button**, as in
  full mode — wheel-only ±5 %, no click/drag, no hover chip.
- **Bottom-edge micro volume sliver removed** — redundant now that the
  bar is visible in the row.
- **Window no longer grows for volume.** The mini window is completely
  static during a session; the only size changes are enter/exit mini.
  Bar width ~515 → **~620 px** to host the in-row bar.
- Edge-meter language simplified: **position alone rides the top edge**;
  volume returned to the row.

**v4 — "wheel means wheel"**
- The 96 px in-row volume **bar** is replaced by a literal **volume
  wheel**: a thin 20 px ring dial (track ring + level arc filling from
  12 o'clock + head tick), 6 px after the speaker. Wheel ±5 % only; the
  number is not printed on the dial — it rides the title swap and the
  tooltip. Bar width ~620 → **~543 px**.

**v5 — final padding compression (doc locked after this pass)**
- Rule of the trim: **shrink the space, never the glyphs.** Button hits
  30 → **26 px wide** (height stays 30); group pitch 6/14/26 →
  **5/11/20** (same ~1:2.2:3.7 rhythm as the full cluster); icon gap
  11 → 8, outer padding 5 → 4, title left margin 10 → 8.
- Glyphs stay **18 px**, the wheel stays **22 px**, and the **title
  keeps its full ~141 px** — every saved pixel came from chrome,
  never content.
- Bar width ~543 → **~488 px**. Hard floor recorded: no hits below
  26 px, no in-group gap below 5 px.
- Mini's pitch constants are now officially its own (§9 updated); full
  mode keeps 6 / 14 / 26 untouched.
- Cleanups: §7 reference to the (removed) preview console corrected.
