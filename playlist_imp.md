# Playlist control & slide-out panel — implementation brief

> **Status:** **Phase A complete (owner-confirmed); Phase B NOT IMPLEMENTED**
> (updated 2026-09-08). Phase A is the local playlist — §§1–9, §7 steps 1–12.
> Phase B is §10 (m3u / IPTV channel mode). **Points 1–12 are FINAL design
> decisions** (2026-09-08): failed-channel handling (§10.8); live chrome with a
> **still soft light, no moving shimmer** (§10.8a, option A); large-list
> performance with no cap, 64 MB ceiling and progressive `m3u_xmltv` parsing
> (§10.10); clear/Undo/privacy (§10.9, §10.10e); and the §10.13 checklist +
> status/README/mark docs (§10.12 M-11). Scope clarifications M55–M57
> (2026-09-08, §10.12): local `.m3u` files use the same parser, frontier
> Prev/Next parks, and radio needs no separate path. **Points 5 and 6 must be
> implemented exactly as the approved grouping/favourites preview (§10.15)**,
> including Flat on load and the same-file missing-category fallback. None of
> this marks Phase B production code as implemented. Build order stays local first.
> Point 2 now includes RAM-only queue storage and provider logos **instead of
> channel numbers**; the search field shows only the total channel count.
>
> **New session? Read this box, then §1.** Two owner reversals of the
> 2026-09-06 draft are already recorded in the body — do not re-introduce
> them:
> - **Undock / dock is REMOVED.** SALU stays a single surface. Header slot 5
>   is a **Close ✕** that closes the playlist panel (§4.4, §4.8). No loose
>   window, no `desktop_multi_window`, no `PlaylistBridge` — none of that
>   will be implemented.
> - **A local file load starts at the top.** When local files are loaded,
>   playback starts from the **first file of the playlist the panel is
>   showing** — row 0 of the sorted, shown list (§1 decision 5). **One
>   sanctioned exception (owner, 2026-09-07):** a *folder auto-load*
>   trigger (`autoload_imp.md`, Phase B — shipped) starts at the picked
>   file's natural folder row instead; do not "fix" that back.
>
> Phase A in brief: a playlist mark and toggle in the control row (§§2–3), a
> slide-out glass panel over the video (§4), queue/repeat/shuffle service work
> (§5) and silent keyboard (§6), built in §7's steps 1–12 and verified against
> §8's checklist. §10 in brief (the pending Phase B): the
> header's first two slots swap to group-by and favourite, repeat and shuffle
> are dropped, rows lose drag and delete, groups are an accordion, a dead
> channel toasts **"Failed to load"** and **skips to the next** (3 strikes stop
> the cascade), the timeline goes inert with a **still soft light** (no moving
> shimmer, §10.8a), and the engine
> holds one media instead of the whole list. §10.0's blocker stands: SALU
> currently hands the whole `.m3u` URL to mpv, so no channel metadata ever
> reaches the app; prepare the queue model first, then the parser, before
> building the channel UI.
>
> This is the binding spec for SALU's playlist control and its slide-out
> panel. Placement, mark and state semantics were chosen by the owner in the
> interactive study `design/playlist-mark-preview/index.html` (serve it with
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
| 5 | **Local load → start at the top** | Whenever local files are loaded (Open File… / Open Folder… / drop), the queue is ordered as the folder shows it (§5) and **playback starts from the first file of the playlist the panel is showing** — row 0 of the shown list. A fresh load never starts mid-list and never from a remembered position. |
| 6 | **Header slot 5** | **Close ✕** — closes the playlist panel (the same 220 ms reverse as the mark toggle · Esc · Ctrl+L). **Undock / dock is REMOVED** (owner, 2026-09-07) — there is no second window and nothing else lives in this slot (§4.4, §4.8). |

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

**4.4 Header row — five docked marks, no words** *(slots locked 2026-09-06; slot 5 changed to Close by the owner, 2026-09-07)*

The four-tab strip (Playlist · Video · Audio · Subtitles) is **removed** from
this panel. It is a playlist panel and nothing else. Where the Video / Audio /
Subtitle views live now is an open Phase 4 question — the control row's right
edge is still reserved for them (§1, decision 1), and they must not come back
as tabs on top of the queue.

The header appears **only when the queue is non-empty** (owner's rule),
so none of the five controls needs a dimmed state for "nothing to act
on". Left to right, in a 322 px panel
with 8/10 px padding and a hairline underneath:

| # | Control | Mark | States & tooltip |
|---|---|---|---|
| 1 | **Repeat** | the family's existing ¾-arc + arrowhead (`RestartMark`'s geometry) | cycles **off → all → one**. Off = the arc at the quiet 55 % ink (still hoverable) · all = full ink · one = full ink **plus a solid bead at the arc's centre** — never a numeral, rules 1 & 6. `active:` glow when not off. Tooltips "Repeat off / Repeat all / Repeat one" (the Mute/Unmute precedent) |
| 2 | **Shuffle** | two crossing rules with arrowheads at their right ends | on/off toggle, glow when on, tooltip "Shuffle". Must cross and carry heads so it can never be read as the transport's `<<` / `>>` |
| 3 | **Search** | thin glass field, radius 14 · inside it, left to right: **magnifier mark · the typed text · the count · ✕ (only while there is text)** | no placeholder text (rule 1) — the magnifier and the tooltip name it. Takes the remaining width. The count is part of the field, not a footer (§4.5) |
| 4 | **Clear playlist** | `TrashMark` | **absolute**: playback stops, the queue empties, SALU returns to its initial state (the logo canvas). Instant, no confirmation, 5 s **Undo** toast (rule 3) — see §5 |
| 5 | **Close** | `✕` — the same cross the plus already rotates into | closes the playlist panel: the 220 ms reverse slide/fade, glow off, exactly as the mark toggle · Esc · Ctrl+L. Tooltip "Close playlist". It only closes the *view* — the queue and playback are untouched; the control-row mark reopens the panel. |

Header space math: four 30 px marks + gaps ≈ 128 px, leaving ~174 px for the field —
and the field now has to hold the magnifier (~20 px), the count (~28 px) and the
✕ (~20 px) as well, so typed text gets ~100 px. Tight but workable, and removing
the footer is what keeps it that way. **Escape hatch if it ever feels cramped:**
a collapsing field — at rest just the magnifier mark, expanding into the field on
click. Recorded, not built pre-emptively.

**The panel has exactly two zones: the header and the rows.** No footer, no tab
strip, no title, no section labels (rules 1 and 6).

Marks this needs: **two new drawings** (shuffle, magnifier). Everything else is
reused: the loop arc from `RestartMark`, the ✕ the plus already rotates into,
`TrashMark`, `PlusMark`.

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

**4.8 Undock / dock — REMOVED (owner, 2026-09-07)**

The earlier plan to let the playlist become its own draggable window is
**dropped**. SALU stays a single surface: the playlist lives only in the
docked panel, and the panel is closed with the header's **Close ✕** (§4.4,
slot 5) or the mark toggle / Esc / Ctrl+L. There will be **no** loose window,
no `desktop_multi_window` dependency, no `PlaylistBridge` seam, no §13a spike,
no amend to follow.md §8 — none of it will be implemented. The docked-space
math above is final.

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

- **The advance inherits the viewer's state; a deliberate step overrides it.**
  When an item ends while the viewer is PAUSED, the next one loads **paused**
  — the automatic answer never starts sound nobody asked for. A hand-pressed
  `|<<` / `>>|` or a **row click** does the opposite: it always plays, even
  from pause. One owner: `PlayerService.playsOnStep(StepIntent)` (see
  outline_transport_osd_resume.md · "The step rule").
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
  *"Does `|<<` restart THIS item?" has one owner:*
  `PlayerService.previousRestartsThisItem` — non-mutating (it peeks the
  heard-log through `QueueService.peekPreviousHeard`), read both by
  `previous()` itself and by the OSD card, so the action and the card can
  never disagree. With shuffle on and an **empty** heard-log there is
  nothing heard before, so the 3-second rule answers — the item restarts
  and the card reads `00:00:00`.
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

---

## 7. Steps — Phase A, local playlist only (each leaves the app runnable)

Undock was removed (2026-09-07, §4.8), so Phase A is **steps 1–12 of this
list** — there is no step 13. Steps 4 and 5 carry the owner's start-at-the-top
rule (§1, decision 5): loading local files always begins playback from the
first file of the playlist the panel is showing.

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
   hover wash. **Playback starts at the top**: when local files are loaded
   (Open File… / Open Folder… / drop), the fresh queue plays from row 0 — the
   first file of the list the panel shows — never from the middle of the list
   and never from a remembered position (§1 decision 5; ordering rule in §5).
5. **Row actions** — 🗑 remove + 5 s Undo toast; `≡` drag reorder via
   `ReorderableListView` (or a manual drag) + `player.move`. No up/down buttons.
   (A drag/reorder is a *deliberate* change, so it keeps whatever is playing;
   the start-at-the-top rule applies to fresh loads only, §1 decision 5.)
6. **Auto-scroll** — the reveal rule of §4.3: jump on entrance, 220–300 ms
   animated afterwards, shortest distance, only when required, suppressed for
   ~3 s after a manual scroll.
7. **Header row** — repeat (off/all/one, bead for "one"), shuffle, the search
   field with the count inside it, clear playlist, and the **Close ✕** slot.
   Two new marks to draw: shuffle, magnifier. Header
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
    panel-hit-test branch, including while the panel is empty). A fresh drop
    batch that replaces the queue also plays from its row 0 (§1 decision 5).
11. **Polish** — empty states, **SALU's own dark scrollbar** (§4.3, overriding
    Flutter's desktop Material scrollbar), Esc/Ctrl+L, glow on `active`, motion
    timings, and a pass over R2/R3 (pill coexistence, glow visibility from a
    distance).
12. **Docs** — README phase table (Phase 4 → in progress), add the new marks to
    `follow.md` §1.6's family list, and record Phase A as
    *FINAL & IMPLEMENTED* with the date and commit. Keep Phase B's separate
    implementation status honest; a finalized design is not shipped code.

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
13b. Load a folder of 40 files → the queue reads 1…40 top to bottom and playback
    starts from the **first file** (row 0) — never mid-list, never from a
    remembered position. The same holds for Open File… and for a drop that
    replaces the queue. Reordering rows later does not restart playback.
14. While the panel is open the picture does **not** rescale, the chrome does not
    shift, and the timeline's readouts stay where they were.
15. Click the mark mid-slide → the panel reverses from where it is, it does not
    restart or jump.
