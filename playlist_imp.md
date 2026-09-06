# Playlist control & slide-out panel — implementation brief

> **Status:** **FINAL & IMPLEMENTED** (2026-09-06) — phases A (§§1–9,
> steps 1–13) and B (§10, M-1…M-11) are both in. Bridge transport used is
> `desktop_multi_window` 0.3.1's `WindowController` + `WindowMethodChannel`
> pattern; the `PlaylistBridge` message shape (snapshot-out/delta-out/
> intent-in) is the seam Phase 8's Android remote will reuse over a
> WebSocket.
>
> **New session? Read this box, then §10 in full.** The document covers two
> phases that ship in order:
> **(A) the local playlist panel — §§1–9**, and
> **(B) m3u / IPTV channel mode — §10**, which is built *after* A and never
> interleaved with it.
> §10 is self-contained: brief (§10.0–10.11), build steps (§10.12), acceptance
> checklist (§10.13) and 49 numbered decisions M1–M46 (§10.14).
> **Start at §10.0** — it documents a blocker verified in the code: SALU
> currently hands the whole `.m3u` URL to mpv, so no channel metadata ever
> reaches the app. Nothing else in §10 can be built before the parser.
> The interactive study `design/playlist-mark-preview/index.html` implements
> every §10 behaviour (Source → m3u; Scale → 50 000 channels) and is the
> reference for anything the prose leaves ambiguous.
>
> §10 headlines: the header's first two slots swap to group-by and favourite,
> repeat and shuffle are dropped, rows lose drag and delete, groups are an
> accordion, a dead channel toasts **"Failed to load"** and **skips to the next**
> (3 strikes stop the cascade), the timeline goes inert with a live shimmer, and
> the engine holds one media instead of the whole list.
> **Note the one reversal:** M3 ("stay on the dead channel") was overturned by
> the owner on the same day and is superseded by **M3b–M3e** — the table keeps
> the dead row struck through so the change is not silently re-litigated.
> Earlier the same day:
> the panel's four-tab strip is **removed** and replaced by a five-mark header
> row — repeat · shuffle · search · clear · undock — with no footer, the count
> inside the search field, absolute clear, and undock built in the same pass.
> See §4.4, §4.5 and §4.8). This is
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
the ghost mark inside it tells the truth ("nothing is queued") better than a
dimmed control in the row does. The empty panel still accepts drops (§7 step 9),
so it is not inert. Precedent for dimming (`Stop`, `Next`) applies to *transport
verbs with nothing to act on*; a view toggle is not a verb.

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
| **+3 s** | The chrome auto-hides as usual (§4.7) and the panel stays, anchored at y = 148, hanging over the video where the chrome was. |

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

