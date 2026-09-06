# Playlist control & slide-out panel — implementation brief

> **Status:** DECIDED, **NOT IMPLEMENTED** (2026-09-06, revised the same day:
> the panel's four-tab strip is **removed** and replaced by a five-mark header
> row — repeat · shuffle · search · clear · undock — see §4.4 and §4.9). This is
> the binding
> spec for SALU's playlist control and its slide-out panel. Placement, mark
> and state semantics were chosen by the owner in the interactive study
> `design/playlist-mark-preview/index.html` (serve it with
> `python3 -m http.server 8123 --bind 0.0.0.0 --directory design/playlist-mark-preview`).
> Written on branch `arena/01a07168-salu`, base `47b0d90`.
> **Read `follow.md` first — every hard rule applies.** Where this brief
> fills a gap the owner did not decide, the entry is marked *(default)* and
> may be vetoed; nothing else is open.

---

## 0. Baseline (what the code already gives you)

| Area | Fact | File |
|---|---|---|
| Chrome block | 40 px title bar + 108 px controller = **148 px** (`kChromeBlockHeight`) | `home_screen.dart`, `controller_panel.dart` |
| Control row | Row 2, **36 px** tall, container padding `LTRB(18, 4, 18, 12)`, `Stack` with `Align(centerLeft)` = Open control and `Center` = transport cluster | `controller_panel.dart` |
| Pitch grammar | **6 px** inside a group · **14 px** between groups · **26 px** before the sound group — never a box, never a divider | `transport_cluster.dart` |
| Icon recipe | `SaluIconButton` — gray→white glide 120 ms, hover 1.06×, press 0.90×, `active:` = full white + faint static glow, `enabled: false` = dim, tooltip names the control | `salu_icon_button.dart` |
| Mark family | hand-drawn painters, `markInk(context)` + `markStrokeFor(size)` = `clamp(size × 0.085, 1.4, 2.2)` px, round caps/joins, quiet parts at `ink.withAlpha(140)` | `salu_marks.dart`, `transport_marks.dart` |
| Queue truth | `QueueService.instance` — `paths` (`ValueNotifier<List<String>>`), `index`, `hasQueue`, `hasCurrent`, `hasNext`, `setQueue`, `setIndex`, `clear`. Survives Stop (Stop parks the queue) | `queue_service.dart` |
| Engine | `PlayerService.instance` — `openPath`, `openPaths`, **`_openQueueAt(index, {play, start})` is private**, `previous()`, `next()`, `stop()`, `playFromStop()`, `stopMemory`, `transportState`, `position`, `duration`, `currentTitle`, `currentPath` | `player_service.dart` |
| Transport verbs | `TransportActions.instance` — play/pause, stop, previous, next, seek ramp, volume, mute, restart | `transport_actions.dart` |
| Chrome lock | `ChromeLock.instance.acquire()/release()` — reference counted, keeps the top chrome awake | `ui_lock.dart` |
| Glass material | `GlassCapsule` — blur 18, `AppColors.glass`, `surfaceOutline` hairline, radius param (21 pill / 10 deck) | `glass_capsule.dart` |
| Popup precedent | Overlay-portal pill anchored below its button, Esc closes, click-outside closes, focus restored to `_focusBefore`, 130 ms fade + 0.96→1.0 | `open_media_control.dart` |
| Keyboard | `home_screen.dart::_onKeyEvent` — Space, ←→, ↑↓, M, S, PgUp/PgDn, Esc; Ctrl+O / Ctrl+F / Ctrl+U at line ~306 | `home_screen.dart` |
| Queue surgery API | media_kit `Player`: `add(Media)`, `remove(int index)`, `move(int from, int to)`, `jump(int index)`, `open(Playlist(medias, index:))` — all real in the pinned `media_kit ^1.1.11` | pub.dev |
| Playlist files | `.m3u` / `.m3u8` are already accepted by **Open File** (`MediaUtils.isPlaylist`) — the new control is a *view*, never an open verb | `media_utils.dart`, `open_media_service.dart` |

---

## 1. Locked decisions (owner's picks, 2026-09-06)

| # | Decision | Locked value |
|---|---|---|
| 1 | **Placement** | Left zone of Row 2, **immediately right of the Open `+`** (preview option **B**). The row's right edge stays reserved for tracks · PiP · fullscreen. |
| 2 | **Mark** | **Now Row** — three ragged rules; the row that is playing carries the family's solid play chevron at its head. |
| 3 | **State channel** | **Position in thirds** — the chevron's row = `floor(index / count × 3)`, clamped 0…2. No chevron at all when the queue is empty. |
| 4 | **Panel top** | **Below the chrome block**: `top: kChromeBlockHeight` (148 px), sliding from the **right** edge. Never full height — a full-height panel covers its own toggle. |

### 1.1 Pitch between `+` and the playlist mark — *(default, one-line veto)*

The preview's option B rendered the two marks **2 px** apart, which is the
*pill's internal* pitch (`SizedBox(width: 2)` in `_PillBody`) — the strongest
possible "these are siblings" signal, and it makes the playlist mark read as a
fourth Open action ("load an .m3u"). This brief locks **6 px** = SALU's
in-group pitch: same placement, weaker sibling read. To fuse them visually
instead, change the one `SizedBox(width: 6)` in §7 step 2 to `2`. Nothing else
in this spec moves.