16. The header appears **only** once something is queued; with an empty
    queue the panel is the ghost mark and nothing else — no header, no
    footer — and the canvas is back to its initial state.
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
30. No ripples, no splashes, no filled box or pill behind any icon, no instruction
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
| 19 | Header row | repeat · shuffle · search · clear playlist · **Close ✕**, left to right, marks only (slot 5 changed from undock/dock to Close, 2026-09-07) | **owner**, 2026-09-06 (slots) · **owner**, 2026-09-07 (slot 5) |
| 19b | Header slot 5 | **Close ✕** — closes the playlist panel (220 ms reverse · glow off · queue and playback untouched); the control-row mark, Esc and Ctrl+L close it the same way | **owner**, 2026-09-07 |
| 20 | Header visibility | only while the queue is non-empty | **owner**, 2026-09-06 |
| 21 | Search field | magnifier inside-left · **count inside-right** · ✕ inside-right while there is text · no placeholder · **filters the view only** | **owner**, 2026-09-06 |
| 21b | Footer | **none** — the panel is header + rows; no append button (files arrive via the Open control or a drop) | **owner**, 2026-09-06 |
| 21c | Local batch order | the shell's array is never trusted: a drop/dialog batch is re-sorted into the folder's own order (natural, case-insensitive) and plays from that top row; blocks still only ever append | **owner** (bug: 8 files started at 6/7), §5 |
| 21d | Local load → start at the top | **when local files are loaded, playback starts from the first file of the playlist the panel is showing** — row 0 of the shown, sorted list; never mid-list, never from a remembered position. Only *fresh loads* start at the top — reordering rows is deliberate and never restarts playback | **owner**, 2026-09-07 |
| 22 | Repeat glyph | the family's loop arc · bead at its centre = repeat one · quiet ink = off · never a numeral | default, §4.4 |
| 23 | Focus | the search field is the only focusable thing in the panel; Esc precedence per §4.5 | default, §4.5 |
| 24 | Clear playlist | **absolute** — playback stops, queue empties, SALU returns to its initial state; 5 s Undo restores the queue *and* the position; resume memory and the saved seven untouched | **owner**, 2026-09-06 |
| 24b | Deleting the playing row | next → else previous → else initial state | **owner**, 2026-09-06 |
| 24c | Scrollbar | SALU's own thin dark thumb, transparent track, no arrows — never the Material/platform one | **owner** (catch) + default (spec), §4.3 |
| 24d | Shuffle & the view | shuffle never reorders the visible list; playback order only | **owner**, 2026-09-06 |
| 24e | Repeat × shuffle | the decision table of §5; repeat-one **suspends** shuffle (quiet ink, no glow) and the setting survives | default, §5 |
| 24f | Prev/Next during shuffle | follow the play-order history (what was heard), not the list | default, §5 |
| 25–26 | Undock / dock (draft rows 25, 25b, 25c, 26 of 2026-09-06) | **REMOVED — not implemented**: no loose window, no `desktop_multi_window` dependency, no `PlaylistBridge`, no step-13a spike, no follow.md §8 amendment. Header slot 5 is a **Close ✕** instead. Full record in §4.8 | **owner**, 2026-09-07 |
| 27 | Auto-scroll | only when required · shortest distance · jump on entrance · ~3 s suppression after a manual scroll | **owner** (behaviour) + default (numbers), §4.3 |
| 28 | Shuffle engine | SALU picks the next index off `stream.completed`; **never** `player.setShuffle` | default, §5 |
| 29 | Build order | **Phase A = §7's steps 1–12 only** (undock removed, so step 13 does not exist) — one feature, one branch, shipped together; Phase B (§10) comes later and is never interleaved | **owner**, 2026-09-07 |
| 30 | Video / Audio / Subtitles | **re-planned separately later** — nothing assumed, the row's right edge stays reserved and empty | **owner**, 2026-09-06 |

---

## 10. m3u mode — the IPTV playlist (owner's brief, 2026-09-06)

> **Status:** **PHASE B — NOT IMPLEMENTED** (updated 2026-09-08). The owner
> confirms Phase A — the local playlist (§§1–9, §7 steps 1–12) — is complete.
> **Points 1–12 are FINAL as design decisions, not production code.** The
> owner approved points 5 and 6 exactly as previewed (§10.15, 2026-09-08). This
> section replaces the earlier "out of scope: IPTV grouping … the owner takes
> that next". Everything in §§1–9 still governs; this section states only what
> **changes when the loaded playlist is an m3u URL**. Entries marked *(default)*
> may be vetoed. **Undock is removed** (2026-09-07, §4.8), so where this section
> referred to an undocked window the reference is void; there is one playlist
> surface, the docked panel, and header slot 5 is its **Close ✕** (local and m3u
> modes alike).

### Owner review status — 2026-09-08

These point numbers refer to the owner's plain-language review, **not** the
M-1…M-11 implementation steps. "Final" below means design approval only.

| Point | Review state | Decision |
|---|---|---|
| **1** | **FINAL** | SALU reads the M3U channel directory; mpv plays the selected stream (§10.0). |
| **2** | **FINAL** | One efficient RAM-only queue; ID-first/name-fallback identity; missing grouping information is `Unknown`; logos replace individual numbers; only the total count appears inside search (§§10.0, 10.4, 10.9). |
| **3** | **FINAL — owner, 2026-09-08** | mpv receives only the selected channel. Prev/Next follow the original channel list, never a grouped/filtered view. Stop keeps that list parked (§§10.8b, 10.10a). |
| **4** | **FINAL — owner, 2026-09-08** | Channel names and logos (no individual numbers), correct channel title; no row drag/delete; group-by/favourites replace repeat/shuffle (§§10.1, 10.4, 10.7). |
| **5** | **FINAL — owner, 2026-09-08; preview approved exactly** | Flat on every fresh load; category/language/country, the one-open-group accordion, dimmed unavailable modes, `Unknown` last and the same-file `group-title` → `#EXTGRP` fallback. Match the approved preview's appearance and interactions (§§10.2–10.2a, 10.5, 10.15). |
| **6** | **FINAL — owner, 2026-09-08; preview approved exactly** | Bookmark marks and hover/filled states, saved favourites across reloads/restarts, and favourites-only filtering that retains grouping. Match the approved preview's appearance and interactions (§§10.3, 10.15). |
| **7** | **FINAL — owner, 2026-09-08** | Search names/groups only; temporarily flatten groups; preserve the total-only count; collapsed-group and off-screen markers reveal the playing channel without overriding filters (§§10.6, 10.9). |
| **8 · failures** | **FINAL — owner, 2026-09-08** | “Failed to load” + channel name, then next channel; stop after 3 consecutive failures, never wrap past the last channel (§10.8). |
| **9 · live controls** | **FINAL — owner, 2026-09-08 (option A)** | Seek disabled, timeline visible but inert, and a **still soft light** — no moving shimmer — as the live/receiving indicator, fading quietly when the stream stalls; the bottom hairline carries the same still light (§§10.8a, 10.8c; preview `design/live-indicator-preview`). |
| **10 · large-list performance** | **FINAL — owner, 2026-09-08** | No channel cap; **64 MB download ceiling**; progressive load off the UI isolate and fluid scroll/search at 50 000. The `m3u_xmltv` adoption makes rows arrive *during* the download; §10.10's old whole-file timings are superseded and re-measured at M-10 (§10.10). |
| **11 · clear · undo · privacy** | **FINAL — owner, 2026-09-08** | Bin unloads channels only — the saved URL seven and the favourites store survive; Undo restores from an in-memory snapshot, never a re-fetch; credential-bearing URLs are never rendered, matched or logged (§§10.9, 10.10e, M24–M25). |
| **12 · testing · docs** | **FINAL — owner, 2026-09-08** | §10.13's acceptance checklist must pass and the implementation status, README phase table and mark docs are updated when Phase B ships (§10.12, M-11). |

### 10.0 The blocker — SALU must parse the m3u itself

Verified in the code (2026-09-06):

| Fact | Where |
|---|---|
| `playUrl` → `openPath(url)` → `setQueue([url], 0)` — the queue holds **one** entry: the m3u URL | `open_media_service.dart:74`, `player_service.dart:349` |
| mpv expands the playlist internally; SALU never sees the channels | `_openQueueAt` hands mpv one `Media` |
| The index mirror is gated on `queue.paths.length == playlist.medias.length` → `1 != 24`, so **it is skipped** and SALU never learns which channel plays | `player_service.dart:177` |
| `currentTitle` = `MediaUtils.displayName(uri)` → a stream URL `…/live/user/pass/1234.ts` titles the window **"1234"** | `player_service.dart:169` |

**Point 1 — FINAL (owner, 2026-09-08): SALU reads the channel directory;
mpv plays the selected channel.** This is design approval, **not an
implementation-complete mark**; Phase B implementation remains pending.

SALU fetches and parses the provider's M3U channel directory, keeping each
channel's available details and stream URL in SALU. mpv receives **only the
selected channel's URL**, never the whole channel list (§10.10a), and handles
streaming, buffering, decoding, video and audio playback. A channel's **HLS
`.m3u8` manifest of video segments stays mpv's responsibility** — SALU's parser
is for the channel directory, not the stream's segment playlist.

Without a parser SALU has no `group-title`, no `tvg-language`, no `tvg-country`,
no `tvg-logo` and no display name for its channel UI — i.e. none of
§§10.1–10.6 can exist. The parser is the first channel-loading dependency
(after the queue-model preparation in M-1); the channel UI comes after it.

**Point 2 — FINAL (owner, 2026-09-08): upgrade the queue, RAM only.**
Store channel identifiers, names, groups, languages, countries and **logo
addresses** alongside stream URLs in one in-memory queue, while keeping local
playlists working unchanged. **Channel numbers are removed from this phase**:
logos appear before channel names, and the **only channel count** is the total
inside the search field (§10.9). This is design approval; implementation is
still pending.

**Data model — one list of objects, no parallel metadata table, no manual mode
flag.** The earlier parallel `List<ChannelMeta>?` alongside `paths` was rejected
(owner, 2026-09-06): every reader and mutation would have to keep two lists in
lockstep. Keep an entry's details with its URL instead. The old draft's call-site
counts predate Phase A; migrate the current notifier-based callers, not those
historical counts.

```dart
/// One queue entry. Local files fill `url` only; m3u channels add details.
class QueueItem {
  const QueueItem(this.url, {this.name, this.tvgId, this.tvgName,
                             this.group, this.language, this.country,
                             this.logoUrl});
  final String url;        // what mpv receives; local mode only needs this
  final String? name;      // channel display label; null for local files
  final String? tvgId, tvgName;
  final String? group, language, country;
  final String? logoUrl;   // image address, NOT downloaded image bytes
}
```