The **undocked** window (§4.8) is not in this Stack at all: it is a separate OS
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
- **Deleting the row that is playing** (owner's rule, 2026-09-06): SALU picks the
  **next** item automatically; if there is no next, the **previous**; if the
  deleted item was the only one, SALU returns to its **initial state** (playback
  stopped, queue empty, logo canvas). The picked item goes through `playIndex`,
  so its resume memory applies exactly as it does for Next. Full mechanics in §5.
- **The scrollbar is SALU's own**, never the platform's or Material's: a thin
  (~5–6 px) rounded thumb at `rgba(255,255,255,.16)`, brightening to ~`.30` on
  hover, over a **transparent track**, no arrow buttons, and it fades out when
  the list is idle. Flutter's desktop `ScrollBehavior` attaches a Material
  scrollbar whose light gray thumb reads as a white stripe on `#1E1E1E` glass —
  override it (`ScrollConfiguration` with `scrollbars: false`, then SALU's own
  `RawScrollbar` styling). This is a hard style rule, not a detail.
- **Shuffle never reorders the visible list** (owner's rule): the rows always
  show the queue's natural order. Shuffle changes *playback order* only — see §5.

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

**4.4 Header row — five docked marks, no words** *(owner's change of plan, 2026-09-06)*

The four-tab strip (Playlist · Video · Audio · Subtitles) is **removed** from
this panel. It is a playlist panel and nothing else. Where the Video / Audio /
Subtitle views live now is an open Phase 4 question — the control row's right
edge is still reserved for them (§1, decision 1), and they must not come back
as tabs on top of the queue.

The docked header appears **only when the queue is non-empty** (owner's rule),
so none of the five docked controls needs a dimmed state for "nothing to act
on". The loose window keeps its header even after a clear, so Dock and Close
remain reachable; queue verbs simply dim there. Left to right, in a 322 px panel
with 8/10 px padding and a hairline underneath:

| # | Control | Mark | States & tooltip |
|---|---|---|---|
| 1 | **Repeat** | the family's existing ¾-arc + arrowhead (`RestartMark`'s geometry) | cycles **off → all → one**. Off = the arc at the quiet 55 % ink (still hoverable) · all = full ink · one = full ink **plus a solid bead at the arc's centre** — never a numeral, rules 1 & 6. `active:` glow when not off. Tooltips "Repeat off / Repeat all / Repeat one" (the Mute/Unmute precedent) |
| 2 | **Shuffle** | two crossing rules with arrowheads at their right ends | on/off toggle, glow when on, tooltip "Shuffle". Must cross and carry heads so it can never be read as the transport's `<<` / `>>` |
| 3 | **Search** | thin glass field, radius 14 · inside it, left to right: **magnifier mark · the typed text · the count · ✕ (only while there is text)** | no placeholder text (rule 1) — the magnifier and the tooltip name it. Takes the remaining width. The count is part of the field, not a footer (§4.5) |
| 4 | **Clear playlist** | `TrashMark` | **absolute**: playback stops, the queue empties, SALU returns to its initial state (the logo canvas). Instant, no confirmation, 5 s **Undo** toast (rule 3) — see §5 |
| 5 | **Undock / Dock back** | one slot, two marks: a window with an arrow leaving it / the same window with the arrow returning | swaps with the state (the plus→× precedent), tooltips "Undock" / "Dock back" |

Loose window only: a final **Close** ✕ after Dock hides the playlist view while
leaving playback and the queue untouched.

Docked space math: four 30 px marks + gaps ≈ 128 px, leaving ~174 px for the field —
and the field now has to hold the magnifier (~20 px), the count (~28 px) and the
✕ (~20 px) as well, so typed text gets ~100 px. Tight but workable, and removing
the footer is what keeps it that way. **Escape hatch if it ever feels cramped:**
a collapsing field — at rest just the magnifier mark, expanding into the field on
click. Recorded, not built pre-emptively.

**The panel has exactly two zones: the header and the rows.** No footer, no tab
strip, no title, no section labels (rules 1 and 6).

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
- **The count lives inside the field**, at its right edge, left of the ✕
  (owner's decision — there is no footer at all, §4.4). It reads `14` normally
  and `9 / 14` while a filter is hiding rows. Numerals are data, not instruction
  text — the same precedent as the volume bar's in-bar `62%` and the timeline's
  readouts. 10 px, `#7C7C80`, tabular figures, and it must never be clickable.
- **There is no footer and no append button in this panel** (owner's decision).
  Files enter the queue through the Open control (`+` → file / folder / URL) or
  by dropping onto the panel; the playlist panel only *shows and orders* what is
  already queued. Removing the footer also gives the field its width back.
- **Focus — the one exception to §4.7.** Clicking the field takes focus, so
  while it is focused Space and ←→ type and move the caret instead of driving
  the transport. Clicking anywhere else in the panel (a row, a header mark, the
  background) releases focus and the transport keys work again. The panel
  itself still never grabs focus on open.
- **Esc precedence:** field focused *with* text → clear the text, keep focus,
  consume. Field focused and *empty* → release focus, consume. Panel open, no
  field focus → close the panel. Pill open → the pill wins, it already owns Esc.

**4.6 Empty state — the mark itself**

Nothing queued: **no header**, `NowRowMark(size: 46, now: -1)` at ~30 % ink
centred, and that is all — the panel is two zones (header + rows) and when there
is no queue there is no header either. No words, no hint, no illustration
(rule 1). The panel still accepts drops while empty (§7 step 9).

**4.7 The panel is not a popup — *(default, veto-able)***

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

**4.8 Undock / dock — a third surface class**

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
Verified state of the platform (checked 2026-09-06):

- Flutter **stable ships no public multi-window API**. As of 3.44.8 (2026-07-23)
  the framework's windowing API exists but only on the **main** channel behind
  `flutter config --enable-windowing`, is marked `@internal`, and is documented
  as breaking between patch releases — not a foundation for a production build.
  Its decisive property: **all windows share one engine and one isolate**, so a
  `ValueNotifier` in a common ancestor is visible to both with no channel and no
  serialization. That is exactly what this feature wants.
- On stable today the practical path is the **`desktop_multi_window`** plugin
  (0.3.0, published 2025-10-28; Windows / Linux / macOS), which spawns a child
  window with **its own engine and isolate**. `window_manager` — what SALU
  already uses — manages one window only and cannot create a second.

**Owner's verdict (2026-09-06): it is possible, so it is IN SCOPE and must be
fully implemented as part of this playlist build** — not deferred to a later
phase. Consequences of doing it on stable today:

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
- Closing the loose window with its own caption/header ✕ = **hide the playlist
  view**, never clear the playlist and never stop playback; the next chrome
  playlist click opens the docked panel again.
- Its drag area is the header, so the header marks keep working while it is loose.
- Repeat / shuffle / filter state lives in the **player** process; the loose
  window mirrors it, so docking back restores exactly what was on screen.
- *(default)* **Above SALU, not above every other app.** The child stays on top
  of the player only. System-wide always-on-top is a separate pin, later — a
  permanently top-most window over other applications is hostile.
- While undocked, the video, the chrome and the control row are unchanged.

**4.8a The child engine's window contract (learned the hard way, 2026-09-06).**
The loose window is a SECOND engine, and SALU's plugins are registered per engine.
Three rules follow, and all three are load-bearing:

- `windows/runner/flutter_window.cpp` MUST hand every child engine the plugin set:
  `DesktopMultiWindowSetWindowCreatedCallback([](void *c) { RegisterPlugins(
  reinterpret_cast<flutter::FlutterViewController *>(c)->engine()); });`
  Without it the child has **no `window_manager` at all** — every call there dies
  with `MissingPluginException` — so the loose window cannot go frameless, size
  itself, remember its bounds, hold the close, drag, or destroy itself. If the
  undocked window ever looks native-sized (800×600, real title bar) or refuses to
  close, THAT line is the first thing to check, not the Dart.
- Closing a window is `windowManager.close()` (SC_CLOSE) after
  `setPreventClose(false)`. **`destroy()` on Windows is `PostQuitMessage(0)`** — it
  quits a message loop, it never closes the HWND — so it is a last resort, never
  the first call.
- **No native bar, ever, in either engine.** The loose window uses the player's
  own chrome contract — `titleBarStyle: TitleBarStyle.hidden` +
  `windowButtonVisibility: false` (window_manager eats WM_NCCALCSIZE, so the
  caption strip and its buttons belong to the Flutter view; the panel's header is
  the drag area and the only ✕). `_configureWindow()` guards each step separately
  and answers whether the bar is actually gone; that answer rides to the host with
  `ready`, and a `false` triggers §13a's abort gate at runtime — the window is
  hidden, never shown, and the docked slot keeps the playlist. A half-configured
  window hanging off a borderless player is a dropped feature, not a detail.

**And the host verifies, it does not hope.** `desktop_multi_window` 0.3.x gives the
main window only `window_show` / `window_hide`: no native destroy. So `dock()`
keeps the controller until `WindowController.getAll()` confirms the child is gone
(that registry entry dies with the engine, and `onWindowsChanged` is what reports
it), retries a bounded number of times, and finally HIDES the window — a zombie
nobody sees is survivable, an orphan floating over the player after a redock is
not. The docked slot's state flips first and unconditionally: the player must never
be held hostage by a window it does not own.

**Build order inside this feature:** the docked panel first (steps 1–12), then
undock (step 13) — same feature, same branch, shipped together.

**Step 13a is a bounded spike, and it is the abort gate.** Before wiring
anything: create the child window, **strip its frame** so it is borderless like
the main window, apply the glass material, and verify DPI scaling, header
dragging, and that SALU's single-instance handshake does not treat the child as
a second launch. If the child window cannot be made to look like SALU — a native
title bar we cannot remove, wrong DPI, or a visible engine-start stutter — then
**undock is dropped**, the header keeps four marks, and this section is rewritten
as rejected. We do not ship a native-looking window hanging off a borderless
player.

**Write the sync seam so it can be deleted later.** Keep every cross-window
message inside one thin `PlaylistBridge` (snapshot-out / intent-in). If the
framework windowing API reaches stable, the bridge disappears and the loose
window becomes a subtree reading `QueueService.instance` directly — with **no
change to the panel's UI code**. Until then the same bridge is the shape Phase 8's
Android remote needs over a WebSocket, so it is built once and used twice.

## 5. Service work

**`QueueService`** — add, keeping `paths` an unmodifiable list and every
mutation a single `paths.value = …` assignment so listeners fire once:

```dart
void append(List<String> items);   // dedupe not required this phase
void removeAt(int i);              // keeps `index` honest, see below
void move(int from, int to);
```

**One gesture = one block, ordered as the folder shows it (owner, 2026-09-06).**
Windows does not hand the shell's multi-select (Open dialog or a drag) over in
the order the user is looking at: the array **starts at the item that was
grabbed or clicked first and wraps** — select ten files, drag them by the
sixth, and the app receives `6,7,8,9,10,1,2,3,4,5`. A queue built from that
verbatim "starts from the middle of the folder", so the array is never trusted.
Every local batch is sorted by `MediaUtils.naturalPathCompare` at the boundary
(`OpenMediaService.openFiles`, `DropHandler.scanFolderForMedia`,
`DropHandler.handleDroppedPaths`): folder first, then the name, both natural
so digit runs count as numbers (`ep2` before `ep10`). A fresh batch then plays
from row 0 — the top file.

* This does **not** touch the append verb: blocks still join at the end, in the
  order the gestures arrived, and only the inside of a block is ordered.
* A curated order is still possible — after the fact, with the row grip
  (`move`), which is what the panel is for.

**The queue holds ONE spelling of a path (owner, 2026-09-06).** The same file
arrives as `C:\media\a.mp4` (picker, shell drop), as `file:///C:/media/a.mp4`
(mpv's report) and, after an Undo, as whichever was stored. Resume memory,
`stopMemory` and the "is this the row that was playing?" checks are all STRING
comparisons, so `QueueService` canonicalizes every entry on the way in
(`setQueue` / `append` / `insertAt` → `MediaUtils.canonicalPath`) and
`ResumeService` canonicalizes its own keys on both sides. A queue url is
therefore always comparable with `currentPath`, and a file remembered under one
spelling is found under any other. Streams are returned untouched by
`canonicalPath` — a URL's spelling is a key of its own (favourites, the URL
library) and must never be rewritten. Call sites pass raw paths; **nobody
pre-normalizes**.

**`removeAt` — the owner's rule (2026-09-06), and it replaces the earlier
"playback keeps running" idea.**

| what was deleted | what SALU does |
|---|---|
| an item **before** the playing one | `index` shifts down one; playback untouched |
| an item **after** the playing one | nothing changes; playback untouched |
| **the playing item**, and a next exists | remove it, then play the **next** item via `playIndex` (resume memory applies) |
| **the playing item**, no next, a previous exists | remove it, then play the **previous** item via `playIndex` |
| **the only item** | remove it → **initial state**: playback stopped, queue empty, logo canvas — exactly what `stop()` + `clear()` produce |

Order of operations matters: update `QueueService` first, then the engine
(`player.remove(i)`), then the follow-up `playIndex` — so the row that disappears
and the row that lights up change in the same frame the audio changes.

**`clear()` — absolute (owner's rule).** Clear playlist means: stop playback,
empty the queue, and leave SALU in its **initial state** — the logo canvas, an
empty queue, `TransportState.idle`, every transport mark dim. Nothing keeps
playing. Two things it must **not** touch: the on-disk **resume memory** (a
cleared playlist is not a wiped history) and the **saved URL seven**
(`UrlLibraryService`). The 5 s **Undo** toast restores the queue *and* re-opens
the item that was playing at its remembered position, silently — that is what
makes an absolute clear safe without a confirmation dialog (rule 3).

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

### Repeat × shuffle — the one decision table (no collisions, no conflicts)

Two controls, one question: *the item ended, what plays now?* Exactly one of
them may answer, and the marks must show which one is answering.

| repeat | shuffle | end of an item | end of the queue |
|---|---|---|---|
| **one** | off | the same item again | n/a — it never reaches the end |
| **one** | **on** | the same item again — **repeat one wins, shuffle is suspended** | n/a |
| all | off | the next item in list order | wrap to index 0 |
| all | **on** | the next item of the shuffle pass | start a **new pass** (fresh random order; its first item should not be the one that just ended) |
| off | off | the next item in list order | **stop** → the queue parks (Stop ≠ Start Over) |
| off | **on** | the next unplayed item of the pass | the pass is exhausted → **stop** → the queue parks |

- **Suspension is visible, and the setting survives.** While repeat-one is
  active, the shuffle mark drops to the quiet 55 % ink and loses its glow —
  icon-only language for "not in effect right now" — but its *state* is kept.
  Turning repeat back to all/off re-lights shuffle exactly as it was. Nothing is
  silently reset, and no text is needed to explain it.
- **A shuffle pass** = every item played once, in random order, never the same
  item twice in a row. Track it as a list of not-yet-played indexes; a manual row
  click during shuffle counts that item as played; adding, removing or clearing
  items resets the pass.
- **`|<<` and `>>|` follow what you heard, not what you see.** With shuffle on,
  Previous returns to the item actually played before and Next goes to the next
  shuffled pick — so keep a small **play-order history** in `QueueService` (a
  stack of visited indexes, reset on a new pass, on clear, and on a fresh open).
  The visible list never reorders.
- Both must survive Stop: Stop parks the queue, and the parked queue keeps its
  repeat/shuffle mode. Persisting them across app restarts is **out of scope**
  (`shared_preferences` is allowed by §7 of follow.md, but not decided here).
- **Cost to note:** intercepting `completed` gives up mpv's native gapless
  advance for the shuffled / repeat-one cases. Acceptable for video; if gapless
  audio ever matters, that is the trade being made.

**Undo (rule 3, no confirmation dialogs):** removal, reorder and clear are
instant and offer a **5 s Undo toast** — reuse the Resume toast's interactive-card
pattern (one word on the action is the single allowed exception to "no text on
controls"). What Undo restores:

- **the list, always** — the item goes back to its original index
  (`player.add` + `player.move`), or the whole queue comes back in its original
  order after a clear.
- **playback, only when the deletion had taken it away.** If Undo restores an
  item while something else is playing, playback is *not* yanked back — you are
  watching that other item on purpose. If the deletion had landed SALU in its
  initial state (the only item removed, or clear playlist), Undo **also**
  re-opens the item that was playing, silently at its remembered position.

---

## 6. Keyboard (silent — never printed, rule 2)

| Key | Action | Note |
|---|---|---|
| **Ctrl+L** | toggle the playlist panel | add to the Ctrl block in `_onKeyEvent` next to Ctrl+O/F/U. `L` is free; a bare letter is not acceptable (M and S are taken, and a search field is on the roadmap) |
| **Esc** | close the panel (consumed) | precedence, highest first: **pill** (already owns Esc) → **search field with text** (clear it, keep focus) → **search field empty** (release focus) → **panel** (close). Extend the existing Esc branch in this order |
| Space, ←→, ↑↓, M, S, PgUp/PgDn | unchanged | the panel takes no focus, so the transport set keeps working while it is open — **except while the search field is focused** (§4.5), which is the one place typing must win |
| Ctrl+L while undocked | raise the loose window | identical to clicking the mark: never opens a second docked panel (§4.8) |

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
7. **Header row** — repeat (off/all/one, bead for "one"), shuffle, the search
   field with the count inside it, clear playlist, and the undock/dock slot.
   Three new marks to draw: shuffle, magnifier, the undock/dock pair. Header
   hidden while the queue is empty (§4.4, §4.6). **No footer** — the panel is
   header + rows and nothing else.
8. **Search** — the field, live view-only filtering, the ✕ inside it, the
   no-match state, the count inside the field, and the focus/Esc rules of §4.5. This step
   is the one that touches the keyboard handler.
9. **Repeat & shuffle behaviour** — §5: `RepeatMode`, `shuffleOn`, the decision
   table, the shuffle pass, the play-order history that makes `|<<` honest during
   shuffle, the `stream.completed` interception, and **never**
   `player.setShuffle`. The visible list order must not change.
10. **Drops** — the panel as a drop target: **drop on the panel = append, drop on
    the canvas = replace** (Phase 5's rule; `drop_handler.dart` needs the
    panel-hit-test branch, including while the panel is empty).
11. **Polish** — empty states, **SALU's own dark scrollbar** (§4.3, overriding
    Flutter's desktop Material scrollbar), Esc/Ctrl+L, glow on `active`, motion
    timings, and a pass over R2/R3 (pill coexistence, glow visibility from a
    distance).
12. **Docs** — README phase table (Phase 4 → in progress), add the new marks to
    `follow.md` §1.6's family list, **amend follow.md §8 for the third surface
    class (§4.8)**, and flip this file's status line to *FINAL & IMPLEMENTED*
    with the date and commit.

13. **Undock / dock — in scope, built last** (§4.8). 13a is the frameless-child
    window **spike and abort gate**; then the `desktop_multi_window` dependency,
    the child's glass shell, the `PlaylistBridge` snapshot-out / intent-in seam,
    drag by the header, raise-on-summon, dock-back, and loose-window close =
    hide playlist view. If 13a fails, undock is dropped and steps 1–12 still
    ship.

**Out of scope here:** the Video / Audio / Subtitle views — **the four-tab strip
is removed from this panel** (§4.4) and, per the owner (2026-09-06), those three
will be **re-planned separately later**; nothing is assumed about where they go,
and the control row's right edge stays reserved and empty until that plan exists.
Also out of scope: chapter markers;
per-item metadata probing; persisting the queue, repeat or
shuffle across restarts (`shared_preferences` is allowed, the queue stays
runtime — follow.md §7). **IPTV / `.m3u` handling is no longer out of scope —
it is specified in §10 and is its own build phase, starting with the parser
(§10.0).**

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
6. Hover a row **that is not playing** → 🗑 fades in; click → the row is gone
   instantly + a 5 s Undo toast; Undo puts it back at the same index, playback
   undisturbed. (Deleting the *playing* row is item 26.)
7. Drag a row by `≡` → the list reorders, mpv's playlist follows, playback does
   not restart.
8. Drop 3 files on the panel → appended, current item untouched. Drop the same
   3 on the canvas → the queue is replaced (existing behaviour, unchanged).
8b. Select 8 files in a folder and start the drag from the 6th (or Ctrl-pick
   them out of order), drop / Open File… them → the queue reads 1…8 and the
   first thing that plays is file **1**, not file 6 (§5, one gesture = one
   block). Same for Open Folder… with names like `ep2`/`ep10`: natural order.
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
16. The docked header appears **only** once something is queued; with an empty
    docked queue the panel is the ghost mark and nothing else — no header, no
    footer — and the canvas is back to its initial state. The loose window keeps
    Dock/Close reachable if a clear empties it.
17. Repeat cycles off → all → one per click: quiet arc → full arc → arc + centre
    bead, glow on anything but off, tooltip naming the new state each time.
18. Repeat **one** with shuffle on → the shuffle mark drops to quiet ink and loses
    its glow while the same item repeats; switching repeat back to all/off
    re-lights shuffle with its setting intact. One control answers, and the marks
    say which.
19. Shuffle toggles with the glow; mpv's own playlist order is untouched (no
    `player.setShuffle`), the **visible order never changes**, and a row click, a
    removal and a reorder still hit the items they appear to hit.
20. Shuffle on: `>>|` plays an unplayed item at random and never the same one
    twice in a row; `|<<` returns to the item actually heard before; exhausting
    the pass with repeat off parks the queue (Stop ≠ Start Over).
21. Typing filters live, the ✕ appears inside the field, and the count **inside
    the field** reads `n / 14`; clearing returns the full list and `14`. The real
    queue never changed: repeat, shuffle, clear and row-clicks act on all 14.
22. Field focused → Space types a space and ←→ move the caret, the transport does
    not fire; click a row → Space is play/pause again.
23. Esc, in order: pill → field with text (text clears, panel stays) → empty field
    (focus releases) → panel closes.
24. A filter with no match → the magnifier at 30 % ink, centred, no words.
25. Deleting a row **before or after** the playing one leaves playback untouched
    and the highlighted row still the same file.
26. Deleting **the playing** row starts the next item (with its resume memory);
    with no next, the previous; with no other item at all, SALU returns to its
    initial state. Each case offers a 5 s Undo that restores exactly what was there.
27. Clear playlist → playback stops, the queue empties, SALU is in its initial
    state; Undo restores the queue **and** resumes the item at its remembered
    position. On-disk resume memory and the saved URL seven are untouched.
28. The list scrollbar is SALU's own thin dark thumb on a transparent track — no
    light gray Material thumb, no arrow buttons.
29. With a 14-item queue: opening on item 12 reveals it with **no** scroll
    animation; advancing to 13 scrolls the shortest distance in ~250 ms; manual
    scrolling suppresses the reveal for ~3 s.
30. Undock → the playlist becomes its own **borderless glass** window at the same
    322 px width, draggable by its header, the docked slot goes empty, and the
    header mark becomes dock-back. While it is loose, the control-row mark and
    Ctrl+L **raise** it rather than opening a second docked panel. Its own ✕
    hides the playlist view only — it never deletes the playlist or stops
    playback, and the next chrome playlist click opens the docked panel.
31. No ripples, no splashes, no filled box or pill behind any icon, no instruction
    text, no placeholder string, no shortcut labels, no confirmation dialog,
    **no footer, and no tab strip anywhere in the panel**.

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
| 9 | Panel ≠ popup | no click-outside close, no focus steal, no ChromeLock | default, §4.7 |
| 10 | Close paths | mark toggle · Esc · Ctrl+L | default, §6 |
| 11 | Width / material | 322 px, `GlassCapsule` recipe, left hairline | default, §4.1 |
| 12 | Rows | click = play · hover 🗑 + Undo · `≡` drag reorder | default, §4.3 |
| 13 | Empty state | the mark itself at 30 % ink, no words | default, §4.5 |
| 14 | Tab strip | **REMOVED** from this panel — it is playlist-only; Video / Audio / Subtitles need a new home (the row's right edge is still reserved) | **owner**, 2026-09-06 |
| 15 | Open choreography | press 0.90× → spring back + glow + slide/fade 220 ms easeOutCubic, one controller, mid-flight reverses | default, §4.0 |
| 16 | Video | **overlaid, never docked** — no rescale on open/close | default, §4.1 |
| 17 | Tooltip | "Playlist" / "Hide playlist", following the Mute/Unmute precedent | default, §3 |
| 18 | Reveal | opening scrolls to the playing row with no animation | default, §4.3 |
| 19 | Header row | docked: repeat · shuffle · search · clear playlist · undock, left to right, marks only; loose adds Close ✕ | **owner**, 2026-09-06 |
| 20 | Header visibility | only while the queue is non-empty | **owner**, 2026-09-06 |
| 21 | Search field | magnifier inside-left · **count inside-right** · ✕ inside-right while there is text · no placeholder · **filters the view only** | **owner**, 2026-09-06 |
| 21b | Footer | **none** — the panel is header + rows; no append button (files arrive via the Open control or a drop) | **owner**, 2026-09-06 |
| 21c | Local batch order | the shell's array is never trusted: a drop/dialog batch is re-sorted into the folder's own order (natural, case-insensitive) and plays from that top row; blocks still only ever append | **owner** (bug: 8 files started at 6/7), §5 |
| 22 | Repeat glyph | the family's loop arc · bead at its centre = repeat one · quiet ink = off · never a numeral | default, §4.4 |
| 23 | Focus | the search field is the only focusable thing in the panel; Esc precedence per §4.5 | default, §4.5 |
| 24 | Clear playlist | **absolute** — playback stops, queue empties, SALU returns to its initial state; 5 s Undo restores the queue *and* the position; resume memory and the saved seven untouched | **owner**, 2026-09-06 |
| 24b | Deleting the playing row | next → else previous → else initial state | **owner**, 2026-09-06 |
| 24c | Scrollbar | SALU's own thin dark thumb, transparent track, no arrows — never the Material/platform one | **owner** (catch) + default (spec), §4.3 |
| 24d | Shuffle & the view | shuffle never reorders the visible list; playback order only | **owner**, 2026-09-06 |
| 24e | Repeat × shuffle | the decision table of §5; repeat-one **suspends** shuffle (quiet ink, no glow) and the setting survives | default, §5 |
| 24f | Prev/Next during shuffle | follow the play-order history (what was heard), not the list | default, §5 |
| 25 | Undock | its own draggable borderless glass window, same 322 px, header = drag area; the mark raises it while loose; dock mark docks back; loose-window close/header ✕ hides the playlist view | **owner**, 2026-09-06 |
| 25b | Undock scope | **in scope for this build** (owner: "if it is possible it has to be fully implemented while making the playlist"), built as step 13 behind a frameless-window spike that is the abort gate | **owner** + default, §4.8 |
| 25c | Undock plumbing | `desktop_multi_window` on stable (Flutter ships no public multi-window API), all traffic through one `PlaylistBridge` seam so it can be deleted when the framework API lands, and reused by Phase 8 | default, §4.8 |
| 26 | Undock stacking | above SALU only, never system-wide always-on-top | default, §4.8 |
| 27 | Auto-scroll | only when required · shortest distance · jump on entrance · ~3 s suppression after a manual scroll | **owner** (behaviour) + default (numbers), §4.3 |
| 28 | Shuffle engine | SALU picks the next index off `stream.completed`; **never** `player.setShuffle` | default, §5 |
| 29 | Build order | steps 1–12 docked, step 13 undock — one feature, one branch, shipped together | default, §7 |
| 30 | Video / Audio / Subtitles | **re-planned separately later** — nothing assumed, the row's right edge stays reserved and empty | **owner**, 2026-09-06 |

---

## 10. m3u mode — the IPTV playlist (owner's brief, 2026-09-06)

> **Status:** **IMPLEMENTED** (2026-09-06). This section replaces the earlier
> "out of scope: IPTV grouping … the owner takes that next". Everything in
> §§1–9 still governs; this section states only what **changes when the loaded
> playlist is an m3u URL**. Entries marked *(default)* may be vetoed.

### 10.0 The blocker — SALU must parse the m3u itself

Verified in the code (2026-09-06):

| Fact | Where |
|---|---|
| `playUrl` → `openPath(url)` → `setQueue([url], 0)` — the queue holds **one** entry: the m3u URL | `open_media_service.dart:74`, `player_service.dart:349` |
| mpv expands the playlist internally; SALU never sees the channels | `_openQueueAt` hands mpv one `Media` |
| The index mirror is gated on `queue.paths.length == playlist.medias.length` → `1 != 24`, so **it is skipped** and SALU never learns which channel plays | `player_service.dart:177` |
| `currentTitle` = `MediaUtils.displayName(uri)` → a stream URL `…/live/user/pass/1234.ts` titles the window **"1234"** | `player_service.dart:169` |

**Therefore: SALU fetches and parses the m3u, then hands mpv a resolved list of
channel URLs.** Without a parser there is no `group-title`, no `tvg-language`,
no `tvg-country`, no `tvg-chno` and no display name — i.e. none of §§10.1–10.6
can exist. This parser is step 1 of the build order and nothing else starts
before it.

**Data model — settled (owner's challenge, 2026-09-06).** An earlier draft
proposed a **parallel `List<ChannelMeta>?`** alongside `paths`. The owner
rejected it — *"how does the user switch between local and m3u, and is it not
complicated?"* — and the code agrees: `paths` has **6 read sites and 3 mutation
sites**, so a parallel list would force every one of them to keep two
collections in lockstep forever. One missed mutation and every row shows the
wrong channel's name. Switching local → m3u → local would mean nulling and
rebuilding a second list each time, with two things to keep honest instead of
one.

**Decision: one list of objects, no parallel table, no mode flag.**

```dart
/// One queue entry. Local files fill `url` only; m3u channels fill the rest.
class QueueItem {
  const QueueItem(this.url, {this.name, this.group, this.language,
                             this.country, this.chno, this.tvgId});
  final String url;        // what mpv is handed — the only field local mode needs
  final String? name;      // m3u display name; null → derive from the path
  final String? group, language, country, chno, tvgId;
}
```

- Local mode builds `QueueItem(path)` with every other field null, so local
  playback is **byte-identical to today**.
- m3u mode fills the metadata. **Switching sources is just `setQueue(...)` with
  a different list** — exactly the mechanism that exists now. No second list, no
  null-and-rebuild, no possible desync.
- The header swap reads off the data, not a flag:
  `bool get isChannelList => items.any((QueueItem i) => i.name != null);`
- Transitional keeper so the 6 existing call sites keep compiling and can be
  migrated one at a time:
  `List<String> get paths => items.map((QueueItem i) => i.url).toList();`

Attribute reference: `#EXTINF:-1 tvg-id tvg-name tvg-logo tvg-language
tvg-country tvg-chno group-title,Display Name`.

### 10.1 The header swaps two slots, and only two

Slots 3 · 4 · 5 (search · clear · undock) are **identical to local mode**.
Slots 1 · 2 swap:

| # | local mode | **m3u mode** |
|---|---|---|
| 1 | Repeat | **Group by** — flat / category / language / country |
| 2 | Shuffle | **Favourite** — filter to favourites only |

**Repeat and shuffle are dropped in m3u mode** (owner, 2026-09-06). They are
queue verbs; live channels are not a queue. They return untouched the moment a
local queue is loaded. Recorded consequence: an m3u of VOD items also loses
them — accepted.

**Pitch, not a flat gap.** The header follows SALU's own grammar:
`[group · favourite] 14 [search] 14 [bin] 14 [undock]`, 6 px inside the mode
pair. The 2 px gap of the first draft put the field's **✕ (clear the text)**
about 4 px from the **🗑 (clear the whole playlist)**. Destructive controls do
not get 2 px.

### 10.2 Slot 1 — Group by *(default, except the four modes)*

- **One stable mark plus a pill below it** — the `+` → pill pattern the app
  already teaches. The mark **never morphs** into four different glyphs: the
  family's grammar is *one mark, modified* (repeat is one loop arc across three
  states). Four unrelated glyphs can never be learned.
- **The mark does not report the mode; the list does it better** — grouping on
  = named group heads on screen, flat = none. No 18 px glyph beats that.
- **Auto-pick on load:** if more than ~60 % of entries carry `group-title` →
  category, else flat. Remembered per playlist. The default is then right with
  no click.
- **A mode the file has no tags for is dimmed, never hidden** — a vanishing
  option reads as a broken app.
- **Group order:** category keeps the playlist's own **first-appearance** order
  (providers order deliberately); language and country are alphabetical;
  `Uncategorized` always last.
- **Normalise country and language.** `tvg-country` is usually a code (`UK`,
  `GB`, `US`), `tvg-language` a word. Without a small ISO-3166 / ISO-639 map the
  heads fragment into `UK` / `GB` / `United Kingdom`.
- **Multi-value fields are NOT split this phase.** `group-title="UK | News"`
  and `tvg-language="English;Spanish"` are real. Splitting puts one channel in
  two groups and breaks "one row = one channel index". Treat the whole string
  as one key.

### 10.3 Slot 2 — Favourites

- **Mark: the bookmark, not a star.** A five-point star at 15 px with a 1.4 px
  round-join stroke turns to mush; a bookmark is two verticals and a notch.
- **The row bookmark's visibility is the whole design** *(strong
  recommendation)*: **filled + full ink and always visible when the channel IS
  a favourite; invisible until the row is hovered when it is not.** A
  3000-channel list carrying 3000 outline bookmarks destroys the exact signal
  favourites exist to give. Hover-to-add is already the local rows' grammar.
- **Keying a channel:** `tvg-id` → `tvg-name` → display name, in that order.
  Never the index (order changes) and never the stream URL (it rotates).
  Display name alone is not enough: duplicate names are rampant in IPTV lists
  (same channel at several qualities), so one click would light four rows.
- **Keying the playlist: by HOST, not the full URL** *(default)*. Providers
  rotate credentials (`/live/USER/TOKEN/`), and a full-URL key silently wipes
  every favourite on rotation. Honest trade: two playlists on one host share
  favourites — for a personal player that is a feature.
- Storage `shared_preferences` (follow.md §7), **writes debounced ~500 ms** —
  the whole file is rewritten on every change.
- **Never prune orphaned favourites** on reload; the provider may restore the
  channel tomorrow.
- **Favourites-only keeps grouping.** A search answers *"where is X"* and so
  flattens the list; favourites-only is a **browse** mode. Only the search
  suspends grouping (and only then does the group mark drop to quiet ink).

### 10.4 Rows — no reorder, no delete

- **No `≡` grip, no drag, no up/down** (owner): the order is the provider's.
- **No per-row bin** (owner). The only row action is the favourite bookmark.
- Anatomy: `[chevron if playing] · name · channel no. · favourite`.
- The channel number rides the local list's **duration** slot — live duration is
  `-1`, so the slot is free. **No `tvg-chno` → the slot stays empty**, never `0`,
  never the word "LIVE".
- Click a row = play that channel. Hover wash and the now-row treatment are
  §4.3's, unchanged.

### 10.5 Grouping and the accordion

- **Flat** → one plain list.
- **Category / language / country** → collapsible heads, **accordion: exactly
  one group open at a time** (owner).
- **All collapsed by default; only the playing channel's group is open**
  (owner). With **nothing playing, nothing is open** — an all-collapsed list is
  the map of the playlist, which is the point of grouping. *(This overrides the
  preview's earlier "open the first group".)*
- **An auto-advance must not steal the view** *(default)*: the open group
  follows the playing channel **only while the open group is already the
  playing one**. Deliberately opening "Movies" while News plays must survive an
  advance inside News (follow.md — never fight the user).
- **Collapsing a group above the viewport must not yank the list** — compensate
  the scroll offset so rows under the cursor stay put.
- **Sticky group head** while a long group is scrolled *(default)*.
- Empty groups vanish under a filter; the head count reflects what is shown.

### 10.6 Keeping the playing channel visible

§4.3's reveal rule applies, plus the two cases the accordion creates:

- **The playing channel sits inside a COLLAPSED group** → its group head
  carries the play chevron, so "where am I" survives the accordion.
- **The playing row is scrolled off-screen** *(default, innovative)* → a small
  quiet chevron fades in at the list edge it is hiding behind, pointing toward
  it; click = expand its group if needed, then reveal. It exists only while the
  signal is actually lost, costs no permanent control and no words. At 12 000
  channels this matters far more than at 14 files.

### 10.7 Title bar

The title bar shows the **playing channel's name**, exactly as local files show
their file name. One rule to lock: **the playlist's display name wins — mpv's
ICY / HLS stream metadata must never overwrite it**, or the title flickers
between "BBC News HD" and whatever the stream announces mid-programme.

### 10.8 A dead channel is skipped, not sat on (owner, 2026-09-06 — **reverses the earlier M3**)

**Earlier decision (superseded):** "stay on the dead channel, never auto-advance."
**Owner's final call:** *"toast will say failed to load, then auto advance to the
next and play that. The user shouldn't have to keep clicking next on failing
channels — and they can see in the title bar what is playing."* Correct: with a
50 000-channel provider list, dead entries are routine, and making the viewer
hand-click past each one is the worse failure mode. The title bar (M22) is what
makes the skip safe — you always know where you landed.

**The behaviour**

1. A channel fails to load → the toast reads **"Failed to load"** with the
   channel's name, in the deck's existing card shape (the same slot that already
   names the item on Next).
2. SALU immediately opens the **next channel in list order** and plays it.
3. The title bar and the panel's now-row follow, so the viewer sees where the
   skip landed.

**10.8a-i Why SALU drives the advance, not mpv** *(this is not a preference)*

The owner's instinct — *"if it's native mpv, why not use it"* — is right in
spirit and impossible in this mode. **mpv's native advance only works if mpv is
holding the playlist**, and M40 forbids exactly that: handing mpv 50 000 entries
costs ~1 s per `playlist-pos` change at 40 k and ~2 s at 80 k (mpv#6162). Using
native advance would trade a 2-second stall on *every* channel change for a few
lines of Dart.

SALU gets the identical behaviour for free, because the hook already exists:
`player.stream.error` is **already subscribed** (`player_service.dart:267`, it
currently only `debugPrint`s). In channel mode that listener fires the toast and
calls the next channel. Same outcome, no engine list, no stall.

**10.8a-ii The cascade guard — mandatory** *(default)*

Auto-advance creates a failure mode the old "stay put" rule did not have: when a
provider's credentials expire **every** channel fails, so a naive advance
stampedes the whole 50 000-entry list, firing a toast per channel and hammering
the network, with no way for the viewer to catch it.

- **Stop after 3 consecutive failures.** Three in a row is not a dead channel,
  it is a dead provider (expired credentials, no internet, wrong URL). SALU stops
  on the third, leaves the toast up, and waits — that is where the *original*
  "stay put" instinct genuinely belongs.
- The counter **resets on any successful playback** and on **any manual channel
  pick** (row click, Prev/Next) — a deliberate choice is never treated as part
  of a cascade.
- **Do not wrap at the end of the list.** If the tail fails, stop; wrapping to
  index 0 risks a silent loop.
- Skipping is **failure-only**. A live channel never "ends", so `completed` is
  not an advance trigger in channel mode.

### 10.8a The chrome during live playback (owner, 2026-09-06)

A live channel has no duration (`#EXTINF:-1`), so there is no position to draw
and nothing to seek. **SALU already has this exact state** — Stop, per
`outline_transport_osd_resume.md` §2: *"zero the timeline (`00:00:00 /
00:00:00`, inert) · hide the bottom progress hairline"*. Live playback reuses
it rather than inventing a second "nothing to show" look.

| Element | Live behaviour |
|---|---|
| **Timeline (Row 1)** | **Stays exactly where it is, at its exact size** — hard rule 5 forbids hiding it (the container never shifts). It keeps its track and loses everything that encodes a position: no fill, no thumb, no left/middle/right readouts, no minute ticks, no hover chip. **An empty track already says "there is no position here."** |
| Timeline input | Inert — click, press-drag and wheel all do nothing. |
| **Greying it out** | **Rejected.** Dimming is SALU's *disabled-icon* language (follow.md §2); a greyed 23 px slab reads as broken chrome, not as live TV. |
| **Hiding it** | **Rejected** — hard rule 5. |
| **Bottom progress hairline** | **Carries the same shimmer** while the chrome is auto-hidden — see §10.8c. (It is still hidden while stopped or idle, exactly as today.) |
| **Seek backward / forward marks** | **Dimmed** — the same `enabled: false` Stop already applies to them. |
| **← / → keys** | **Silent.** A live key behind a dimmed button is worse than either alone: the marks say "not available" while the keyboard disagrees. |
| Play / Pause · Stop · sound group · volume bar | Unchanged. |

**The live shimmer** *(default — vetoable; the plain inert track alone is also
correct)*. The empty track is not wasted: a **slow, very quiet shimmer drifting
left → right along it** is SALU's own "live, no timeline" signal. It reads as
*flowing* rather than *broken*; it needs no text, no red dot and no "LIVE"
badge (rules 1 and 6 forbid all three); and because it is driven by the arrival
of data it **stops when the stream stalls** — so buffering gets an honest,
wordless indicator for free. Amplitude stays under the volume bar's hover
brightening: this is a status, not a control.

### 10.8b Transport in m3u mode (owner, 2026-09-06)

Everything here already exists; m3u mode only changes *which* rules apply.

| Action | m3u behaviour |
|---|---|
| **Play / Pause** | Works. OSD deck cards exactly as local. |
| **Stop** | Identical to local: playback stops, the canvas returns to the **initial SALU window** (logo, title bar reads `SALU`), and **the channel list stays loaded, parked on the same channel** — Stop ≠ Start Over. The panel keeps showing the list; the parked channel keeps the now-row highlight. |
| **Previous / Next** | Walk the **channel list**. Dimmed when the list holds a single channel, exactly as local dims them with one item. |
| **Seek ± (marks and keys)** | Dimmed and silent — §10.8a. |
| **Volume / Mute** | Unchanged, OSD cards unchanged. |
| **Failed channel** | The existing toast reads **"Failed to load"** + the channel name, then SALU **advances to the next channel and plays it** (§10.8). No new surface, no dialog. Three consecutive failures stop the cascade. |

**Previous / Next follow list order, never the visible order** (owner agreed,
2026-09-06). With
the accordion open on "Movies" while a News channel plays, Next plays the next
channel **in the list**, not the next visible row. Browsing must never change
what Next does — the same principle as §5's "shuffle never reorders the visible
list". If Next lands in a collapsed group, §10.5's accordion rule opens it and
§10.6 reveals the row.

**Previous's 3-second rule does not apply** (owner agreed, 2026-09-06). Locally, Previous restarts the
current item when the position is past 3 s. A live stream has no position to
restart from, so in m3u mode **Previous always moves to the previous channel**.

### 10.8c The hairline carries the live signal too (owner, 2026-09-06)

The owner's extension of §10.8a: *"we may also use the bottom thin line for the
same purpose if chrome is autohide."* Correct — and it repairs an element that
is currently **dead** in this state.

**The bug it fixes.** `_AutoHideProgress` (`home_screen.dart`) draws
`width: w * frac`, and `frac` falls back to `0.0` when
`duration <= Duration.zero`. A live stream has no duration, so today, with the
chrome auto-hidden, the hairline is **visible and draws nothing** — a 2 px strip
of pure background. It passes its own visibility test (`playing` → `true`) and
then renders emptiness. The shimmer gives it the only honest thing it can say.

| | Local file | **Live channel** |
|---|---|---|
| Hairline content | fill from the left = position | **the §10.8a shimmer**, drifting left → right |
| While buffering / stalled | n/a | the drift **stops** — same wordless signal as the timeline |
| Stopped / idle | hidden (unchanged) | hidden (unchanged) |

**The two surfaces never appear together.** The hairline exists *only* while the
chrome is hidden, and the timeline only while it is shown, so the live signal
**hands off** between them and is never duplicated. That is the whole value:
with the chrome auto-hidden over a live channel, the shimmer is the only thing
on screen still reporting that data is arriving.

- **The hairline's shimmer must be brighter than the timeline's** *(default)*:
  2 px of height needs far more contrast than a 23 px bar to read at all. The
  bar's highlight sits near `rgba(255,255,255,.11)`, the hairline's near `.55`.
- Everything else about the hairline is unchanged: 2 px, window bottom, the
  180 ms fade, and **strictly display-only** — the existing `Listener` that
  absorbs pointer events stays, so it can never be clicked, dragged, scrolled
  or hovered for a tooltip (it must not become a seek surface by accident).
- Same source of truth as the timeline: one "live and receiving" flag drives
  both, so they can never disagree.

### 10.9 Search, clear, undock in m3u mode

- **Search matches name + group, never the URL** — matching the URL would
  surface credentials. Precompute one lowercase key per channel at parse time;
  never `toLowerCase()` 12 000 strings per keystroke.
- **The count needs room:** `9 / 14` fits, `1284 / 12750` is eleven characters
  at 10 px. In m3u mode §4.4's collapsing-field escape hatch stops being
  optional.
- **The bin unloads the channels only.** Playback stops, the list empties, SALU
  returns to the logo canvas — and the **saved URL seven (`UrlLibraryService`)
  is untouched**, as is the favourites store. 5 s Undo restores **from an
  in-memory snapshot, never a re-fetch**: an Undo that stalls 10 s on a slow
  provider is not an Undo.
- **Undock:** §4.8's "one snapshot per change" contract does not survive 12 000
  channels crossing an isolate. Send the list **once**, then deltas only (index,
  favourites, mode, filter). Phase 8's WebSocket has the identical problem, so
  the `PlaylistBridge` must be delta-shaped from the start.

### 10.10 Performance — 50 000 channels, and why there is no cap

**Decision: no channel cap. The cap was the wrong answer to the right worry.**
A cap only converts "slow" into "refused", and the owner's requirement is
*"nothing but keep changing channels and keep viewing"*. Measured on a
generated **50 000-channel, 12.9 MB** playlist with the real attribute set
(`tvg-id`, `tvg-name`, `tvg-logo`, `tvg-language`, `tvg-country`, `tvg-chno`,
`group-title`):

| Work | Cost at 50 000 |
|---|---|
| Parse the whole file | **149 ms** |
| First 200 rows ready to paint | **0.9 ms** |
| Build the grouping index | **8.9 ms** |
| Precomputed search keys | 18.6 ms |
| One keystroke, worst case (full rescan) | **3.5 ms** — inside one 60 Hz frame |
| Naive search (`toLowerCase` per row per keystroke) | 40.8 ms — **a dropped frame; banned** |

Parsing is not the problem. **The engine is.**

#### 10.10a The real bottleneck — never hand mpv the whole list

`_openQueueAt` (`player_service.dart:371`) builds a `List<Media>` for the
**entire** queue and calls `player.open(Playlist(medias, index:))` — and every
channel change goes through it (`next()` :547, `previous()` :537, a row click).
At 50 000 channels that is a 50 000-entry playlist handed across the Dart→mpv
boundary **on every zap**, which mpv is documented to handle badly:
`playlist-pos` changes cost **~1 s at 40 000 entries and ~2 s at 80 000**
(mpv-player/mpv#6162), with a further regression reported at 200 000 (#15264).
Local playback never exposed this because a folder queue is tens of items.

**The rule: in channel-list mode the engine holds ONE media, never the list.**

- SALU owns the list (`List<QueueItem>`, §10.0) and is the only thing that
  knows about channels 0…49 999.
- A channel change opens **just that channel's URL**. Measured cost of the
  rebuild we are deleting: 2.7 ms of Dart allocation and ~1.6 MB of garbage per
  zap — before mpv's own per-entry cost, which is the part that actually hurts.
- Nothing is lost: the advance that matters in this mode is the **failure skip**
  (§10.8), and SALU drives it from `stream.error` rather than from mpv's
  playlist — which is what makes holding one media possible. Live streams
  have no resume memory to carry (`resume_service.dart:92` skips anything with
  `://`). Those were the only two reasons `_openQueueAt` handed over the whole
  list.
- Local mode is untouched — it keeps handing mpv the full queue, keeping native
  gapless advance and `Media(start:)` resume exactly as they are today.

#### 10.10b Progressive load — the list is usable in ~1 ms

Parse on a background isolate and stream the result: **the first ~200 rows are
ready in 0.9 ms**, the remaining 49 800 arrive 149 ms later. The user sees a
populated, scrollable, clickable list effectively instantly; the tail lands
before they can reach it. No spinner is needed for a 149 ms job — and per rule 1
there is no text to show anyway.

- **The wordless loading state** (§10.9) is therefore only for the **network
  fetch** of a 12.9 MB file, which is the genuinely slow part and entirely
  outside SALU's control. Reuse the live shimmer of §10.8a: the timeline is
  already inert with nothing to report, and a drifting shimmer during the
  download says "working" with no words and no new vocabulary.
- **Play before the parse finishes.** If the user clicks a channel while the
  tail is still arriving, it plays immediately — SALU only needs that one URL.
- **If the fetch itself fails** (bad URL, dead provider, past the M46 byte
  ceiling): the shimmer stops and the same toast wording is used —
  **"Failed to load"** with the playlist's name, never its URL (§10.10e). SALU
  returns to whatever it was doing; a failed *playlist* load is not a failed
  channel and must not trigger the M3b skip.

#### 10.10c The three rules that keep 50 000 rows fluid

1. **`ListView.builder` only** — never a mapped child list. The row count is the
   only thing that scales; built rows stay proportional to the viewport.
2. **Precompute one lowercase search key per channel at parse time**
   (`name + group`). 18.6 ms once, versus 40.8 ms *per keystroke* naively.
   Narrowing the previous result while the term grows costs 10.1 ms across five
   keystrokes.
3. **Intern the low-cardinality fields** (`group`, `language`, `country`). A
   50 000-channel list holds ~28 unique values across those three fields; without
   interning it holds 150 000 separate strings. This is what makes the grouping
   index cheap enough to rebuild on a mode switch (8.9 ms) instead of caching
   four of them.

Also: the grouping index is rebuilt in SALU only — **switching group mode never
touches the engine**, so it cannot interrupt playback.

#### 10.10d Where a limit does belong

Not on channels — on the **download**. A hostile or mistyped URL can stream
gigabytes. Abort the fetch past a generous byte ceiling *(default: 64 MB, ~5×
the 12.9 MB measured at 50 000 channels)* and treat it as a failed load, using
the same toast a failed channel uses (M37). That bounds the real risk without
ever telling a legitimate 50 000-channel user "no".

### 10.10e Privacy

- **Never render a playlist URL** in a row, tooltip, title bar, OSD card or log
  — they carry credentials.
- Search matches name and group only, never the URL (§10.9) — otherwise a
  typed token could surface a credential as a "match".

### 10.11 Out of scope, explicitly

`tvg-logo` (colour art per row fights rule 6, plus thousands of fetches),
EPG / `tvg-id` guide data, catch-up, Xtream APIs, editing or saving a modified
m3u, and per-channel resume (`resume_service.dart:92` already skips anything
containing `://`).

### 10.12 Build steps — m3u mode (each leaves the app runnable)

m3u mode is **its own phase, built after steps 1–13 of §7**. The docked local
panel must work first; this phase then adds the channel-list behaviour behind
it. Do not interleave them.

| # | Step | Leaves the app |
|---|---|---|
| **M-1** | **`QueueItem` + `QueueService`** (§10.0). Turn `paths` into `List<QueueItem>`, keep `List<String> get paths` as the transitional getter so the 6 existing read sites compile untouched. Add `isChannelList`. | identical behaviour, local only |
| **M-2** | **The parser** — fetch, `#EXTINF` attribute regex, display name after the comma, intern group/language/country (M44), precompute the lowercase search key (M43), byte ceiling (M46). **Off the UI isolate.** Pure Dart, unit-testable with no UI. | unused, but tested |
| **M-3** | **Route m3u URLs to the parser** instead of to mpv (`open_media_service.playUrl`). Build the queue from the parsed channels. Fix the index mirror, which is gated on `paths.length == medias.length` (`player_service.dart:177`). | m3u loads, plain list, no grouping |
| **M-4** | **The engine path (M40)** — in channel mode `_openQueueAt` opens **one** media, never the list. Local mode keeps the existing full-queue path untouched. | channel changes are constant-time |
| **M-4b** | **Failure skip (§10.8)** — extend the existing `stream.error` listener (`player_service.dart:267`, currently a `debugPrint`): toast "Failed to load" + name, advance to the next channel, and enforce the 3-strike cascade guard. | dead channels self-skip |
| **M-5** | **Title bar + rows** — channel name (M22), channel number in the duration slot, no grip, no bin, favourite only (M14/M15). | list is usable |
| **M-6** | **Favourites** — the store keyed by host → `tvg-id`/`tvg-name`/name (M11/M12), debounced writes, the filter toggle, hover-vs-filled visibility (M10). | favourites work |
| **M-7** | **Grouping + accordion** — the group index, the four modes, auto-pick (M6), the pill, dimming unavailable modes, the accordion rules of §10.5, sticky heads. | grouping works |
| **M-8** | **Reveal** — chevron on a collapsed playing group, the off-screen edge chevron (§10.6). | never lose the playing channel |
| **M-9** | **Live chrome** — the inert timeline, the shimmer, the hairline handoff, dimmed+silent seek, Prev/Next rules (§10.8a–c). | live playback reads correctly |
| **M-10** | **Progressive load** (M41) + the fetch shimmer (M42) + the failed-channel toast (M37). | 50 000 channels feel instant |
| **M-11** | **Docs** — flip this section's status, update `follow.md` §1.6 with any new marks, README phase table. | shipped |

**Two traps, both already paid for once in §5:** every action must act on the
**real** channel list, never on the filtered view; and the group index is a view
over the list, so a mode switch must never touch the engine (M45).

### 10.13 Acceptance checklist — m3u mode

1. Load an m3u URL → the panel lists **channels**, not one row named after the
   playlist file.
2. Title bar reads the channel's display name, never `1234` from the stream URL,
   and never flickers to ICY metadata mid-programme.
3. Header slots 1–2 are **group-by** and **favourite**; repeat and shuffle are
   **absent**. Load a local folder → repeat and shuffle are back, unchanged.
4. Header pitch: the field's ✕ is nowhere near the bin. `[group·fav] 14
   [search] 14 [bin] 14 [undock]`.
5. Group-by opens a pill with four modes, the active one glowing; the mark
   itself never changes shape. A playlist carrying only `group-title` dims
   language and country instead of hiding them.
6. Category keeps the provider's first-appearance order; language and country
   are alphabetical; `Uncategorized` is last.
7. All groups collapsed by default, only the playing channel's group open. With
   nothing playing, **nothing** is open.
8. Exactly one group open at a time; opening another closes the first.
9. Open "Movies" while a News channel plays, let it advance → **Movies stays
   open** and the News group head carries the chevron.
10. Collapse a group above the viewport → the rows under the cursor do not jump.
11. Scroll the playing channel off screen → an edge chevron fades in; click it →
    the group expands if needed and the row is revealed.
12. Favourite a channel → filled bookmark, always visible. Non-favourites show
    the bookmark **only on hover**.
13. Reload the same playlist → favourites are still there. Reload it after the
    provider rotates the credentials in the URL → **still there** (host key).
14. Favourites-only **keeps** the group heads; a search **flattens** them and
    the group mark drops to quiet ink. Clearing the search restores both.
15. Search matches name and group, never the URL. No credential can ever appear
    as a match.
16. Rows have no grip and no bin; drag does nothing; the only row action is the
    bookmark.
17. Channel number sits in the duration slot; a channel with no `tvg-chno`
    leaves it **empty** — never `0`, never "LIVE".
18. While a live channel plays: the timeline is **present, full size, empty and
    inert** — no fill, no thumb, no readouts, no hover chip, and clicking or
    dragging it does nothing.
19. The shimmer drifts while data arrives and **stops** when the stream stalls.
20. Auto-hide the chrome → the hairline carries the same shimmer. Bring the
    chrome back → the hairline goes, the timeline resumes it. **Never both.**
21. Seek marks are dimmed **and** ← → do nothing.
22. Stop → logo canvas, title `SALU`, and the channel list stays loaded on the
    same channel. Play → that channel plays again.
23. Prev/Next walk the channel list even when the accordion shows another group;
    with one channel they dim. Previous always steps back a channel — it never
    "restarts" a live stream.
24. A channel that fails shows **"Failed to load"** + its name, then SALU
    **plays the next channel**; the title bar and now-row follow it.
24b. Point the playlist at expired credentials so every channel fails → SALU
    stops after **3** consecutive failures instead of stampeding the list. Click
    a working channel → the counter resets and skipping works again.
24c. Let the **last** channel in the list fail → SALU stops; it does not wrap
    around to index 0.
25. Bin → channels unload, logo canvas. The **saved URL seven and the favourites
    store are untouched**. Undo restores instantly (no re-fetch).
26. A 50 000-channel playlist: rows appear almost immediately, the panel scrolls
    smoothly, typing does not stutter, and switching group mode does not
    interrupt playback.
27. Click a channel while the tail of a big playlist is still parsing → it plays
    immediately.
28. No instruction text, no placeholder, no "LIVE" badge, no red dot, no
    spinner, no confirmation dialog anywhere in m3u mode.

### 10.14 Decision record — m3u

| # | Decision | Value | Chosen by |
|---|---|---|---|
| M1 | Header slots 1–2 swap with the source | group-by · favourite | **owner** |
| M2 | Repeat & shuffle | **dropped** in m3u mode | **owner**, 2026-09-06 |
| M3 | Dead channel | ~~stay on it, never auto-advance~~ → **REVERSED (M3b)** | superseded |
| M3b | Dead channel | toast **"Failed to load"** + name, then **auto-advance to the next channel and play it** — the viewer never hand-clicks past dead entries | **owner**, 2026-09-06, §10.8 |
| M3c | Who drives the skip | **SALU, off `stream.error`** — never mpv's native advance, which would require handing mpv the whole list and cost ~1–2 s per change (M40). The listener already exists at `player_service.dart:267` | forced by M40, §10.8a-i |
| M3d | Cascade guard | **stop after 3 consecutive failures**; reset on any success or manual pick; never wrap past the end of the list | default, §10.8a-ii |
| M3e | Skip trigger | **failure only** — `completed` never advances in channel mode (a live channel does not end) | default, §10.8a-ii |
| M4 | Group modes | flat · category · language · country | **owner** |
| M5 | Group-by UI | one stable mark + pill, never a morphing glyph | default, §10.2 |
| M6 | Group-by default | auto-pick from tag coverage, remembered per playlist | default, §10.2 |
| M7 | Missing-tag modes | dimmed, not hidden | default, §10.2 |
| M8 | Multi-value tags | not split this phase | default, §10.2 |
| M9 | Favourite mark | bookmark, not star | default, §10.3 |
| M10 | Row bookmark visibility | filled+visible when favourite; hover-only when not | default, §10.3 |
| M11 | Channel key | `tvg-id` → `tvg-name` → name | default, §10.3 |
| M12 | Playlist key | **host**, not full URL | default, §10.3 |
| M13 | Favourites + grouping | favourites keep groups; only search flattens | default, §10.3 |
| M14 | Rows | no drag, no reorder, no per-row delete | **owner** |
| M15 | Row action | favourite only | **owner** |
| M16 | Channel number | in the duration slot; empty when absent | default, §10.4 |
| M17 | Accordion | one group open; all collapsed by default; playing group open | **owner** |
| M18 | Nothing playing | nothing open | default, §10.5 |
| M19 | Auto-advance vs the open group | the view is not stolen | default, §10.5 |
| M20 | Playing channel in a collapsed group | chevron on the group head | default, §10.6 |
| M21 | Playing row off-screen | edge chevron, click = reveal | default, §10.6 |
| M22 | Title bar | channel name; playlist name beats stream metadata | **owner** + default |
| M23 | Search scope | name + group, never the URL | default, §10.9 |
| M24 | Bin | unloads channels only; saved seven and favourites survive | default, §10.9 |
| M25 | Undo | in-memory snapshot, never a re-fetch | default, §10.9 |
| M26 | Bridge | delta-shaped, not snapshot-per-change | default, §10.9 |
| M27 | Parser | SALU parses the m3u; mpv gets resolved URLs | forced by §10.0 |
| M28 | Data model | **one `List<QueueItem>`** — the parallel metadata list is **rejected** (desync across 9 call sites; a source switch would rebuild two collections) | **owner** (challenge) + §10.0 |
| M29 | Timeline when live | stays, exact size, **inert and empty** — never hidden (rule 5), never greyed (that is icon-disabled language) | **owner** (raised) + default, §10.8a |
| M30 | Live shimmer | slow quiet left→right drift on the empty track; stops when the stream stalls = free buffering signal | default, §10.8a |
| M31 | Bottom hairline when live | **carries the same shimmer** while the chrome is auto-hidden — the two surfaces hand off and never both show; fixes a hairline that currently renders empty on live (`frac = 0`) | **owner**, 2026-09-06, §10.8c |
| M31b | Hairline shimmer contrast | brighter than the bar's (~`.55` vs `.11`) — 2 px needs it | default, §10.8c |
| M31c | Hairline stays display-only | the existing pointer-absorbing `Listener` stays; never a seek surface | default, §10.8c |
| M32 | Seek marks + ← → keys | dimmed **and** silent | **owner**, 2026-09-06 |
| M33 | Stop in m3u | canvas → initial state; **channel list stays parked on the same channel** | **owner**, 2026-09-06 |
| M34 | Previous / Next | walk the channel list; dim at a single channel | **owner**, 2026-09-06 |
| M35 | Prev/Next order | **list order, never the visible order** — browsing must not change what Next does | **owner agreed**, 2026-09-06, §10.8b |
| M36 | Previous's 3 s restart rule | does not apply live — Previous always steps back a channel | **owner agreed**, 2026-09-06, §10.8b |
| M37 | Failed-channel toast | the existing card shape, wording **"Failed to load"** + the channel name (a toast may carry words; follow.md §1.6 allows it — controls may not) | **owner**, 2026-09-06 |
| M38 | Volume / mute OSD | unchanged from local | **owner**, 2026-09-06 |
| M39 | **Channel cap** | **none** — a cap turns "slow" into "refused"; 50 000 parses in 149 ms | **owner** ("stay responsive at 50k"), §10.10 |
| M40 | **Engine holds ONE media in channel mode** | never hand mpv the list — `playlist-pos` costs ~1 s at 40k, ~2 s at 80k (mpv#6162). Local mode keeps the full-queue path | forced by §10.10a |
| M41 | Progressive load | first ~200 rows at 0.9 ms, tail at 149 ms; a channel is playable before the parse ends | default, §10.10b |
| M42 | Loading state | only for the network fetch; reuse the §10.8a shimmer, no spinner, no words | default, §10.10b |
| M43 | Search keys | precomputed at parse time; narrowing while typing. Naive per-keystroke lowercasing is **banned** (40.8 ms = dropped frame) | default, §10.10c |
| M44 | String interning | intern group / language / country — 28 unique values instead of 150 000 strings | default, §10.10c |
| M45 | Group-mode switch | re-index in SALU only, never an engine call — cannot interrupt playback | default, §10.10c |
| M46 | Download ceiling | abort past ~64 MB and fail with the M37 toast — the limit belongs on bytes, not channels | default, §10.10d |

---

Rejected on the way (recorded so they are not re-proposed silently): Queue Rail
and its hinged/mirrored variants, Bead Queue, Panel Hinge (rect + divider —
one hollow rounded rect away from `□` Stop), right-edge placement (options A
and C), "bead = something is queued", full-height panels, **docking the video**
(rescales the picture on every toggle and the chrome cannot follow), any
scale-on-enter motion for the panel (edge-anchored surfaces slide, they do not
grow), **the four-tab strip inside this panel** (owner's change of plan), a
numeral "1" inside the repeat loop (text on a control, rules 1 & 6), a
placeholder string in the search field, `player.setShuffle` (it desyncs mpv's
order from `QueueService`), centring the playing row on every advance (long jumps
on a 40-file queue), **a footer of any kind** — including the append `+` and the
count that first lived there, **the platform/Material scrollbar**, letting
repeat-one and shuffle both answer "what plays next", and deferring undock to a
later phase (the owner wants it built with the playlist).