### 1.2 Consequences of the left placement — now requirements

- **R1 · The mark must not look like an Open sibling.** It may never use a
  film frame, stacked frames, link or plus. Now Row satisfies this.
- **R2 · The pill still anchors to the `+` box** (`top = plus bottom + 6`,
  `left = plus left`), unchanged. It is 128 px wide and will extend *under*
  the playlist mark. Accepted — but while the pill is open its full-screen
  dismiss layer swallows the first click anywhere, so **clicking the playlist
  mark with the pill open closes the pill and does not toggle the panel.**
  That is intended popup behaviour; do not "fix" it.
- **R3 · The panel opens far from its toggle** (~500 px at 1000 px wide).
  The only "it is open over there" signals are the mark's active glow and the
  panel's own 220 ms slide. Therefore the glow is **mandatory**, not optional.
- **R4 · Now Row's chevron is defused by distance.** The whole transport
  cluster sits between it and the sound group, so the "second `>` in the row"
  collision does not bite. Hard constraint that keeps this true: **Now Row
  must never be used inside the transport cluster, inside the Open pill, or
  anywhere within a group of transport marks.**

---

## 2. The mark — `NowRowMark`

Lives in `lib/ui/widgets/salu_marks.dart` with the rest of the family, using
`markInk` / `markStrokeFor`. All geometry is a fraction of the mark box.

