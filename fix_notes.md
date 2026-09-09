# Pending fixes — playlist panel

> Captured during review (owner session, 2026-09-07).

## 1 · Auto-scroll / reveal to the playing row doesn't fire (shuffle / auto-advance)
**Status:** FIXED 2026-09-07 — see `_revealPlaying({force})`, `_onIndexChanged`,
`_onOpenChanged` in `lib/ui/panels/playlist_panel.dart`.
**Symptom:** panel is open during shuffle; the index jumps (e.g. row 3 → row 49)
but the list never scrolls to show the new row.

**Where it breaks (read from code):**
- `PlaylistPanelState._revealPlaying` returns immediately if `_userScrolled` is true.
- The reveal's own smooth `animateTo` can emit a trailing scroll notification
  *after* `_programmatic` flips back to `false`; that notification hits
  `_onScroll`, which sets `_userScrolled = true` for 3 s → next reveals skipped.
- The reveal only runs while `_panel.playlistOpen.value` is true at the instant
  the index changes.

**Not the cause:** the reveal already reads the live scroll metrics
(`hasPixels`, `hasViewportDimension`, `hasContentDimensions`, `pixels`,
`viewportDimension`, `maxScrollExtent`) and clamps to `maxScrollExtent`, so
drag-resize / maximize is handled automatically by Flutter.

**Fix direction:** don't let the reveal's own motion trip `_userScrolled`
(reset/guard it around the programmatic scroll), and always run the reveal on
index change while the panel is open.

## 2 · Fresh load should start from the first (top) visible row
**Verified by reading the code:** a fresh load
(`openFiles` / `openFolder` / drop-replace → `PlayerService.openPaths` →
`QueueService.setQueue(paths, 0)` + `_openQueueAt(0, fresh: true)`) sets the
queue index to 0 and opens the engine at playlist index 0 — the first (top)
row of the *same* sorted list the panel shows. So a true fresh load already
starts at row 0.

**Runtime question to confirm:** whether media_kit honors `Playlist(index:)` on
open. Irrelevant for index 0 (default), but matters for Next/Previous on
non-zero jumps.

**If a middle row is seen playing right after a load:** the load was likely not a
clean fresh load (e.g. files dropped *onto the panel* = append, which keeps the
currently-playing row) rather than a middle start index.

## 3 · Manual Next / Previous row does NOT reveal into view (same root cause as #1)
**Status:** FIXED 2026-09-07 — same `_revealPlaying({force: true})` change as #1
covers deliberate Next/Previous/row-click steps.
**Symptom:** with shuffle on, an *auto-advance* jump scrolls the new row into view,
but pressing the **Next** / **Previous** buttons does not bring the new playing row
into the visible area.

**Verified by reading the code:** manual and auto-advance share the exact same path —
`TransportActions.next()/previous()` → `PlayerService.next()/previous()` →
`_openQueueAt(target)` → `QueueService.setIndex(target)` →
`PlaylistPanel._onIndexChanged` → `_revealPlaying()`. There is NO separate code that
skips the reveal for manual navigation.

**Why it still differs in practice:** the only gate that silently skips the scroll is
`_revealPlaying`'s first line `if (_userScrolled) return;`. So a manual step that
lands within ~3 s of a manual scroll (or a stray scroll notification) is suppressed,
while an auto-advance that lands in a gap reveals. A deliberate Next/Previous is a
navigation the user explicitly asked for, so it should **always** reveal, even right
after a scroll.

**Fix direction (extends #1):** on a deliberate index change (auto-advance, Next,
Previous, row click) force the reveal regardless of `_userScrolled`; only a *manual
scroll* should suppress the reveal, and only briefly.