- Local mode builds `QueueItem(path)` with every other field null. Natural
  ordering, canonical paths, resume, repeat/shuffle, queue mutations and Undo
  keep their Phase A behaviour.
- m3u mode fills the optional details. **Switching sources is just
  `setQueue(...)` with a different list**, not a second playlist system.
- Channel identity is **ID first, then name**: `tvg-id` → `tvg-name` → display
  name. This is an identification/matching key, not a claim that an ID encodes
  a category, language or country. Never use the row number or stream URL as
  the stable channel identity (§10.3).
- Category comes from that M3U entry's `group-title`, falling back to its
  `#EXTGRP` value only when `group-title` is absent/blank (point 5 FINAL,
  §10.2a). Language and country use `tvg-language` and `tvg-country`. Use only
  information available in the playlist; no outside metadata service,
  provider API or bulk stream probing.
  Do not invent values from an ambiguous ID/name. Missing or blank fields stay
  `null`; their group is displayed as **`Unknown`**, last in the selected
  grouping. This is a missing-data label, not a stored fake category. Missing
  details never prevent a valid stream from playing.
- Normalise recognised country/language codes and names (§10.2). An entire
  playlist missing a field dims that grouping option; flat view still works.
- The visible channel label uses the supplied display name, then `tvg-name`,
  then `tvg-id`, otherwise `Unknown` — never a credential-bearing URL. Each
  parsed channel therefore has a non-null `name`, even when all tags are absent.
  The header still derives its mode from the data:
  `bool get isChannelList => items.any((QueueItem i) => i.name != null);`
- Migrate Phase A's `paths.value` readers/listeners to the item notifier (or a
  compatibility view over it). Do **not** retain a second stored URL list or
  repeatedly materialise all URLs for channel changes. Only local playback
  needs to construct the engine's full playlist (§10.10a).

**RAM storage contract — final:**

- The loaded queue, its indexes and search keys live **only in RAM**. No queue
  database, disk-backed list, compressed archive or queue persistence in
  `shared_preferences`. Stop parks it; closing the app loses the loaded queue.
  Existing saved URLs, favourites and local resume storage remain separate and
  unchanged; this decision does not make those persistent features temporary.
- One immutable item record per channel. Search/group views refer to item
  indexes, not duplicated channel objects. The 5 s Undo may retain the required
  immutable snapshot; release it when it expires or is replaced.
- **Share repeated text**: intern group/language/country values within the
  loaded playlist. The intern pool must not retain every past playlist forever.
  Precompute one lowercase name+group search key per channel (§10.10c).
- Parse progressively in batches off the UI isolate. Release raw download
  buffers, original M3U text and temporary parser data once no longer needed,
  including on failure/cancellation. Do not retain the source text as a cache.
- **Build only visible rows** with `ListView.builder`. Logo image data is
  separate from queue records, fetched lazily into a **bounded RAM cache**
  (§10.4); never download/cache all channel logos eagerly.
- Measure actual peak and retained memory with a large playlist, including
  decoded logos. A playlist's download size is not its RAM footprint; no
  unmeasured promise of a fixed memory cost.

Attribute reference: `#EXTINF:-1 tvg-id tvg-name tvg-logo tvg-language
tvg-country group-title,Display Name`.
`tvg-chno` may exist in input but is ignored in this phase: no `chno` field,
no row number and no replacement `0`/`LIVE` label.

### 10.1 The header swaps two slots, and only two — point 4 FINAL

Slots 3 · 4 · 5 retain **search · clear · Close ✕**, as in local mode; search
has the channel-specific scope and total-only count of §10.9. Slot 5 is Close
in both modes — the undock/dock slot is gone (§4.8). Only slots 1 · 2 swap:

| # | local mode | **m3u mode** |
|---|---|---|
| 1 | Repeat | **Group by** — flat / category / language / country |
| 2 | Shuffle | **Favourite** — filter to favourites only |

**Repeat and shuffle are dropped in m3u mode** (owner, 2026-09-06). They are
queue verbs; live channels are not a queue. They return untouched the moment a
local queue is loaded. Recorded consequence: an m3u of VOD items also loses
them — accepted.

**Pitch, not a flat gap.** The header follows SALU's own grammar:
`[group · favourite] 14 [search] 14 [bin] 14 [close]`, 6 px inside the mode
pair (2026-09-07: slot 5 is the Close ✕ — the old `[undock]` slot is gone,
§4.8). The 2 px gap of the first draft put the field's **✕ (clear the text)**
about 4 px from the **🗑 (clear the whole playlist)**. Destructive controls do
not get 2 px.

### 10.2 Slot 1 — Group by (point 5 FINAL, preview approved 2026-09-08)

**Implement the grouping appearance and interactions exactly as the approved
preview**, including its stable mark, four-option pill and accordion (§10.15).
No alternate glyphs, layout, default mode or added labels without owner approval.

- **One stable mark plus a pill below it** — the `+` → pill pattern the app
  already teaches. The mark **never morphs** into four different glyphs: the
  family's grammar is *one mark, modified* (repeat is one loop arc across three
  states). Four unrelated glyphs can never be learned.
- **The mark does not report the mode; the list does it better** — grouping on
  = named group heads on screen, flat = none. No 18 px glyph beats that.
- **Default on load — FINAL (owner, 2026-09-08): always Flat.** This
  supersedes the old ~60 % category auto-pick and remembered-on-reload mode.
  Every fresh playlist load starts in the provider's flat order, even if every
  channel has complete tags. Grouping changes only when the viewer chooses it.
  The chosen mode survives panel close/reopen and temporary search/favourites
  filtering within that load; it does not override Flat on the next fresh load.
- **A mode the file has no tags for is dimmed, never hidden** — a vanishing
  option reads as a broken app.
- **Group order:** category keeps the playlist's own **first-appearance** order
  (providers order deliberately); language and country are alphabetical;
  **`Unknown` always last** (point 2, final — replaces `Uncategorized`).
- **Normalise country and language.** `tvg-country` is usually a code (`UK`,
  `GB`, `US`), `tvg-language` a word. Without a small ISO-3166 / ISO-639 map the
  heads fragment into `UK` / `GB` / `United Kingdom`.
- **Multi-value fields are NOT split this phase.** `group-title="UK | News"`
  and `tvg-language="English;Spanish"` are real. Splitting puts one channel in
  two groups and breaks "one row = one channel index". Treat the whole string
  as one key.

### 10.2a Missing-information logic — point 5 FINAL (2026-09-08)

Keep the already-final point-2 rules: no outside metadata discovery, no
fabricated country/language/category from a channel ID or ambiguous name,
missing fields stay null, and `Unknown` comes last when grouping is available.

Implement the approved preview's **metadata-aware options, not automatic grouping**:

1. A dimension with usable information is available; a dimension with none is
   dimmed but remains visible in the four-option pill. Availability reads the
   underlying playlist, not the current search/favourites subset.
2. Partial information keeps known groups useful and puts the rest in
   `Unknown`. With no grouping information at all, stay in Flat rather than
   manufacturing a meaningless single group or blocking playback.
3. Recognised aliases share one group (`UK` / `GB` / `United Kingdom`, `en` /
   `English`). Multi-value fields stay whole; do not silently split rows.
4. **Same-file category fallback — FINAL with the approved preview:** if
   `group-title` is absent or blank, accept that entry's `#EXTGRP` category.
   An explicit `group-title` wins; if both are missing/blank, the category stays
   unknown. This reads another tag in the supplied M3U, not a provider API or
   outside lookup. No comparable country/language guessing is added.

See §10.15 for the three approved interactive sample scenarios. The previous category
coverage threshold must not reappear as a so-called smart default.

### 10.3 Slot 2 — Favourites (point 6 FINAL, preview approved 2026-09-08)

**Implement the favourites appearance and interactions exactly as the approved
preview** (§10.15): bookmark marks, hover-to-add/filled-visible saved states,
persistence across reloads/restarts and favourites-only grouped browsing.
Visual and behavioural sign-off is complete; no silent redesign or simplification.
Production persistence remains `shared_preferences`, not the browser mock's
`localStorage`; the approved user-visible result must be the same.

- **Mark: the bookmark, not a star.** A five-point star at 15 px with a 1.4 px
  round-join stroke turns to mush; a bookmark is two verticals and a notch.
- **The row bookmark's visibility is the whole design** *(point 6 FINAL)*: **filled + full ink and always visible when the channel IS
  a favourite; invisible until the row is hovered when it is not.** A
  3000-channel list carrying 3000 outline bookmarks destroys the exact signal
  favourites exist to give. Hover-to-add is already the local rows' grammar.
- **Keying a channel — FINAL (point 2):** `tvg-id` → `tvg-name` → display
  name, in that order (ID first, then name).
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

### 10.4 Rows — no reorder, no delete (point 4 FINAL, 2026-09-08)

- **No `≡` grip, no drag, no up/down** (owner): the order is the provider's.
- **No per-row bin** (owner). The only row action is the favourite bookmark.
- **Anatomy — FINAL (point 2):**
  `[chevron if playing] · logo · name · favourite`.
- **No channel number anywhere in a row** — neither a provider's `tvg-chno`
  nor a generated row number. The old number-in-duration-slot proposal is
  superseded. The only channel count is the total inside search (§10.9).
- The **logo is before the name**, not an action or a new header mark. Reserve
  a small, fixed slot (default: 24 × 24 px in the existing 38 px row) so names
  never jump as images arrive. Fit the artwork without stretching. The playing
  chevron and favourite bookmark stay separate and unchanged.
- **Provider logos are allowed channel artwork**, including their native
  colours; this is the owner's narrow exception to the old logo exclusion,
  not permission to replace SALU's monochrome action marks with stock icons.
- Click a row = play that channel, including its logo area. The image is not
  independently focusable/clickable. Hover wash and now-row treatment stay
  §4.3's.

**Logo loading — included in point 2, final (previously out of scope):**

- Read `tvg-logo` from the same M3U entry. Fetch only a playlist-supplied image
  address (resolve a relative address against the playlist URL); no outside
  logo directory, name search or guessed logo service. Permit HTTP(S) image
  requests only. The referenced host may differ from the playlist's host:
  this is an explicit image download, not external metadata discovery.
- Load only visible rows and a small nearby buffer, with a small, fixed maximum
  number of concurrent requests. Playlist loading, scrolling and channel
  playback **never wait for logos**. Cancel stale work on source changes and
  bind results to the requested logo URL, never a recycled row index.
