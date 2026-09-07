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