## 4 · Channel list renders empty — the rows area collapses to 0 × 0
**Status:** FIXED 2026-09-08 — `_channelRowsArea` (`fit: StackFit.expand`) and
`_SaluScrollView` (the list is the Stack's non-positioned child) in
`lib/ui/panels/playlist_panel.dart`.
**Symptom (owner, Phase B):** an m3u loads and plays, the channel header shows
(group-by · favourites · search with the channel count · bin · close), but the
rows area below it is blank — the channel list that the M-3/M-4 build listed
"just fine" is gone. No exception, no red box, nothing in the terminal.

**Root cause (layout, not data).** The queue held every channel the whole
time; the list was laid out at zero size, so it painted nothing.

- Local mode: `Expanded → _rowsArea → _SaluScrollView`. `Expanded` passes
  **tight** constraints, so the scroll view's inner `Stack`
  (`Positioned.fill(list)` + the thumb) inherited `minHeight == maxHeight` and
  filled the panel. That is why Phase A — and Phase B before the channel UI —
  always looked right.
- Channel mode (M-5): `_channelRowsArea` wrapped the same scroll view in a new
  `Stack` (for the sticky head and the edge chevrons). A `Stack` with the
  default `StackFit.loose` lays out its non-positioned children with
  `constraints.loosen()` → `minHeight` becomes **0**.
- `RenderStack` sizes itself to `Size(max(minWidth, …), max(minHeight, …))`
  over its **non-positioned** children only (`rendering/stack.dart`,
  `_computeSize`). Inside `_SaluScrollView` the list was `Positioned.fill`, so
  the *only* non-positioned child was the thumb's `SizedBox.shrink()`
  placeholder (0 × 0) whenever the thumb was not drawn. With a loosened
  `minHeight` the inner Stack therefore measured **0 × 0**, and
  `StackParentData.positionedChildConstraints` handed the list
  `BoxConstraints.tightFor(width: 0, height: 0)`. The `ListView` was laid out
  at zero size and painted nothing — no exception, no overflow stripe, and not
  even the Stack's clip (`_hasVisualOverflow` stays false when the child is
  zero-sized). `LayoutBuilder` passes its constraints straight down and takes
  `constraints.constrain(child.size)`, so the collapse propagated up unchanged.
- The `ListView` still existed with clients, at `viewportDimension == 0`. That
  is why the scrollbar drew nothing (`viewport <= 0` guard) and why the edge
  chevron chip (§10.6) sat there pointing at a list nobody could see: with a
  zero-height viewport the playing row is always "off screen".

**Fix.** Two independent guards, so the collapse cannot come back through a
future wrapper:
1. `_channelRowsArea` builds its Stack with `fit: StackFit.expand` — the rows
   view gets the same tight box the local list gets from `Expanded`.
2. `_SaluScrollView` makes the scroll view itself the Stack's non-positioned
   child (the thumb stays positioned). `RenderViewport` is `sizedByParent`
   with `size == constraints.biggest`, so it fills any bounded box, loose or
   tight: the local (tight) caller measures exactly as before, and the channel
   caller can no longer collapse.

**Verified against the framework source** (`flutter/flutter@stable`):
`RenderStack._computeSize` (non-positioned-only measurement,
`StackFit.loose → constraints.loosen()`, `StackFit.expand →
BoxConstraints.tight(constraints.biggest)`),
`StackParentData.positionedChildConstraints`, `_RenderLayoutBuilder.performLayout`,
`RenderViewport.computeDryLayout`, `RenderFlex._constraintsForFlexChild`
(`Expanded` + `stretch` = tight on both axes — why local mode never collapsed),
and `RenderBox.hitTestSelf == false` for the childless `SizedBox` that
`StackFit.expand` now stretches (it cannot swallow a row click).

**Not the cause (checked and cleared):** the parser and the progressive batches
(ported and exercised over CRLF/BOM/tiny-chunk inputs — every channel is
emitted), `QueueService.setItems`/`appendItems` notification, the descriptor
cache and `ChannelGrouping.descriptors` (Flat returns one row per filtered
index), and the isolate batch typing.

### 4a · Three "channel failed to load" lines for one dead channel
Same session, same log. `_onEngineError` printed one line per **mpv error
line**, before `ChannelSkipPolicy` decided anything — and one dead stream emits
several. The policy was already correct (one strike, one toast, one skip); only
the log lied, and it read like three dead channels. The line now reports the
*decision* — `skipping to the next` / `staying put (n in a row)` /
`channel error ignored (duplicate report)`.

### 4b · "Lost connection to device." is not a crash
`_CloseGuard.onWindowClose` (lib/main.dart) flushes the resume + favourites
stores and then calls `exit(0)`. The VM service socket dies with the process,
so `flutter run` reports "Lost connection to device." on every normal window
close. Nothing crashed in the pasted log.