- Decode at the required display pixel size, accounting for display scale.
  Share identical logo requests/images; use a logo-specific bounded **RAM-only
  cache** that evicts least-recently-used images. Bound per-image transfer size
  and request time too; the cache must not become an unbounded second playlist.
  Numeric resource budgets are implementation defaults to verify in M-10.
- Missing, invalid or failed logo → the reserved slot stays empty. No spinner,
  error icon, instruction text or repeated retry loop. A logo failure is **not
  a failed channel**: it must never trigger the failure toast or channel skip.
- Do not persist downloaded logos to disk. An evicted logo may be fetched again
  when needed; this must not block restoring the channel list from Undo.

### 10.5 Grouping and the accordion — point 5 FINAL (2026-09-08)

- **Flat** → one plain list.
- **Category / language / country** → collapsible heads, **accordion: exactly
  one group open at a time** (owner).
- **After the viewer selects a grouped mode:** all collapsed except the
  playing channel's group (owner). A fresh load itself is **Flat** (§10.2),
  not an accordion. With **nothing playing, nothing is open** — a collapsed list is
  the map of the playlist, which is the point of grouping. This continues to
  reject the superseded "open the first group" idea; the approved preview agrees.
- **An auto-advance must not steal the view** *(point 5 FINAL)*: the open group
  follows the playing channel **only while the open group is already the
  playing one**. Deliberately opening "Movies" while News plays must survive an
  advance inside News (follow.md — never fight the user).
- **Collapsing a group above the viewport must not yank the list** — compensate
  the scroll offset so rows under the cursor stay put.
- **Sticky group head** while a long group is scrolled *(point 5 FINAL)*.
- Empty groups vanish under a filter. **No group-head counts**: point 2
  reserves channel counts for the single total inside search (§10.9).

### 10.6 Keeping the playing channel visible — point 7 FINAL (2026-09-08)

§4.3's reveal rule applies, plus the two cases the accordion creates. A search
or favourites filter that hides the channel is never cleared or overridden by
an indicator; reveal only when the current view contains that channel/group.

**The playing channel stays in the visible area — FINAL (owner, 2026-09-08,
point-7 clarification, M54).** While the panel is open, a channel change that
makes the now-row part of the current view always keeps it visible:

- **A deliberate change (row click, Next/Prev) reveals it immediately** — the
  shortest scroll needed; the ~3 s post-manual-scroll suppression of §4.3
  never swallows a deliberate zap. If the destination channel sits in a
  COLLAPSED group, that group opens and the row is revealed (§10.8b).
- **An automatic failure skip never steals a browsed view** — if the skip lands
  inside the group already on screen it reveals normally (the row is part of
  the current view); if it lands in a group the viewer is not browsing, the
  view is untouched and the toast + title bar name the landing channel while
  the §10.6 indicators (head chevron / edge chevron) point to it. A 3-failure
  cascade must never yank the list.
- **A filtered-out playing channel is never revealed by force** — no filter is
  cleared or overridden (§10.6 below, point 7).

- **The playing channel sits inside a COLLAPSED group** → its group head
  carries the play chevron, so "where am I" survives the accordion.
- **The playing row is scrolled off-screen** *(point 7, FINAL)* → a small
  quiet chevron fades in at the list edge it is hiding behind, pointing toward
  it; click = expand its group if needed, then reveal. It exists only while the
  signal is actually lost, costs no permanent control and no words. At 12 000
  channels this matters far more than at 14 files.

### 10.7 Title bar — point 4 FINAL (2026-09-08)

The title bar shows the **playing channel's name**, exactly as local files show
their file name. **The channel's playlist-supplied display name wins — mpv's
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

**The behaviour — reaffirmed by the owner, 2026-09-08 (review point 8 — FINAL)**

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

**10.8a-ii The cascade guard — mandatory; owner-approved 2026-09-08**

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
| **Bottom progress hairline** | **Carries the same still soft light** while the chrome is auto-hidden — see §10.8c. (It is still hidden while stopped or idle, exactly as today.) |
| **Seek backward / forward marks** | **Dimmed** — the same `enabled: false` Stop already applies to them. |
| **← / → keys** | **Silent.** A live key behind a dimmed button is worse than either alone: the marks say "not available" while the keyboard disagrees. |
| Play / Pause · Stop · sound group · volume bar | Unchanged. |

**The live indicator — FINAL (owner, 2026-09-08, option A of
`design/live-indicator-preview`): a still soft light, no moving shimmer.** The
owner rejected the drifting shimmer during review ("feels noisy to see
continuous moving"). The empty track instead carries a **soft, still centre
glow** (radial, fading to nothing at the track edges) — SALU's "live, no
timeline" signal. It needs no text, no red dot and no "LIVE" badge (rules 1
and 6 forbid all three); and because it is driven by the arrival of data it
**quietly fades away when the stream stalls** — so buffering gets an honest,
wordless indicator for free, with no persistent motion. Amplitude stays under
the volume bar's hover brightening (centre near
`rgba(255,255,255,.16)`, zero at the edges): this is a status, not a control.
It is never animated while live and receiving — stillness is the point; the
*change* (light present → light gone) is the signal.

### 10.8b Transport in m3u mode (point 3 FINAL, owner, 2026-09-08)

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
then renders emptiness. The soft light gives it the only honest thing it can say.

| | Local file | **Live channel** |
|---|---|---|
| Hairline content | fill from the left = position | **the §10.8a soft light** — still, centred |
| While buffering / stalled | n/a | the light **fades out** — same wordless signal as the timeline |
| Stopped / idle | hidden (unchanged) | hidden (unchanged) |

**The two surfaces never appear together.** The hairline exists *only* while the
chrome is hidden, and the timeline only while it is shown, so the live signal
**hands off** between them and is never duplicated. That is the whole value:
with the chrome auto-hidden over a live channel, the still light is the only
thing on screen reporting that data is arriving — no movement anywhere.

- **The hairline's soft light must be brighter than the timeline's** *(owner,
  option A)*: 2 px of height needs far more contrast than a 23 px bar to read
  at all. The bar's glow sits near `rgba(255,255,255,.16)` at its centre, the
  hairline's near `.5`. Still in both — brightness does the work, not motion.
- Everything else about the hairline is unchanged: 2 px, window bottom, the
  180 ms fade, and **strictly display-only** — the existing `Listener` that
  absorbs pointer events stays, so it can never be clicked, dragged, scrolled
  or hovered for a tooltip (it must not become a seek surface by accident).
- Same source of truth as the timeline: one "live and receiving" flag drives
  both, so they can never disagree.

### 10.9 Search, clear, close in m3u mode

**Search + playing-channel reveal are FINAL (point 7, owner, 2026-09-08).**
Search temporarily flattens groups; clearing it restores the selected grouping
mode and the browsed group. It never mutates the original queue or makes
Prev/Next follow visible results. The point-2 total-only count remains final.

- **Search matches name + group, never the URL** — matching the URL would
  surface credentials. Precompute one lowercase key per channel at parse time;
  never `toLowerCase()` 12 000 strings per keystroke.
- **Count — FINAL (point 2): total channels only, inside the search field.**
  A 12 750-channel list shows `12750`, including while search or favourites hide
  rows — never `1284 / 12750`, a filtered-result count, per-row numbering or a
  group-head count. During progressive loading it reflects the total loaded so
  far; once parsing completes it is the full channel total. Local mode retains
  its existing `shown / total` behaviour unchanged. Keep the channel-mode
  collapsing field and enough room for the total without crowding the text ✕
  or the playlist bin.
**Point 11 — FINAL (owner, 2026-09-08): clear, Undo and privacy.** Bin
unloads channels only — saved URLs and favourites survive; Undo never
re-fetches; credential-bearing URLs are never exposed.

- **The bin unloads the channels only.** Playback stops, the list empties, SALU
  returns to the logo canvas — and the **saved URL seven (`UrlLibraryService`)
  is untouched**, as is the favourites store. 5 s Undo restores **from an
  in-memory snapshot, never a re-fetch**: an Undo that stalls 10 s on a slow
  provider is not an Undo. This restores channel records (including logo URLs),
  not an unlimited collection of images; evicted logos may load lazily without
  delaying Undo.
- **Close ✕ (slot 5) closes the panel only** — the channel list stays loaded
  and keeps playing, exactly as in local mode. Undock does not exist (§4.8), so
  there is no cross-window/cross-isolate bridge to design for m3u mode; Phase 8
  will design its own transport when it is built.

### 10.10 Performance — 50 000 channels, and why there is no cap

**Point 10 — FINAL (owner, 2026-09-08): no channel cap; a 64 MB download
ceiling; channels load progressively in the background and the list scrolls
and searches smoothly at 50 000.**

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

These historical timings cover playlist text, **not logo downloads or image
memory**. The fixture included `tvg-chno`; point 2 now ignores channel numbers.
Profile the final queue and bounded logo cache separately before claiming a RAM
budget or a combined loading time.

**Superseded by the parser adoption (M49, 2026-09-08):** the table above was
measured with SALU's earlier whole-text prototype parser. With `m3u_xmltv`'s
`parseStream`, rows are produced **as the download arrives**, not after a full
parse, and the per-entry cost is the adopted parser's own (unmeasured at 50 000
— its published figures are for XMLTV). The *rules* below (no cap, 64 MB
ceiling, off-UI parse, index views, interning, viewport rows) stand; the
numbers are re-measured at M-10.

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

**Point 3 — FINAL (owner, 2026-09-08): in channel-list mode the engine holds
ONE media, never the list.** SALU selects each channel in the original provider
order, including Prev/Next while search, favourites or grouping change the view.
Stop leaves the same list and channel index parked (§10.8b). Local playback's
existing full-queue engine path is unchanged.

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
  outside SALU's control. Reuse the live indicator of §10.8a: the timeline is
  already inert with nothing to report, and a still soft light during the
  download says "working" with no words and no new vocabulary — it fades when
  the fetch ends or fails, exactly as it fades on a stalled live stream.
- **Play before the parse finishes.** If the user clicks a channel while the
  tail is still arriving, it plays immediately — SALU only needs that one URL.
- **If the fetch itself fails** (bad URL, dead provider, past the M46 byte
  ceiling): the still light fades out and the same toast wording is used —
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

These three rules are part of point 2's finalized RAM contract (§10.0), not
optional shortcuts. Keep the original M3U text only while parsing needs it;
release temporary buffers and expired Undo snapshots. Group/search views hold
indexes over the one queue. Apply §10.4's lazy, size-limited RAM cache to logos
so artwork does not erase the savings made on channel metadata.

Also: the grouping index is rebuilt in SALU only — **switching group mode never
touches the engine**, so it cannot interrupt playback.