| Element | Geometry (fractions of the box) | Ink |
|---|---|---|
| Three rules | `y = 0.28 · 0.52 · 0.76`, each from `x = 0.16` to `x = 0.86 · 0.68 · 0.78` | quiet `withAlpha(140)` |
| Chevron head (playing row only) | `M(0.16, y−0.08) L(0.30, y) L(0.16, y+0.08) Z` — **filled and stroked** with the family weight + round joins (exactly `PlayMark`'s point-softening trick) | full |
| Playing row's rule | from `x = 0.38` to that row's end (`0.86 / 0.68 / 0.78`) | full |
| Empty queue | three quiet rules, **no chevron** | quiet |

- Sizes: **20 px** in the control row (36 px button) · **18 px** if it is ever
  reused as a panel tab. Stroke comes from `markStrokeFor`, so 1.7 px at 20.
- **Raggedness is load-bearing.** Three *equal* rules = `≡` = the drag handle
  (hard rule 6). If a future tweak equalises the lengths, the mark becomes
  illegal. Keep `0.86 / 0.68 / 0.78`.
- Air between strokes at 20 px is ~3.1 px — three rules is the ceiling for
  this box, not a preference. Do not add a fourth.

### 2.1 Painter sketch

```dart
/// Playlist — three ragged rules; the row that is playing carries the
/// family's solid chevron at its head. The chevron's row reports position
/// in thirds (playlist_imp.md §2). Never used near the transport cluster.
class NowRowMark extends StatelessWidget {
  const NowRowMark({super.key, this.size = 20, this.now = 0});

  final double size;

  /// 0…2 = the row carrying the chevron; `-1` = nothing queued.
  final int now;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _NowRowPainter(markInk(context), markStrokeFor(size), now),
      );
}

class _NowRowPainter extends CustomPainter {
  const _NowRowPainter(this.ink, this.stroke, this.now);

  final Color ink;
  final double stroke;
  final int now;

  static const List<double> _ys = <double>[0.28, 0.52, 0.76];
  static const List<double> _ends = <double>[0.86, 0.68, 0.78];

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    final Paint quiet = Paint()
      ..color = ink.withAlpha(140)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final Paint line = Paint()
      ..color = ink
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final Paint fill = Paint()
      ..color = ink
      ..style = PaintingStyle.fill;
    final Paint round = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < _ys.length; i++) {
      if (i == now) continue; // the playing row is drawn last, full ink
      final double y = h * _ys[i];
      canvas.drawLine(Offset(w * 0.16, y), Offset(w * _ends[i], y), quiet);
    }
    if (now < 0) return; // empty queue — no chevron, nothing full-ink

    final double y = h * _ys[now];
    final Path head = Path()
      ..moveTo(w * 0.16, y - h * 0.08)
      ..lineTo(w * 0.30, y)
      ..lineTo(w * 0.16, y + h * 0.08)
      ..close();
    canvas.drawPath(head, fill);
    canvas.drawPath(head, round); // softens the points, as PlayMark does
    canvas.drawLine(Offset(w * 0.38, y), Offset(w * _ends[now], y), line);
  }

  @override
  bool shouldRepaint(_NowRowPainter old) =>
      old.ink != ink || old.stroke != stroke || old.now != now;
}
```

### 2.2 Where `now` comes from

```dart
/// Playlist row that carries the chevron: position in thirds, -1 when the
/// queue is empty (playlist_imp.md §1, decision 3).
int playlistRowOf(int index, int count) => count <= 0 || index < 0
    ? -1
    : (index * 3 ~/ count).clamp(0, 2);
```

`count = 5`: rows `0,0,1,1,2` · `count = 3`: rows `0,1,2` · `count = 1`: row `0`.
Put the helper next to `QueueService` (or as a getter on it) so the control and
the panel can never disagree.

- Rebuild from `Listenable.merge([QueueService.instance.paths, .index])`.
- The chevron jumps between rows with **no animation** — it changes only when
  playback crosses a third, which is rare. If it ever reads as jumpy, cross-fade
  130 ms per follow.md §3; do not slide it.
- *(default)* The mark reports **position**, so the open state must not add a
  second glyph change: **open = `active: true` glow only** (follow.md §2 already
  reserves the glow for exactly this). No rotation, no mirroring, no retraction.

---

## 3. The control — `lib/ui/osc/playlist_control.dart`

```dart
SaluIconButton(
  // Names the control, never teaches (rule 1). Follows state exactly like
  // the sound mark's `'Unmute' / 'Mute'`:
  tooltip: PanelService.instance.playlistOpen.value ? 'Hide playlist' : 'Playlist',
  size: 36,
  active: PanelService.instance.playlistOpen.value,
  enabled: true,                       // ALWAYS — see 3.1
  onTap: PanelService.instance.togglePlaylist,
  child: NowRowMark(size: 20, now: playlistRowOf(queue.index.value, queue.paths.value.length)),
)
```

**3.1 Always enabled — *(default)*.** It never dims, even with an empty queue.
Dimming would hide the panel from anyone who has not queued anything yet, and
the empty panel is not a dead end (it carries the append control, §4.4).
Precedent for dimming (`Stop`, `Next`) applies to *transport verbs with nothing
to act on*; a view toggle is not a verb.

**3.2 State ownership — new `lib/core/panel_service.dart`.**

```dart
class PanelService {
  static final PanelService instance = PanelService._();
  final ValueNotifier<bool> playlistOpen = ValueNotifier<bool>(false);
  void togglePlaylist() => playlistOpen.value = !playlistOpen.value;
  void closePlaylist() => playlistOpen.value = false;
}
```

App-level (not widget-level) so the keyboard, the mark and the panel all read
one notifier, exactly as `QueueService` does for the queue.

---

## 4. The panel — `lib/ui/panels/playlist_panel.dart`

**4.0 The click — choreography, frame by frame**

One `AnimationController` (220 ms) driving `forward()` / `reverse()`, exactly as
`open_media_control.dart` does, so a mid-flight toggle **reverses** instead of
restarting. The control is a toggle, never a launcher: clicking it while the
panel is open closes it.

| t | What happens |
|---|---|
| **0 ms** · pointer down | The mark sinks to **0.90×** instantly. No ripple, no splash, no shape behind it (rule 4, `NoSplash` stays global). |
| **~100 ms** · pointer up | The mark springs back to 1.0× over 120 ms ease-out, **and in the same frame**: `playlistOpen = true` → `active:` flips, so the color glides to `textPrimary` and the **faint static glow** appears (the row's only glow — §1.2 R3 makes it load-bearing). |
| **same frame** | The panel enters: `translateX(322 → 0)` **plus** opacity `0 → 1`, **220 ms**, `Curves.easeOutCubic`. Slide + fade, **no scale** — `0.96 → 1.0` belongs to point-anchored popups; an edge-anchored panel already "grows from its anchor direction" (§3) by sliding. |
| **same frame** | **Nothing moves that must not move**: the video keeps its size and scale, the chrome block does not shift, the timeline stays Row 1 (rule 5). The panel is glass *over* the picture — see 4.1. |
| **~220 ms** · settled | Rows are laid out and the list is scrolled so the playing row is on screen (4.3). **No OSD card flashes** — the deck is transport/volume only. |
| **never** | The click does not start playback, does not touch the queue, does not take focus, does not acquire `ChromeLock`, does not open a modal. |
| **+3 s** | The chrome auto-hides as usual (§4.6) and the panel stays, anchored at y = 148, hanging over the video where the chrome was. |

**Closing** (mark again · Esc · Ctrl+L) runs the reverse: `translateX(0 → 322)` +
fade out, 220 ms `Curves.easeInCubic` (the pill's `reverseCurve`), glow off via
the same 120 ms color glide back to `iconIdle`. The panel stops hit-testing the
instant it starts closing (`IgnorePointer`), so a closing sheet can never eat a
click meant for the video.

**If the `+` pill is open**, the first click anywhere — including on this mark —
only closes the pill (§1.2 R2). The second click opens the panel. Intended.

**4.1 Geometry & material**

- `Positioned(top: kChromeBlockHeight, right: 0, bottom: 0, width: 322)`
  (Phase 4 allows 300–350; 322 matches the study).
- Material: `AppColors.glass` + `BackdropFilter(blur 18)` + a `surfaceOutline`
  hairline on the **left** edge only; top-left radius 14, square elsewhere —
  the same recipe as `GlassCapsule`, not a new one.
- Motion: `translateX(1 → 0)`, **220 ms**, `Curves.easeOutCubic`; exit the
  reverse. When closed it must not hit-test (`IgnorePointer` / `Visibility`).
- It **never** touches the container: the timeline and the control row stay
  exactly where they are (hard rule 5), and because it starts at y = 148 it
  cannot cover the timeline's right-hand readout at any window width.
- **The panel overlays the video; it does not dock it.** The picture keeps its
  size and aspect scaling while the panel is open — glass (blur 18 over
  `AppColors.glass`) already lets the covered image glow through. Docking
  instead (shrinking the video by 322 px) was rejected: it rescales the picture
  on every open *and* every close, mid-scene, and the chrome block cannot follow
  it (rule 5), so the video would end up narrower than the timeline sitting
  directly above it. The study demonstrates both — "Panel opens → docks the
  video".

**4.2 Z-order (bottom → top)**

`video → playlist panel → chrome block (title bar + controller) → Open pill →
OSD deck → modal barrier + modal`

The OSD deck must stay above the panel — at the 800 px minimum width a wide
card (the Resume toast) can reach the panel's left edge, and the deck is never
allowed to be covered.

The **undocked** window (§4.9) is not in this Stack at all: it is a separate OS
window owned by the same process, so it floats above SALU's whole surface and
follows its own drag position.

**4.3 Content — rows only, no headers, no labels (rule 1)**

Row anatomy, 38 px tall, radius 9:

```
≡ grip · [solid chevron on the playing row only] · name · duration · (hover) 🗑
```

- `≡` = `GripMark` (16 px) — drag to reorder. Same handle as the URL rows, so
  the gesture is already taught by the app.
- The playing row repeats the mark's chevron at 12 px, full white, name at
  `textPrimary` + w600; every other row's name is `#C9C9CC`.
- **Duration: current item only** (`PlayerService.duration`). Other items show
  nothing — probing 40 files for metadata is out of scope for this phase.
- Hover wash `rgba(255,255,255,.055)`; the 🗑 (`TrashMark`, 16 px) fades in on
  the right, on hover only — the URL rows' exact pattern.
- Click anywhere on a row = play that index. No "select then load".

### Auto-scroll — the playing row stays in the visible area

- **Only when required.** If the playing row is fully visible (6 px slack from
  either edge), the list does not move at all. A panel that re-centres on every
  index change fights the reader.
- **Shortest distance to the nearest edge** — never "centre it". Centring turns
  a one-item advance into a long jump on a 40-file queue.
- **Motion:** 220–300 ms `easeOutCubic`, matching the family. On panel
  *entrance* the reveal is a **jump with no animation** (the slide is already
  the motion); animated only for later index changes while the panel is open.
- **Triggers:** index change only — auto-advance, Next/Previous, a row click,
  a resume. Not filtering, not reordering.
- **Never fight the user.** Suppress the reveal while the pointer is scrolling
  the list and for ~3 s after a manual scroll; resume on the next index change.
- If the filter (§4.5) has hidden the playing row, the reveal does nothing —
  there is nothing to reveal, and the filter must not be overridden.

**4.4 Header row — five marks, no words** *(owner's change of plan, 2026-09-06)*

The four-tab strip (Playlist · Video · Audio · Subtitles) is **removed** from
this panel. It is a playlist panel and nothing else. Where the Video / Audio /
Subtitle views live now is an open Phase 4 question — the control row's right
edge is still reserved for them (§1, decision 1), and they must not come back
as tabs on top of the queue.

The header appears **only when the queue is non-empty** (owner's rule), so none
of the five ever needs a dimmed state for "nothing to act on". Left to right,
in a 322 px panel with 8/10 px padding and a hairline underneath:

| # | Control | Mark | States & tooltip |
|---|---|---|---|
| 1 | **Repeat** | the family's existing ¾-arc + arrowhead (`RestartMark`'s geometry) | cycles **off → all → one**. Off = the arc at the quiet 55 % ink (still hoverable) · all = full ink · one = full ink **plus a solid bead at the arc's centre** — never a numeral, rules 1 & 6. `active:` glow when not off. Tooltips "Repeat off / Repeat all / Repeat one" (the Mute/Unmute precedent) |
| 2 | **Shuffle** | two crossing rules with arrowheads at their right ends | on/off toggle, glow when on, tooltip "Shuffle". Must cross and carry heads so it can never be read as the transport's `<<` / `>>` |
| 3 | **Search** | thin glass field, radius 14, **magnifier mark inside the left edge**, **✕ inside the right edge only while there is text** | no placeholder text (rule 1) — the magnifier and the tooltip name it. Takes the remaining width |
| 4 | **Clear playlist** | `TrashMark` | instant, no confirmation, 5 s **Undo** toast (rule 3) |
| 5 | **Undock / Dock back** | one slot, two marks: a window with an arrow leaving it / the same window with the arrow returning | swaps with the state (the plus→× precedent), tooltips "Undock" / "Dock back" |

Space math: four 30 px marks + gaps ≈ 128 px, leaving ~174 px for the field.
Tight but workable. **Escape hatch if it ever feels cramped:** a collapsing
field — at rest just the magnifier mark, expanding into the field on click.
Recorded, not built pre-emptively.

Marks this needs: **three new drawings** (shuffle, magnifier, the undock/dock
pair). Everything else is reused: the loop arc from `RestartMark`, the ✕ the
plus already rotates into, `TrashMark`, `PlusMark`.

**4.5 Search — the one text field, and what it costs**

- **It filters the VIEW only.** The queue's contents and order are never
  touched by a search. Repeat, shuffle, clear, reorder and row-click all act on
  the **real** queue, not on the filtered list. (This is the classic bug; write
  it into the tests.)
- Live filtering as you type — no submit, no button.
- **No match** → the magnifier at 40 px, 30 % ink, centred. No words (rule 1).
- Footer count: `9 / 14` while filtering, `14` otherwise. Numerals are data,
  not instruction text — the same precedent as the volume bar's in-bar `62%`
  and the timeline's readouts.
- **Focus — the one exception to §4.8.** Clicking the field takes focus, so
  while it is focused Space and ←→ type and move the caret instead of driving
  the transport. Clicking anywhere else in the panel (a row, a header mark, the
  background) releases focus and the transport keys work again. The panel
  itself still never grabs focus on open.
- **Esc precedence:** field focused *with* text → clear the text, keep focus,
  consume. Field focused and *empty* → release focus, consume. Panel open, no
  field focus → close the panel. Pill open → the pill wins, it already owns Esc.

**4.6 Footer — one mark**

`PlusMark` (18 px) = **append files** → the native Windows picker, appended to
the queue without disturbing playback, plus the count readout (§4.5). Removal is
per-row (🗑). The footer stays visible even with an empty queue, so the panel is
never a dead end.

**4.7 Empty state — the mark itself**

Nothing queued: no header, `NowRowMark(size: 46, now: -1)` at ~30 % ink centred,
and the footer's `+`. No words, no hint, no illustration (rule 1).

**4.8 The panel is not a popup — *(default, veto-able)***

follow.md §3's "Esc closes · click-outside closes" governs **popups, menus and
modals**. §8 classifies the playlist as a **slide-out panel** — a live task used
*while watching*. So:

- **Click-outside does NOT close it.** A click on the video is play/pause; if
  that also closed the panel, the panel could not survive one pause.
- **Esc closes it** (§4.5 precedence) and **Ctrl+L toggles it**.
- **It does not take focus** — except the search field, and only while typing
  (§4.5). You keep watching with Space and ←→ while the panel is open.
  Consequence: no ↑↓ row walking in this phase.
- **No `ChromeLock`.** The chrome may auto-hide after 3 s while the panel stays
  open; the panel stays anchored at y = 148 and does not slide up. Locking the
  chrome would pin the top bar for a whole episode.

**4.9 Undock / dock — a third surface class**

What the owner wants: the playlist leaves the player and becomes **its own
window** — same 322 px width, same glass, draggable anywhere on the desktop,
independent of the player (it survives auto-hide, minimize and fullscreen), and
it docks back into the exact same slot.

**This is a contract change, not a detail.** follow.md §8 allows exactly two
surfaces today ("modal vs panel … never mix"). A detached window is a third
kind, so **§8 must be amended before this is built** — otherwise the next
session will read "never mix" and refuse to build it, or build it silently and
break the contract.

**It is the largest single item in this feature — bigger than the panel.**
`window_manager` manages one window; a second needs a multi-window package
(e.g. `desktop_multi_window`), which spawns a child window with **its own
engine and isolate**. Consequences:

- The child cannot read `QueueService.instance` — different isolate. Every
  state change (queue, index, position, repeat, shuffle, filter text) must
  cross a channel, and every action (play row, remove, reorder, clear, toggle)
  must come back as an intent.
- **Design that as one snapshot-out / intent-in contract**, because Phase 8's
  Android remote needs exactly the same shape over a WebSocket. Build the
  protocol once, reuse it twice.
- Single instance (follow.md §7) survives — a child window is not a second
  instance — but `main.dart`'s single-instance handshake and the
  file-association routing must be verified not to treat the child as a launch.

Locked behaviours:

- Undocking **moves** the panel, it does not copy it: the docked slot goes
  empty and exactly one playlist view exists on screen.
- While undocked, the control-row mark **summons and raises** the loose window
  (with a brief outline pulse) — it never opens a second, empty docked panel.
  One queue, one truth. Same for Ctrl+L.
- The header's mark swaps to **dock back**; clicking it returns the window to
  the slot at y = 148 and disposes the child window.
- Closing the loose window with its own caption ✕ = **dock back**, never
  "delete the playlist".
- Its drag area is the header, so the five marks keep working while it is loose.
- Repeat / shuffle / filter state lives in the **player** process; the loose
  window mirrors it, so docking back restores exactly what was on screen.
- *(default)* **Above SALU, not above every other app.** The child stays on top
  of the player only. System-wide always-on-top is a separate pin, later — a
  permanently top-most window over other applications is hostile.
- While undocked, the video, the chrome and the control row are unchanged.

**Phasing (recommended):** ship the docked panel first — mark, control, panel,
rows, header, search, auto-scroll — then build undock as its own step behind the
same `PanelService`. It carries a new dependency and engine-level work, and it
must not hold the docked panel hostage.

## 5. Service work

**`QueueService`** — add, keeping `paths` an unmodifiable list and every
mutation a single `paths.value = …` assignment so listeners fire once:

```dart
void append(List<String> items);   // dedupe not required this phase
void removeAt(int i);              // keeps `index` honest, see below
void move(int from, int to);
```

`removeAt` index rule: removing an item **before** the current one decrements
`index`; removing the current one leaves `index` where it is (the engine keeps
playing the file it already opened — mpv's playlist entry is removed, playback
is not interrupted); removing the last item clamps `index`.

> **Verify on Windows before shipping step 5:** that mpv really continues the
> loaded file after `player.remove(currentIndex)`. If it instead advances or
> stops, change the rule to *"removing the playing item ends playback of it and
> selects the neighbour"* and update checklist item 6 — do not silently keep a
> rule the engine does not honour.

**`PlayerService`** — public wrappers, because `_openQueueAt` is private and
carries the resume memory:

```dart
Future<void> playIndex(int i);                  // = stopMemory = null; _openQueueAt(i)
Future<void> removeFromQueue(int i);            // QueueService.removeAt + player.remove(i)
Future<void> moveInQueue(int from, int to);     // QueueService.move    + player.move(from, to)
Future<void> appendToQueue(List<String> paths); // QueueService.append  + player.add(Media(...)) per item
```

Use `playIndex` (not `player.jump`) for row clicks so resume memory and the
Resume toast behave exactly as they do for Previous/Next. While the engine is
**stopped or idle**, mutations touch `QueueService` only — `_openQueueAt`
rebuilds mpv's playlist from the queue on the next play, which is already how
Stop-parks-the-queue works.

**Repeat & shuffle — new state, and one trap.**

```dart
enum RepeatMode { off, all, one }
final ValueNotifier<RepeatMode> repeatMode;   // PlayerService
final ValueNotifier<bool> shuffleOn;          // PlayerService
```

- Repeat maps naturally onto media_kit: `player.setPlaylistMode(PlaylistMode.none
  | .loop | .single)`. Shuffle looks like `player.setShuffle(true)` — **do not
  use it.** mpv shuffles *its own* playlist, which is the playlist SALU handed it
  from `QueueService.paths`; the two orders would silently diverge and every
  index-based row click, remove and reorder would hit the wrong item.
- Keep mpv's playlist in queue order and let **SALU choose the next index**:
  listen to `player.stream.completed` and, when shuffle or repeat-one is active,
  call `playIndex(chosen)` instead of letting mpv advance. Repeat-all at the end
  of the queue wraps to 0.
- Shuffle picks from the **not-yet-played** items of the current pass, then
  starts a new pass — never the same item twice in a row, never a pure random
  pick that can repeat.
- Both must survive Stop: Stop parks the queue, and the parked queue keeps its
  repeat/shuffle mode. Persisting them across app restarts is **out of scope**
  (`shared_preferences` is allowed by §7 of follow.md, but not decided here).
- **Cost to note:** intercepting `completed` gives up mpv's native gapless
  advance for the shuffled / repeat-one cases. Acceptable for video; if gapless
  audio ever matters, that is the trade being made.

**Undo (rule 3, no confirmation dialogs):** removal and reorder are instant and
offer a **5 s Undo toast** — reuse the Resume toast's interactive-card pattern
(one word on the action is the single allowed exception to "no text on
controls"). Undo restores the item at its original index via `player.add` +
`player.move`.

---

## 6. Keyboard (silent — never printed, rule 2)

| Key | Action | Note |
|---|---|---|
| **Ctrl+L** | toggle the playlist panel | add to the Ctrl block in `_onKeyEvent` next to Ctrl+O/F/U. `L` is free; a bare letter is not acceptable (M and S are taken, and a search field is on the roadmap) |
| **Esc** | close the panel (consumed) | precedence, highest first: **pill** (already owns Esc) → **search field with text** (clear it, keep focus) → **search field empty** (release focus) → **panel** (close). Extend the existing Esc branch in this order |
| Space, ←→, ↑↓, M, S, PgUp/PgDn | unchanged | the panel takes no focus, so the transport set keeps working while it is open — **except while the search field is focused** (§4.5), which is the one place typing must win |
| Ctrl+L while undocked | raise the loose window | identical to clicking the mark: never opens a second docked panel (§4.9) |

---

## 7. Steps (each leaves the app runnable)

1. **The mark** — `NowRowMark` in `salu_marks.dart` + `playlistRowOf`; add both
   to the family doc-comment list at the top of that file.
2. **The control** — `PanelService` + `playlist_control.dart`; `controller_panel.dart`
   left zone becomes:
   ```dart
   Align(
     alignment: Alignment.centerLeft,
     child: Row(mainAxisSize: MainAxisSize.min, children: const <Widget>[
       OpenMediaControl(),
       SizedBox(width: 6),        // playlist_imp.md §1.1 — set 2 to fuse them
       PlaylistControl(),
     ]),
   ),
   ```
   Row height stays 36 px, the timeline does not move, the right edge stays empty.
3. **The panel shell** — mount in `home_screen.dart`'s Stack at
   `top: kChromeBlockHeight, right: 0, bottom: 0, width: 322`, glass + slide +
   `IgnorePointer` when closed; a stub body is fine at this step.
4. **Rows** — bind to `QueueService`; name, now-chevron, click = `playIndex`;
   hover wash.
5. **Row actions** — 🗑 remove + 5 s Undo toast; `≡` drag reorder via
   `ReorderableListView` (or a manual drag) + `player.move`. No up/down buttons.
6. **Auto-scroll** — the reveal rule of §4.3: jump on entrance, 220–300 ms
   animated afterwards, shortest distance, only when required, suppressed for
   ~3 s after a manual scroll.
7. **Header row** — repeat (off/all/one, bead for "one"), shuffle, clear
   playlist (+ Undo toast), undock/dock slot. Three new marks to draw:
   shuffle, magnifier, the undock/dock pair. Header hidden while the queue is
   empty (§4.4, §4.7).
8. **Search** — the field, live view-only filtering, the ✕ inside it, the
   no-match state, the footer count, and the focus/Esc rules of §4.5. This step
   is the one that touches the keyboard handler.
9. **Repeat & shuffle behaviour** — §5: `RepeatMode`, `shuffleOn`, the
   `stream.completed` interception, never `player.setShuffle`.
10. **Append** — footer `PlusMark` (native picker → append) and the panel as a
    drop target: **drop on the panel = append, drop on the canvas = replace**
    (Phase 5's rule; `drop_handler.dart` needs the panel-hit-test branch).
11. **Polish** — empty states, Esc/Ctrl+L, glow on `active`, motion timings, and
    a pass over R2/R3 (pill coexistence, glow visibility from a distance).
12. **Docs** — README phase table (Phase 4 → in progress), add the new marks to
    `follow.md` §1.6's family list, **amend follow.md §8 for the third surface
    class (§4.9)**, and flip this file's status line to *FINAL & IMPLEMENTED*
    with the date and commit.

**Then, as its own phase (do not start it before step 12):**

13. **Undock / dock** — the multi-window dependency, the child window's glass
    shell, the snapshot-out / intent-in channel (§4.9), drag by the header,
    raise-on-summon, dock-back, and closing = docking. Written so Phase 8's
    Android remote can reuse the same protocol.

**Out of scope here:** the Video / Audio / Subtitle views — **the four-tab strip
is removed from this panel** (§4.4) and those three need a new home, most likely
their own marks on the control row's still-reserved right edge; chapter markers;
IPTV grouping of large `.m3u` files and `.m3u` handling generally (**the owner
takes that next**); per-item metadata probing; persisting the queue, repeat or
shuffle across restarts (`shared_preferences` is allowed, the queue stays
runtime — follow.md §7).

---

## 8. Acceptance checklist

1. Row 2 reads `+ >≡ | > □ |<< >>| << >> ⊂)) [bar]`, 6 px between `+` and the
   playlist mark, row still 36 px, timeline still Row 1 and unmoved.
2. Empty queue → three quiet rules, no chevron, mark still clickable; the panel
   opens to the ghost mark with no words anywhere.
3. Queue of 5 → playing #1 puts the chevron on row 1; #3 on row 2; #5 on row 3.
   Nothing animates between them.
4. Click the mark → panel slides from the right in 220 ms, top edge exactly at
   y = 148, control row fully visible and clickable, mark full white + faint glow.
5. Click a row → that item plays; a remembered position resumes silently and the
   Resume toast fires exactly as it does for Next.
6. Hover a row → 🗑 fades in; click → the row is gone instantly + a 5 s Undo
   toast; Undo puts it back at the same index, playback undisturbed.
7. Drag a row by `≡` → the list reorders, mpv's playlist follows, playback does
   not restart.
8. Drop 3 files on the panel → appended, current item untouched. Drop the same
   3 on the canvas → the queue is replaced (existing behaviour, unchanged).
9. Esc closes the panel; Ctrl+L toggles it; neither appears anywhere in the UI.
10. With the panel open, the chrome auto-hides after 3 s and the panel stays;
    moving the mouse brings the chrome back with the mark still glowing.
11. Open the `+` pill while the panel is open → both coexist; the first click on
    a panel row closes the pill instead of acting (R2, intended).
12. Press the mark → it sinks to 0.90× with nothing drawn behind it; release →
    it springs back and the glow appears in the same frame the panel starts
    moving. Tooltip reads "Playlist" closed, "Hide playlist" open.
13. Open with a 40-item queue → the playing row is already on screen when the
    panel settles (no visible scroll); let it auto-advance off-screen → the list
    scrolls to the new row in 220 ms.
14. While the panel is open the picture does **not** rescale, the chrome does not
    shift, and the timeline's readouts stay where they were.
15. Click the mark mid-slide → the panel reverses from where it is, it does not
    restart or jump.
16. The header appears **only** once something is queued; with an empty queue
    the panel is the ghost mark plus the footer `+`, and nothing else.
17. Repeat cycles off → all → one per click: quiet arc → full arc → arc + centre
    bead, glow on anything but off, and the tooltip names the new state each time.
18. Shuffle toggles with the glow — and mpv's own playlist order is untouched
    (no `player.setShuffle`), so a row click, a removal and a reorder still hit
    the items they appear to hit.
19. Type in the field → the list filters live, the ✕ appears inside the field,
    the footer reads `n / 14`; clear it → the full list returns. The real queue
    never changed: repeat, shuffle, clear and row-clicks act on all 14.
20. Field focused → Space types a space and ←→ move the caret, the transport does
    not fire; click a row → Space is play/pause again.
21. Esc: text in the field → the text clears and the panel stays; empty field →
    focus releases; again → the panel closes; pill open → only the pill closes.
22. A filter with no match → the magnifier at 30 % ink, centred, no words.
23. Clear playlist → the queue is gone instantly with no dialog, and a 5 s Undo
    toast restores it exactly as it was.
24. Undock → the playlist becomes its own window at the same 322 px width,
    draggable by its header, the docked slot goes empty, and the header mark
    becomes dock-back. While it is loose, the control-row mark and Ctrl+L
    **raise** it rather than opening a second docked panel, and its own ✕ docks
    it back — it never deletes the playlist.
25. With a 14-item queue: opening on item 12 reveals it with **no** scroll
    animation; advancing to 13 scrolls the shortest distance in ~250 ms; manual
    scrolling suppresses the reveal for ~3 s.
26. No ripples, no splashes, no filled box or pill behind any icon, no
    instruction text, no placeholder string, no shortcut labels, no confirmation
    dialog — and **no tab strip anywhere in the panel**.

---

## 9. Decision record

| # | Decision | Value | Chosen by |
|---|---|---|---|
| 1 | Placement | left zone, right of `+` (preview option B) | **owner**, 2026-09-06 |
| 2 | Mark | Now Row (ragged rules + solid chevron head) | **owner**, 2026-09-06 |
| 3 | State channel | position in thirds | **owner**, 2026-09-06 |
| 4 | Panel top | below the chrome block (`kChromeBlockHeight`) | **owner**, 2026-09-06 |
| 5 | Pitch `+` → mark | 6 px (2 px = the fused variant) | default, §1.1 |
| 6 | Open state | `active:` glow only, no glyph change | default, §2.2 |
| 7 | Enabled | always, never dims | default, §3.1 |
| 8 | Tooltip | "Playlist" (not "Queue") | default, §3 |
| 9 | Panel ≠ popup | no click-outside close, no focus steal, no ChromeLock | default, §4.6 |
| 10 | Close paths | mark toggle · Esc · Ctrl+L | default, §6 |
| 11 | Width / material | 322 px, `GlassCapsule` recipe, left hairline | default, §4.1 |
| 12 | Rows | click = play · hover 🗑 + Undo · `≡` drag reorder | default, §4.3 |
| 13 | Empty state | the mark itself at 30 % ink, no words | default, §4.5 |
| 14 | Tab strip | **REMOVED** from this panel — it is playlist-only; Video / Audio / Subtitles need a new home (the row's right edge is still reserved) | **owner**, 2026-09-06 |
| 15 | Open choreography | press 0.90× → spring back + glow + slide/fade 220 ms easeOutCubic, one controller, mid-flight reverses | default, §4.0 |
| 16 | Video | **overlaid, never docked** — no rescale on open/close | default, §4.1 |
| 17 | Tooltip | "Playlist" / "Hide playlist", following the Mute/Unmute precedent | default, §3 |
| 18 | Reveal | opening scrolls to the playing row with no animation | default, §4.3 |
| 19 | Header row | repeat · shuffle · search · clear playlist · undock, left to right, marks only | **owner**, 2026-09-06 |
| 20 | Header visibility | only while the queue is non-empty | **owner**, 2026-09-06 |
| 21 | Search field | magnifier inside-left, ✕ inside-right, no placeholder, **filters the view only** | **owner** (field + ✕) + default, §4.5 |
| 22 | Repeat glyph | the family's loop arc · bead at its centre = repeat one · quiet ink = off · never a numeral | default, §4.4 |
| 23 | Focus | the search field is the only focusable thing in the panel; Esc precedence per §4.5 | default, §4.5 |
| 24 | Clear playlist | instant + 5 s Undo, no confirmation | default, §4.4 |
| 25 | Undock | its own draggable window, same 322 px, header = drag area; the mark raises it while loose; closing = dock back | **owner**, 2026-09-06 |
| 26 | Undock stacking | above SALU only, never system-wide always-on-top | default, §4.9 |
| 27 | Auto-scroll | only when required · shortest distance · jump on entrance · ~3 s suppression after a manual scroll | **owner** (behaviour) + default (numbers), §4.3 |
| 28 | Shuffle engine | SALU picks the next index off `stream.completed`; **never** `player.setShuffle` | default, §5 |
| 29 | Build order | docked panel first (steps 1–12), undock as its own phase (step 13) | default, §7 |

Rejected on the way (recorded so they are not re-proposed silently): Queue Rail
and its hinged/mirrored variants, Bead Queue, Panel Hinge (rect + divider —
one hollow rounded rect away from `□` Stop), right-edge placement (options A
and C), "bead = something is queued", full-height panels, **docking the video**
(rescales the picture on every toggle and the chrome cannot follow), any
scale-on-enter motion for the panel (edge-anchored surfaces slide, they do not
grow), **the four-tab strip inside this panel** (owner's change of plan), a
numeral "1" inside the repeat loop (text on a control, rules 1 & 6), a
placeholder string in the search field, `player.setShuffle` (it desyncs mpv's
order from `QueueService`), and centring the playing row on every advance
(long jumps on a 40-file queue).