#### 10.10d Where a limit does belong

Not on channels — on the **download**. A hostile or mistyped URL can stream
gigabytes. Abort the fetch past a generous byte ceiling **(FINAL, point 10:
64 MB, ~5× the 12.9 MB measured at 50 000 channels)** and treat it as a failed
load, using the same toast a failed channel uses (M37). That bounds the real
risk without ever telling a legitimate 50 000-channel user "no".

### 10.10e Privacy (point 11 — FINAL, owner, 2026-09-08)

- **Never render a playlist URL** in a row, tooltip, title bar, OSD card or log
  — they carry credentials.
- Search matches name and group only, never the URL (§10.9) — otherwise a
  typed token could surface a credential as a "match".
- Logo URLs may also contain credentials: do not render them in tooltips or
  errors, or log them. Image requests must not forward playlist credentials to
  an unrelated host. No outside metadata/logo lookup service is used.

### 10.11 Out of scope, explicitly

EPG / `tvg-id` guide data, catch-up, Xtream APIs, external metadata/logo
lookup services, editing or saving a modified m3u, disk-backed queue/logo
storage, and per-channel resume (`resume_service.dart:92` already skips
anything containing `://`).

**Superseded exclusion (owner, 2026-09-08, point 2): `tvg-logo` is now IN
SCOPE.** Provider logos replace per-channel numbers before the name (§10.4),
with viewport-only loading and a bounded RAM cache. This does not add EPG or
any other external enrichment source.

### 10.12 Build steps — m3u mode (each leaves the app runnable)

m3u mode is **its own phase, built after steps 1–12 of §7** (Phase A — the
local panel — must work first; undock no longer exists, §4.8). This phase then
adds the channel-list behaviour behind it. Do not interleave them.

| # | Step | Leaves the app |
|---|---|---|
| **M-1** | **`QueueItem` + `QueueService` — point 2 FINAL** (§10.0). One RAM-only list of item records, including optional IDs/names/group/language/country/logo URL, no channel number. Migrate current Phase A notifier readers and mutations without a second stored URL list; add data-derived `isChannelList`. | identical behaviour, local only |
| **M-2** | **The parser** — **base: `m3u_xmltv` 0.2.0, owner decision M49/§10.16 (adopted 2026-09-08)** — fetch, `#EXTINF` attributes and display name, ID-first/name-fallback identity, optional `tvg-logo`, `group-title` → `#EXTGRP` category fallback (point 5 FINAL — patch the package's blank-`group-title` case), nullable grouping details with `Unknown` in the view (blank values → null at the wrapper, BOM stripped at the fetch boundary). Intern group/language/country (M44), precompute the search key (M43), enforce the byte ceiling (M46), release raw text/buffers. `parseStream` drives progressive batches (M-41) off the UI isolate. Pure Dart, unit-testable with no UI — wrapped behind SALU's own parser interface; run SALU's fixture suite, do not inherit the package's tests as proof. | unused, but tested |
| **M-3** | **Route m3u sources to the parser** instead of to mpv — m3u **URLs** (`open_media_service.playUrl`) **and local `.m3u`/`.m3u8` files** opened via Open File…/drop (M55; only the fetch differs). Build the queue from the parsed channels. Fix the index mirror, which is gated on `paths.length == medias.length` (`player_service.dart:177`). | m3u loads, plain list, no grouping |
| **M-4** | **The engine path (M40)** — in channel mode `_openQueueAt` opens **one** media, never the list. Local mode keeps the existing full-queue path untouched. | channel changes are constant-time |
| **M-4b** | **Failure skip (§10.8)** — extend the existing `stream.error` listener (`player_service.dart:267`, currently a `debugPrint`): toast "Failed to load" + name, advance to the next channel, and enforce the 3-strike cascade guard. | dead channels self-skip |
| **M-5** | **Title bar + rows** — channel name (M22), logo before the name instead of numbers (M16), lazy bounded RAM image loading (§10.4), total-only count inside search (§10.9), no grip/bin, favourite as the only row action (M14/M15). | list is usable |
| **M-6** | **Favourites — point 6 FINAL** — match the approved preview exactly (§10.15): host → `tvg-id`/`tvg-name`/name store (M11/M12), debounced writes, filter toggle, hover-vs-filled visibility (M10). Use production `shared_preferences`; no browser study controls/data. | favourites match the approved reference |
| **M-7** | **Grouping + accordion — point 5 FINAL** — match the approved preview exactly (§10.15): group index, four modes with **Flat on every fresh load** (M6), the pill, dimmed unavailable modes, accordion/sticky heads, `Unknown` last and the approved same-file fallback (§10.2a). | grouping matches the approved reference |
| **M-8** | **Reveal** — chevron on a collapsed playing group, the off-screen edge chevron (§10.6). | never lose the playing channel |
| **M-9** | **Live chrome** — the inert timeline, the **still soft light (option A)**, the hairline handoff, dimmed+silent seek, Prev/Next rules (§10.8a–c). | live playback reads correctly |
| **M-10** | **Progressive load** (M41) + fetch indicator (M42, the §10.8a soft light) + failed-channel toast (M37). Measure peak/retained RAM with 50 000 channels, raw-buffer release, viewport row count, bounded logo cache/concurrency and cancellation — **re-measure parse timings on `m3u_xmltv`** (§10.10). | large lists stay responsive within measured memory budgets |
| **M-11** | **Docs — point 12 FINAL (owner, 2026-09-08)** — pass §10.13's checklist, flip this section's status, update `follow.md` §1.6 with any new marks, README phase table. | shipped |

#### Build progress — M-1 … M-11 shipped (engineering record, 2026-09-08)

Code-level status only; **nothing here is an owner sign-off**, and §10.13's
acceptance checklist has not been run against a build (there is no Flutter
engine in the build sandbox — verification is the analyzer plus the pure-Dart
suites in `test/`). M-10's measurements in particular are pending on a real
Windows build: the budgets are implemented, the numbers are not yet taken.

| Step | State | Where |
|---|---|---|
| **M-1** | shipped | `queue_item.dart`, `queue_service.dart` |
| **M-2** | shipped — in-repo pure-Dart parser behind SALU's own interface, **not** `m3u_xmltv` (see the deviation note under M49/§10.16) | `lib/core/m3u/` |
| **M-3** | shipped | `channel_source.dart`, `channel_load_service.dart`, `open_media_service.dart`, `drop_handler.dart`, `main.dart`, `home_screen.dart` |
| **M-4** | shipped | `player_service.dart::_openQueueAt` |
| **M-4b** | shipped | `channel_skip_policy.dart`, `player_service.dart::_onEngineError` |
| **M-5** | shipped | `playlist_panel.dart` (channel header + rows), `channel_logo_service.dart`, `widgets/channel_logo.dart` |
| **M-6** | shipped | `channel_favourites_service.dart`, `playlist_panel.dart`, `player_service.dart` (Undo key), `main.dart` (load + close-guard flush) |
| **M-7** | shipped | `channel_grouping.dart`, `test/channel_grouping_test.dart`, `playlist_panel.dart` (pill + accordion + sticky head), `channel_load_service.dart` (reset signal) |
| **M-8** | shipped | `player_service.dart` (`lastOpenWasAuto`), `playlist_panel.dart` (reveal + head/edge chevrons) |
| **M-9** | shipped | `player_service.dart` (`isBuffering`, `isLiveReceiving`, seek guard), `widgets/live_light.dart`, `media_timeline.dart`, `home_screen.dart` (hairline), `transport_cluster.dart`, `transport_actions.dart` |
| **M-10** | shipped, measurements pending | progressive load in M-3 (`channel_list_loader.dart`), fetch light + failed-playlist toast in M-3/M-5; budgets below implemented, numbers untaken |
| **M-11** | shipped | this section, `follow.md` §1.6, README phase table |

What M-3 routes, and what it deliberately does not:

- Every open verb — Open File…, Open URL, drop, Explorer open-with, the launch
  argument — funnels through `ChannelLoadService.openSource` / `openBatch`. An
  m3u **URL** and a local **`.m3u` / `.m3u8` file** both reach SALU's parser;
  only the fetch differs (M55). mpv never receives a channel list.
- A source that *looks* like a directory but turns out to be an **HLS manifest**
  or not M3U text at all is handed straight back to the engine
  (`ChannelListHls` / `ChannelListNotPlaylist`) — a false positive costs one
  sniffed request, never a broken open.
- **Media wins in a mixed batch**: a multi-select of videos plus an `.m3u`
  plays the videos and ignores the playlist file, because a channel list can
  never share a queue with local files. Dropping an `.m3u` onto the *open
  panel* (the append gesture) ignores it for the same reason.
- The failed-**playlist** toast names the playlist, never its URL: a local file
  name, a remote **host** (§10.10e). It is not a failed channel and never
  triggers the M3b skip.
- The URL library's health dot asks the honest question for a directory — *did
  the playlist load?* — instead of watching the first channel's stream.
- The index mirror's `paths.length == medias.length` gate is fixed: in channel
  mode SALU keeps its own index (mpv's is always 0 and says nothing), and the
  title bar reads the **channel's** label, never `1234` off a stream URL.

M-4 / M-4b, and the Phase A behaviour they must not disturb:

- `_openQueueAt` opens **one** `Media` in channel mode and returns; the local
  full-queue path (native advance, gapless, `Media(start:)` resume) is
  untouched below it.
- Repeat and shuffle are inert in channel mode (`_shuffleDriving` is false, the
  engine is put on `PlaylistMode.none`), so a shuffle left on by a local
  session can never drive channel zapping. `completed` is not an advance
  trigger there — skipping is failure-only.
- Prev/Next walk the channel list in list order, never wrap, and park at both
  ends: at the head, and at the **progressive-load frontier** (M56) because
  `hasNext` is honestly false until more rows land. Previous never "restarts" a
  live stream (§10.8b), and it dims on the first channel.
- The skip rule lives in `ChannelSkipPolicy` as pure bookkeeping so the locked
  behaviour is testable without an engine: toast + next channel, **3**
  consecutive failures stop the cascade, any success or manual pick resets it,
  the tail never wraps, and a burst of mpv error lines for one dead channel
  fires exactly one skip.

M-5 … M-9, and what they must not disturb:

- The panel is one widget with two headers: channel mode shows the
  group-by + favourites pair, a total-only search and 38 px rows
  (`[chevron · 24-px logo · name · hover bookmark]`); the local header
  (repeat/shuffle, `shown / total`) and local rows (grip, trash, drag)
  are untouched below the branch.
- Logos fetch lazily into a bounded RAM-only LRU (200 entries / 32 MB,
  512 KB + 10 s per image, 6 concurrent, ≤5 redirects); a miss is an
  empty slot — never a spinner, never the failure toast. In-flight
  fetches die with the load (`cancelStale`).
- Favourites key ID-first (`tvg-id` → `tvg-name` → name) per playlist
  host (local files by their own path — never a shared bucket, never a
  credentialed URL), persist in `shared_preferences` with 500 ms
  debounced writes plus a close-guard flush, are never pruned, and
  survive the bin (Undo reselects the restored list's key).
- Grouping is a pure model (`channel_grouping.dart` + its suite): Flat
  on every fresh load (the `loadGeneration` reset — mode, query,
  favourites filter, accordion, scroll), a four-option pill with dimmed
  unavailable modes, one stable group-by mark (never four morphing
  glyphs), accordion + sticky head, `Unknown` last, and a search that
  flattens while suspending — never clearing — the mode.
- Reveal answers deliberate vs automatic (`lastOpenWasAuto`): a zap
  force-reveals and opens a collapsed destination group; a failure skip
  into an unbrowsed group never steals the view — the toast, title bar
  and head/edge chevrons say where it landed. Edge chevrons never clear
  filters. The descriptor cache rebuilds only when its key changes, so a
  scroll tick never regroups the list.
- Live chrome: the timeline is empty and inert (no fill, no readouts —
  not even zeros — no hover, no pointer response) with the still soft
  light while data arrives, fading on stall (`player.stream.buffering`);
  the 2 px hairline carries the brighter variant while the chrome hides
  and the signal hands off, never duplicates. Seeks dim, the facade and
  `seekTo` stay silent, Prev/Next walk list order.

Still open before Phase B can be called done: the whole of §10.13 on a
real Windows build — including the M-10 measurements (peak/retained RAM
at 50 000 channels, parse timings on the in-repo parser, logo-cache and
scroll behaviour), the Phase A regression sweep (check 31) and the
failure-cascade checks (24, 24b, 24c) against a live provider. No Flutter
engine exists in the build sandbox, so the analyzer plus the pure-Dart
suites in `test/` (now including `channel_grouping_test.dart`) are the
verification so far.

**Two traps, both already paid for once in §5:** every action must act on the
**real** channel list, never on the filtered view; and the group index is a view
over the list, so a mode switch must never touch the engine (M45).

**Phase B scope clarifications — FINAL (owner, 2026-09-08):**

- **Local `.m3u` / `.m3u8` files route through the same parser and channel UI
  as m3u URLs (M55).** Phase A's Open File…/drop already accept playlist files
  and today hand them whole to mpv; after Phase B that must not remain true.
  Only the fetch differs — read the file instead of the HTTP stream; the same
  HLS-vs-directory detection, byte ceiling, progressive batches, cancellation
  and raw-buffer release apply. A failed local load uses the same
  **"Failed to load"** + playlist-name toast and is not a failed channel (no
  M3b skip).
- **Prev/Next at the progressive-load frontier park until more rows arrive
  (M56).** If the list is still loading and the viewer steps past the last
  parsed channel, it behaves like end-of-list — park/dim, never wrap, never
  interrupt the load. (In practice the streaming parser keeps this rare; the
  rule still covers slow networks and the byte-ceiling edge.)
- **Radio / audio-only channels need nothing new (M57).** Radio is a stream
  exactly like a video channel, simply without video — the same playback path,
  the same rows/favourites/grouping/search, nothing invented. Out of scope:
  radio-specific artwork, station-logos-by-name, or any separate radio UI.

### 10.13 Acceptance checklist — m3u mode (point 12 — FINAL, owner, 2026-09-08)

1. Load an m3u URL → the panel lists **channels**, not one row named after the
   playlist file.
2. Title bar reads the channel's display name, never `1234` from the stream URL,
   and never flickers to ICY metadata mid-programme.
3. Header slots 1–2 are **group-by** and **favourite**; repeat and shuffle are
   **absent**. Load a local folder → repeat and shuffle are back, unchanged.
4. Header pitch: the field's ✕ is nowhere near the bin. `[group·fav] 14
   [search] 14 [bin] 14 [close]` (slot 5 is the Close ✕ — no undock slot, §4.8).
5. A fresh playlist load starts **Flat**, regardless of tag coverage or the
   last load's grouping mode. Group-by opens a four-mode pill; the chosen option
   glows and the main mark never changes shape. A category-only playlist dims
   language and country instead of hiding them. No automatic category choice.
5b. At equivalent desktop sizes, grouping/favourites match the approved
    preview's marks, spacing, material, motion and interaction states (§10.15).
    No new labels, alternate controls, row numbers or study-only UI are added.
6. Category keeps the provider's first-appearance order; language and country
   are alphabetical; **`Unknown` is last** for missing values. Recognised
   country/language aliases share a group; missing fields never block playback.
6b. Missing/blank `group-title` + an entry's `#EXTGRP` → use that category.
    Both present → `group-title` wins. Both missing/blank → `Unknown` when
    grouping is available. Never infer country/language from an ID or URL.
7. When a grouped mode is chosen, only the playing channel's group opens;
   the rest stay collapsed. With nothing playing, **nothing** is open. Fresh
   loads are Flat, so they have no group heads until the viewer asks for them.
8. Exactly one group open at a time; opening another closes the first.
9. Open "Movies" while a News channel plays, let it advance → **Movies stays
   open** and the News group head carries the chevron.
10. Collapse a group above the viewport → the rows under the cursor do not jump.
11. Scroll the playing channel off screen → an edge chevron fades in; click it →
    the group expands if needed and the row is revealed.
11b. The playing channel stays in the visible area (§10.6, M54): pressing
    Next/Prev or clicking a row immediately after a manual scroll still reveals
    the landing channel (a deliberate zap is never suppressed); an automatic
    failure skip into a group the viewer is not browsing does **not** yank or
    open the view — the toast, title bar and head/edge chevrons say where it
    landed. A filtered-out playing channel is never force-revealed.
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
17. A provider logo appears **before the channel name**; no channel or row
    number is rendered anywhere, even if input includes `tvg-chno`. There is
    no `0` or "LIVE" substitute and no group-head count.
17b. Missing/broken logo → a quiet empty slot, stable name alignment, no toast
    and no channel skip. Loading a channel or Undo never waits for its image.
17c. A large list downloads logos only around the viewport, decodes at display
    size and respects its bounded RAM cache and concurrency limits. Fast scroll
    or source switching cannot attach an old image to a different row.
17d. The search field shows **only the total loaded channel count**: a finished
    12 750-channel list reads `12750` before and after search/favourites filtering,
    never `shown / total`. Local playlist counts keep their Phase A behaviour.
18. While a live channel plays: the timeline is **present, full size, empty and
    inert** — no fill, no thumb, no readouts, no hover chip, and clicking or
    dragging it does nothing.
19. The **still soft light** is present on the inert timeline while data
    arrives and **quietly fades** when the stream stalls — nothing moves.
20. Auto-hide the chrome → the hairline carries the same **still soft light**
    (brighter — 2 px needs contrast). Bring the chrome back → the hairline
    goes, the timeline resumes it. **Never both.**
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
27b. Step Next/Previous at the **progressive-load frontier** (rows still
    arriving) → behaves like end-of-list: parks/dims, never wraps, never
    interrupts the load; once more rows land it walks again (M56).
28. No instruction text, no placeholder, no "LIVE" badge, no red dot, no
    spinner, no confirmation dialog anywhere in m3u mode.
29. Point 2 identity uses `tvg-id` first, then `tvg-name`/display name. Optional
    metadata is playlist-provided only; unknown details stay null and group as
    `Unknown`. No external enrichment requests or URL-based guesses occur.
30. A 50 000-channel memory profile shows one queue, shared repeated grouping
    text, index-based views, viewport-only widgets and a bounded logo cache.
    Raw source buffers are released after parsing; old loads and expired Undo
    snapshots are not retained. Neither the queue nor logos are persisted.
31. Open local → IPTV → local: the same queue service changes entries, with no
    parallel metadata list. Local ordering, resume, repeat/shuffle and Undo
    continue to pass Phase A's checks; saved URLs/favourites remain persistent.
32. Open a **local `.m3u` / `.m3u8` file** via Open File…/drop → it lists as
    **channels** through the same parser and channel UI as an m3u URL (only the
    fetch differs) — never handed whole to mpv (M55). A radio / audio-only
    channel in any list plays identically; there is no separate radio UI and
    nothing new is invented (M57).

### 10.14 Decision record — m3u

| # | Decision | Value | Chosen by |
|---|---|---|---|
| M1 | Header slots 1–2 swap with the source | group-by · favourite | **owner** |
| M2 | Repeat & shuffle | **dropped** in m3u mode | **owner**, 2026-09-06 |
| M3 | Dead channel | ~~stay on it, never auto-advance~~ → **REVERSED (M3b)** | superseded |
| M3b | Dead channel | toast **"Failed to load"** + name, then **auto-advance to the next channel and play it** — the viewer never hand-clicks past dead entries | **owner**, 2026-09-06, §10.8 |
| M3c | Who drives the skip | **SALU, off `stream.error`** — never mpv's native advance, which would require handing mpv the whole list and cost ~1–2 s per change (M40). The listener already exists at `player_service.dart:267` | forced by M40, §10.8a-i |
| M3d | Cascade guard | **FINAL — stop after 3 consecutive failures**; reset on any success or manual pick; never wrap past the end of the list | **owner**, 2026-09-08, §10.8a-ii |
| M3e | Skip trigger | **failure only** — `completed` never advances in channel mode (a live channel does not end) | default, §10.8a-ii |
| M4 | Group modes | flat · category · language · country | **owner** |
| M5 | Group-by UI | **FINAL (point 5)** — approved preview's stable mark + four-option pill exactly; never a morphing glyph or added labels | **owner**, 2026-09-08, §§10.2, 10.15 |
| M6 | Group-by default | **FINAL — always Flat on every fresh load**; manual grouping only, retained during this load's panel/search/filter changes, never auto-picked from coverage or restored over Flat on reload | **owner**, 2026-09-08, §10.2 |
| M7 | Missing-tag modes | **FINAL (point 5)** — dimmed, not hidden; availability uses the underlying playlist, not filtered results | **owner**, 2026-09-08, §§10.2–10.2a |
| M8 | Multi-value tags | not split this phase | default, §10.2 |
| M9 | Favourite mark | **FINAL (point 6)** — the approved preview's bookmark, not a star | **owner**, 2026-09-08, §§10.3, 10.15 |
| M10 | Row bookmark visibility | **FINAL (point 6)** — filled + always visible when favourite; hover-only when not; match approved preview exactly | **owner**, 2026-09-08, §§10.3, 10.15 |
| M11 | Channel key | **FINAL (point 2)** — ID first, then name: `tvg-id` → `tvg-name` → display name; never row number or stream URL | **owner**, 2026-09-08, §§10.0, 10.3 |
| M12 | Playlist key | **host**, not full URL | default, §10.3 |
| M13 | Favourites + grouping | **FINAL (point 6)** — favourites keep groups; only search temporarily flattens; approved preview is binding | **owner**, 2026-09-08, §§10.3, 10.15 |
| M14 | Rows | no drag, no reorder, no per-row delete | **owner** |
| M15 | Row action | favourite only | **owner** |
| M16 | Channel numbers / logos | **FINAL (point 2), supersedes number slot** — no channel/row numbers; provider logo **before the name**; missing/broken image leaves an empty, fixed slot | **owner**, 2026-09-08, §10.4 |
| M16b | Logo source / memory | **FINAL (point 2)** — M3U `tvg-logo` only, viewport-first, display-sized decoding, limited concurrent fetches, bounded RAM-only cache; no logo lookup service or blocking playback | **owner**, 2026-09-08, §10.4 |
| M17 | Accordion | **FINAL (point 5)** — Flat on load; selecting grouping opens only the playing group; at most one group open, and all may be collapsed | **owner**, 2026-09-08, §§10.5, 10.15 |
| M18 | Nothing playing | **FINAL (point 5)** — nothing open in a grouped view | **owner**, 2026-09-08, §10.5 |
| M19 | Auto-advance vs the open group | **FINAL (point 5)** — the view is not stolen; preserve a group deliberately browsed by the viewer | **owner**, 2026-09-08, §10.5 |
| M20 | Playing channel in a collapsed group | **FINAL (point 7)** — chevron on the group head; never override a filter | **owner**, 2026-09-08, §10.6 |
| M21 | Playing row off-screen | **FINAL (point 7)** — edge chevron, click = expand if needed and reveal; no filter override | **owner**, 2026-09-08, §10.6 |
| M22 | Title bar | **FINAL (point 4)** — channel's playlist-supplied name, never overwritten by stream metadata; logos not channel numbers in rows | **owner**, 2026-09-08, §§10.4, 10.7 |
| M23 | Search scope | **FINAL (point 7)** — name + group, never URL; temporarily flatten then restore the chosen grouping/browsed group; original queue untouched | **owner**, 2026-09-08, §10.9 |
| M23b | Channel count | **FINAL (point 2)** — total loaded channels only, inside search; unchanged by filtering; no per-row or group-head counts. Local count behaviour untouched | **owner**, 2026-09-08, §10.9 |
| M24 | Bin | unloads channels only; saved seven and favourites survive | **owner**, 2026-09-08 (point 11), §10.9 |
| M25 | Undo | in-memory snapshot, never a re-fetch | **owner**, 2026-09-08 (point 11), §10.9 |
| M26 | Bridge | **void** — undock was removed (2026-09-07, §4.8), so no cross-isolate `PlaylistBridge` will be built | ~~default~~ §10.9 |
| M27 | Parser / playback split | **FINAL (point 1)** — SALU reads the channel directory and retains channel details + URLs; mpv plays only the selected channel URL and handles its HLS segment manifests. Design approved; implementation pending | **owner**, 2026-09-08, §10.0 |
| M28 | Queue upgrade | **FINAL (point 2)** — one RAM-only `List<QueueItem>`; URL + optional IDs/name/group/language/country/logo URL, no channel number, no parallel metadata table; local behaviour unchanged | **owner**, 2026-09-08, §10.0 |
| M28b | RAM efficiency | **FINAL (point 2)** — share repeated grouping text, use index-based views and visible rows only, release raw input/temporary data and expired snapshots; bounded RAM logo cache, no queue/logo disk store | **owner**, 2026-09-08, §§10.0, 10.4, 10.10c |
| M28c | Missing information | **FINAL (point 2)** — playlist data only; identity uses ID then name, not guessed geography/categories. Missing details stay null, shown under `Unknown` last; unavailable grouping modes dim | **owner**, 2026-09-08, §§10.0, 10.2 |
| M29 | Timeline when live | stays, exact size, **inert and empty** — never hidden (rule 5), never greyed (that is icon-disabled language) | **owner** (raised) + default, §10.8a |
| M30 | Live indicator | **FINAL (point 9, owner, 2026-09-08, option A)** — a **still soft centre light** on the empty track, present while data arrives, quietly fading when the stream stalls; **no moving shimmer** (rejected as noisy). Preview: `design/live-indicator-preview` | **owner**, 2026-09-08, §10.8a |
| M31 | Bottom hairline when live | **carries the same still soft light** while the chrome is auto-hidden — the two surfaces hand off and never both show; fixes a hairline that currently renders empty on live (`frac = 0`) | **owner**, 2026-09-06, §10.8c |
| M31b | Hairline light contrast | brighter than the bar's (~`.5` centre vs `.16`) — 2 px needs it; still, not moving | **owner**, 2026-09-08 (option A), §10.8c |
| M31c | Hairline stays display-only | the existing pointer-absorbing `Listener` stays; never a seek surface | default, §10.8c |
| M32 | Seek marks + ← → keys | dimmed **and** silent | **owner**, 2026-09-06 |
| M33 | Stop in m3u | canvas → initial state; **channel list stays parked on the same channel** | **owner**, 2026-09-06 |
| M34 | Previous / Next | walk the channel list; dim at a single channel | **owner**, 2026-09-06 |
| M35 | Prev/Next order | **list order, never the visible order** — browsing must not change what Next does | **owner agreed**, 2026-09-06, §10.8b |
| M36 | Previous's 3 s restart rule | does not apply live — Previous always steps back a channel | **owner agreed**, 2026-09-06, §10.8b |
| M37 | Failed-channel toast | the existing card shape, wording **"Failed to load"** + the channel name (a toast may carry words; follow.md §1.6 allows it — controls may not) | **owner**, 2026-09-06 |
| M38 | Volume / mute OSD | unchanged from local | **owner**, 2026-09-06 |
| M39 | **Channel cap** | **none** — a cap turns "slow" into "refused"; 50 000 parses in 149 ms | **owner** ("stay responsive at 50k"), §10.10 |
| M40 | **Engine holds ONE media in channel mode** | **FINAL (point 3)** — only the selected channel reaches mpv; SALU owns Prev/Next in original order and keeps the list on Stop. Local mode keeps the full-queue path | **owner**, 2026-09-08, §10.10a |
| M41 | Progressive load | `m3u_xmltv.parseStream` yields channel batches as the download arrives — a channel is playable before the tail parses; old whole-file timings (0.9 ms / 149 ms) are superseded and re-measured at M-10 on the adopted parser | **owner**, 2026-09-08 (parser adoption), §10.10b |
| M42 | Loading state | only for the network fetch; reuse the §10.8a **still soft light**, no spinner, no words | **owner**, 2026-09-08 (option A), §10.10b |
| M43 | Search keys | precomputed at parse time; narrowing while typing. Naive per-keystroke lowercasing is **banned** (40.8 ms = dropped frame) | default, §10.10c |
| M44 | String interning | **FINAL (point 2)** — share repeated group/language/country strings within the loaded playlist; release old pools instead of retaining past loads forever | **owner**, 2026-09-08, §§10.0, 10.10c |
| M45 | Group-mode switch | re-index in SALU only, never an engine call — cannot interrupt playback | default, §10.10c |
| M46 | Download ceiling | abort past **64 MB** and fail with the M37 toast — the limit belongs on bytes, not channels | **owner**, 2026-09-08 (point 10), §10.10d |
| M47 | Same-file category fallback | **FINAL (point 5)** — use the entry's `#EXTGRP` only if `group-title` is absent/blank; neither available means unknown; no outside enrichment | **owner**, 2026-09-08, §10.2a |
| M48 | Preview implementation fidelity | **FINAL (points 5 & 6)** — implement grouping/favourites appearance and behaviour exactly as the approved preview committed with this sign-off; no silent redesign | **owner**, 2026-09-08, §10.15 |
| M49 | **Parser base** | **FINAL (owner, 2026-09-08)** — M-2 builds SALU's channel-directory parser on **`m3u_xmltv` 0.2.0** (M3U half only; XMLTV/EPG unused), wrapped behind SALU's own interface. Supersedes §10.16's earlier "no dependency" stance. Requires: blank-`group-title`→`#EXTGRP` fallback patched, blanks→null at the wrapper, UTF-8 BOM stripped, SALU's own fixture suite still mandatory. Costs: Dart floor ≥3.12.2 + `equatable`/`xml` (decide in M-1; vendoring the MIT M3U subset is the fallback). m3u_nullsafe is NOT adopted | **owner**, 2026-09-08, §10.16 |
| M50 | **Live indicator (point 9)** | **FINAL (owner, 2026-09-08, option A of `design/live-indicator-preview`)** — the moving shimmer is **rejected**; the live chrome carries a **still soft centre light** that fades quietly when the stream stalls. Timeline and 2 px hairline share it (hairline brighter); never both surfaces at once; the fetch-loading state (§10.10b) reuses it. Supersedes the M30 *default* | **owner**, 2026-09-08, §§10.8a, 10.8c |
| M51 | **Large-list performance (point 10)** | **FINAL (owner, 2026-09-08)** — no channel cap; 64 MB download ceiling; progressive load off the UI isolate (`m3u_xmltv.parseStream`, rows usable before the download ends) and fluid scroll/search at 50 000. Old §10.10 whole-text timings are superseded and re-measured at M-10 | **owner**, 2026-09-08, §10.10 |
| M52 | **Clear · Undo · privacy (point 11)** | **FINAL (owner, 2026-09-08)** — bin unloads channels only; the saved URL seven and favourites store survive; Undo restores from an in-memory snapshot, never a re-fetch; credential-bearing URLs are never rendered, matched or logged. Upgrades M24/M25 from *default* | **owner**, 2026-09-08, §§10.9, 10.10e |
| M53 | **Testing & docs (point 12)** | **FINAL (owner, 2026-09-08)** — §10.13's checklist gates the phase; on ship, flip this section's status, update `follow.md` §1.6 mark family and the README phase table (M-11) | **owner**, 2026-09-08, §§10.12–10.13 |
| M54 | **Playing channel stays visible (point-7 clarification)** | **FINAL (owner, 2026-09-08)** — a deliberate channel change (row click, Next/Prev) always reveals the now-row in the visible area (shortest scroll; opens a collapsed destination group); the ~3 s suppression applies only to automatic skips, which never steal a browsed view — toast + title bar + head/edge chevrons say where the skip landed; filters are never force-cleared | **owner**, 2026-09-08, §10.6 |
| M55 | **Local `.m3u` / `.m3u8` files** | **FINAL (owner, 2026-09-08)** — a local playlist file opened via Open File…/drop routes through the same parser and channel UI as an m3u URL; only the fetch differs (file read vs HTTP stream); same HLS-vs-directory detection, byte ceiling, progressive batches, cancellation and buffer release. Never handed whole to mpv after Phase B. Favourites keying for a local file uses its canonical path as its own key *(default)* — two local files must never share a "no-host" favourites bucket | **owner**, 2026-09-08, §10.12 |
| M56 | **Prev/Next at the load frontier** | **FINAL (owner, 2026-09-08)** — while rows are still arriving, stepping past the last parsed channel parks/dims like end-of-list: never wraps, never interrupts the load. Rare in practice (streaming parse), but mandatory for slow networks / the byte ceiling | **owner**, 2026-09-08, §10.12 |
| M57 | **Radio / audio-only channels** | **FINAL (owner, 2026-09-08)** — radio is a stream exactly like a video channel, just without video: the same playback path and the same rows/favourites/grouping/search. Nothing new is built — no radio UI, artwork or station-logo-by-name lookup | **owner**, 2026-09-08, §10.12 |

### 10.15 Approved grouping / favourites preview — points 5 & 6 FINAL (2026-09-08)

**Owner sign-off: “as shown the preview will be implemented exactly.”** The
version of `design/iptv-channel-preview/` committed with this approval is the
**binding visual and interaction reference** for points 5 and 6, not an optional
inspiration. Visual sign-off is complete; production Flutter implementation
remains pending.

**Implementation fidelity contract:**

- Match the approved grouping/favourites marks, layout, spacing, glass material,
  hover/press/active states, motion, pill, accordion/sticky heads and bookmark
  interactions exactly at equivalent desktop sizes. No redesign, substitute
  glyphs, extra labels or simplified states without the owner's approval.
- The reference files are `index.html` / `style.css` (layout/material),
  `marks.mjs` (glyphs), `app.mjs` (interaction) and `model.mjs` (grouping,
  fallback, filtering and favourites semantics). Preserve this approved
  reference; future reference changes also require explicit owner approval.
- Port these approved behaviours into SALU's Flutter services/widgets. Browser
  `localStorage` is only a stand-in for production `shared_preferences`;
  simulated playback is not a replacement for `media_kit` / mpv. This approval
  does not mark any production Phase B code as implemented.
- Do **not** copy the study heading/footer, fixture-selector marks, reload-sample
  shortcut, fictional channels/logos, seeded favourites or illustrative still
  into the production app. They are explicitly preview-only scaffolding, not
  part of the approved grouping/favourites product UI.

**Runnable reference:** `design/iptv-channel-preview/index.html`.
Run from the repository root:

```sh
python3 -m http.server 8123 --bind 0.0.0.0 --directory design/iptv-channel-preview
```

- Default sample: 48 fictional channels, Flat view, fictional provider logos,
  a few seeded favourites, partial metadata and an `Unknown` group.
- The three **study-only** marks above the player select mixed metadata,
  category-only, or no grouping metadata. They are not new SALU app controls.
- Group pill: Flat / category / language / country, unavailable options dimmed,
  one expanded group, sticky heads and a chevron on a collapsed playing group.
- Row bookmark: hover-to-add, filled/always visible when saved; header bookmark
  filters favourites without flattening groups. The browser study uses
  `localStorage` to simulate saved favourites; production still uses
  `shared_preferences`. The queue is recreated in RAM, not persisted.
- Search, total-only count, reveal indicators, original-order Prev/Next,
  Stop/Play, clear + 5 s Undo and panel close/reopen are interactive simulations.
- `?sample=large` generates 50 000 synthetic records to exercise viewport-only
  DOM rows. **This is not a Dart/mpv performance or RAM benchmark.** Production
  image-cache byte limits, progressive M3U parsing and actual playback remain
  unimplemented. The backdrop is an AI-generated still, not a live channel.
- The preview's same-file `#EXTGRP` fallback is now **FINAL with point 5**
  (§10.2a); it is part of the approved implementation, not an outstanding proposal.
- See the study README for repeatable model/browser checks. **Points 5 and 6
  are approved in full as previewed**; only their production implementation
  remains pending. Validate the Flutter result against this committed reference.

### 10.16 Flutter / Dart M3U research — checked 2026-09-08

**Finding:** Dart has community playlist-parsing packages; Flutter's documented
video solution is a playback plugin, not a built-in IPTV directory/grouping/
favourites feature. The Flutter guide demonstrates `video_player` for playback;
it does not replace SALU's channel-list work. [1](https://docs.flutter.dev/cookbook/plugins/play-video)

- **`m3u_nullsafe`** is a Dart M3U/M3U-Plus parser with custom entry attributes
  and a `sortedCategories` helper. Its API takes the complete document as a
  `String` and returns a `Future<List<...>>`; that is not a progressive channel
  stream. The package README also explicitly lists streaming input as missing.
  [3](https://pub.dev/documentation/m3u_nullsafe/latest/m3u/)
  [5](https://pub.dev/documentation/m3u_nullsafe/latest/m3u/M3uParser-class.html)
- **`flutter_hls_parser`** handles HLS master/media `.m3u8` manifests. That is
  different from SALU's IPTV channel directory; the selected channel's HLS
  playback remains mpv's job. [1](https://pub.dev/packages/flutter_hls_parser/versions)
- **Keep `media_kit` / mpv for playback.** `media_kit` supports Windows and can
  open one `Media` or a `Playlist`; SALU already depends on it. No second player
  package is needed for this plan. [1](https://pub.dev/packages/media_kit)
  [4](https://pub.dev/documentation/media_kit/latest/)

- **`m3u_xmltv`** (v0.2.0, published 2026-08-13, MIT) is the **adopted base
  for M-2's parser** — owner, 2026-09-08. M3U directory parsing only; its
  XMLTV/EPG half stays unused (EPG is out of scope, §10.11).
  [1](https://pub.dev/packages/m3u_xmltv)

**Parser base — FINAL (owner, 2026-09-08): M-2 builds SALU's channel-directory
parser on `m3u_xmltv` 0.2.0, modified where needed to match the finalized
points, wrapped behind SALU's own parser interface, pure Dart, off the UI
isolate, and proven by SALU's own fixture suite before any channel UI exists
(M-2). This supersedes the earlier "no dependency was added" stance; it is
still adoption *with adaptation and tests*, not a blind dependency.**

Code-level check against the published source (2026-09-08) — why it is sound
for SALU, unlike `m3u_nullsafe`:

- Attributes parse **quoted and unquoted** (`key="v"` and `key=v`) — the
  quote-only regex that hurt `m3u_nullsafe` is not reproduced. `tvg-id`,
  `tvg-name`, `tvg-logo`, `group-title`, `tvg-language`, `tvg-country` arrive
  split into a typed entry (`rawAttributes` keeps anything else).
- Parsing is **line-state, not strict alternation**: blank lines, comments and
  junk lines between `#EXTINF` and the URL do not mis-pair names with URLs, and
  an `#EXTINF` with no following URL is dropped, not fused to the next entry.
- `#EXTGRP` is read natively (it may precede or follow `#EXTINF`).
- The title is everything after the **first comma** — channel names containing
  commas survive.
- **`parseStream(Stream<String>)` yields one entry at a time** — progressive
  batches (M-41), app-side cancellation and the byte ceiling all work; the app
  never holds the decoded text longer than its own fetch does.
- `parseBytes` takes an `encoding` (provider files in latin-1 etc.); VLC/Kodi
  header lines (`EXTVLCOPT`, `KODIPROP`) are captured per entry; lenient on a
  missing `#EXTM3U` header; no network use; ships its own M3U tests (EXTGRP,
  empty attrs, no-URL entries, invalid lines, encodings, streaming). MIT.

Required modification to meet SALU's finalized points (small, enumerated,
tested in M-2):

1. **Blank `group-title` must fall back to `#EXTGRP`** (point 5, §10.2a). The
   package resolves `group-title ?? #EXTGRP` only when `group-title` is
   *absent*; a real-world `group-title=""` wins and the entry's `#EXTGRP` value
   is lost. Treat blank as absent (`(group-title?.isNotEmpty ?? false) ? it :
   #EXTGRP`) — a one-line mapper patch (upstream-PR-able) or wrapper-level fix.
2. **Blank optional values → `null`** (point 2, §10.0). Empty quoted attrs
   parse as `""`, not null; map blanks to null at the wrapper boundary so
   `Unknown` and the ID-first fallback chain behave as finalised.
3. **Strip a UTF-8 BOM before the first line.** The parser does not, and a
   headerless file whose first line is `#EXTINF` would silently drop channel 1.
4. The package's own tests do **not** cover unquoted attributes, BOM, CRLF,
   commas inside names, the blank-`group-title`+`#EXTGRP` case, or large
   inputs — SALU's M-2 fixture suite below is still mandatory.
5. SALU-side, unchanged by adoption: HLS-directory detection at the fetch
   boundary, relative-logo/URL resolution, country/language alias
   normalisation, interning, precomputed search keys, `Unknown`-last grouping,
   and the bounded logo cache (§§10.2–10.4, 10.10).

Costs to accept at M-2: `m3u_xmltv` requires **Dart ≥ 3.12.2** (SALU's floor is
`>=3.4.0`) and pulls `equatable` + `xml` — the `xml`/XMLTV half is unused on
SALU's M3U path. Decide the SDK-floor/Flutter raise in M-1; if the raise is
unacceptable, vendor the M3U subset (MIT) with the §10.16 patch as the
fallback — same code, no floor change.

The required checks list stands and now gates the adapter, not the choice:
quoted/blank/missing/unquoted attributes, names containing commas, BOM/CRLF,
relative URLs, HLS-vs-directory detection, `group-title`-blank+`#EXTGRP`,
cancellation, byte limits, progressive batches, normalisation and shared
strings.

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
repeat-one and shuffle both answer "what plays next", **undock / dock itself**
(owner, 2026-09-07 — replaced by a Close ✕; recorded in §4.8 and §9 rows 19b
and 25–26), **the moving live shimmer** (owner, 2026-09-08 — "feels noisy to
see continuous moving"; replaced by a still soft light, §10.8a option A,
recorded in M30/M50), and **"the first implementation pass must cover §10
too"** (owner, 2026-09-07 — Phase A, the local playlist, comes first).
