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

## 5 · Failed channel: drop the guard + the auto-advance, toast only
**Status:** FIXED 2026-09-09 — `PlayerService.reportChannelFailure`,
deleted `lib/core/m3u/channel_skip_policy.dart`.

**Symptom:** a dead channel showed the same buffering spinner as a slow one,
the terminal said `channel error ignored (already playing — buffering stall)`,
and no toast appeared — the proven/buffering guard swallowed the real failure.
Separately, the failure auto-advance (skip-to-next + 3-strike cascade) fought
the guard and surprised the viewer.

**Fix:** removed the guard (`_channelProven`, the 5 s prove timer, the
`isBuffering` gate), removed the whole auto-advance (`ChannelSkipPolicy`,
strikes, `_lastOpenWasAuto`, `OsdFailedCard.lingering`). Every engine error in
channel mode now toasts `Failed to load` + the channel's name and stays put.
One dead channel still reports once (per-index dedup; every fresh open
resets it, so zapping back re-reports). Local-mode errors unchanged (log only),
post-Stop errors stay silent (`hasMedia` gate). Panel reveal simplified to the
deliberate path only — the auto branch could never trigger again.

## 6 · Prev/Next in grouped mode jumped back to the old category
**Status:** FIXED 2026-09-09 — new `lib/core/channel_view_service.dart`,
`ChannelGrouping.membersOf`/`stepTarget`, panel state moved into the service.

**Symptom:** grouped by Category, playing news `aaa`, then zapping to a Music
channel — Prev/Next landed back in news `aaa`'s neighbourhood instead of
stepping through Music. Flat mode felt fine.

**Cause (confirmed in code + by owner check: the music zap DID switch video
and title):** Prev/Next stepped raw playlist order (`queue.index ± 1`) and
knew nothing about grouping, which was display-only panel state. In Flat the
shown order IS the raw order, so it felt right; grouped, the raw neighbour of
a music channel is usually another group's channel (in a small list, literally
`aaa` itself), and the deliberate-zap reveal then snapped the accordion back to
News — looking like the music pick was forgotten.

**Fix:** Prev/Next now walk the open group in list order and park at its edges
(no wrap, matching the channel no-wrap rule); from outside the open group they
step INTO it (Next → first, Previous → last); Flat / collapsed accordion /
active search (grouping suspended, §10.3) / stale key fall back to raw order.
The favourites filter does not affect stepping. Grouping state moved from the
panel widget into `ChannelViewService` so keyboard steps and closed-panel steps
follow the same shown order; the transport buttons listen to it so their dim
states refresh on grouping changes. Member list is cached per
(list, mode, group, search) so dim reads never rescan 50 000 rows (§10.10c).

## 7 · Typing M/S/Space/arrows in the playlist filter fired transport shortcuts
**Status:** FIXED 2026-09-15 — typing guard in `HomeScreen._onKeyEvent`
(`lib/ui/screens/home_screen.dart`, `_isTyping`).

**Symptom:** pressing M in the playlist filter muted/unmuted instead of typing
"m". Same class for S (stop), Space (play/pause), arrows (seek/volume instead
of caret), Z/X (subtitle sync), PgUp/PgDn (track step).

**Cause:** the window-wide key handler treated bare single keys as transport
shortcuts unconditionally; the filter's field wrapper only consumed Esc, so
every other key bubbled up and got swallowed before producing text.

**Fix:** `_onKeyEvent` now checks whether the focus sits inside an
`EditableText` and yields all bare single-key shortcuts while typing (Ctrl
combinations stay global — they never insert text). One guard covers every
affected key, including Shift+Arrow text selection.

## 8 · Maximize → fullscreen → restore left stale icons, then killed pointer input + painting
**Status:** FIXED 2026-09-15 — new `lib/core/window_state_service.dart`;
`FullscreenControl` + `CustomTitleBar` rewired to it; started in `main`.

**Symptom:** maximize → fullscreen → title-bar restore: window shrank but the
fullscreen button still showed "exit fullscreen". Clicking it then left a
screen-covering window showing only video — no chrome on hover or keys, clicks
dead — while transport keys and playback kept working. Any clean resize
(Win+D, Win+Down) healed it.

**Cause (traced against window_manager 0.5.2 native code + owner testing):**
the two buttons kept separate state memories. The title-bar restore bypassed
the fullscreen system (plugin flag + event machine went silent — no
unmaximize / leave-fullscreen event), so the fullscreen button lied and the
next click sent `setFullScreen(false)` to an already-windowed window. That
raced restore routine (style swap + manual Flutter-view resize + async
re-maximize) corrupted the engine's view state: pointers dropped, framework
frames frozen, while key dispatch, audio, and direct video textures kept
going. Proven by: Ctrl+L opening the panel invisibly (visible after heal),
actions working with no OSD card.

**Fix:** one shared window-state memory (`isFullscreen` / `isMaximized`
notifiers) with live OS re-reads after every command and on every window
event (focus heals external Win+Down/taskbar changes); restore-while-
fullscreen diverts through the clean `setFullScreen(false)` path; fullscreen
toggle reads live state before acting so "exit" can never fire while
windowed. The step-4 trigger is unreachable.

## 9 · Clear browsing data dialog: Cookies & cache badges stuck at the pre-clean sizes
**Status:** FIXED 2026-09-17 — `lib/core/web/web_data_control.dart`
(discovery-based footprint + live cache sweep + purge-aware reporting),
`lib/ui/widgets/browser_clear_dialog.dart` (queued-purge note),
tests in `test/web_data_footprint_test.dart`.

**Symptom:** after "Clear data", Browsing history correctly drops to
"None", but Cookies & site data stays at e.g. "46 MB" and Cached images
& files at "1.8 MB" forever — the cleaning looked like it did nothing.

**Cause (traced):**
- While the engine runs, the profile folder cannot be deleted, so the
  clear marks it for the next-startup purge — but the reopened dialog
  re-scanned the unchanged folder and reported the stale pre-clean size,
  never the pending purge.
- The plugin's `clearCookies` / `clearCache` are only DevTools calls
  (`Network.clearBrowserCookies` / `Network.clearBrowserCache`): they
  empty the live cookie jar and the in-memory HTTP cache, but never
  touch Local Storage / IndexedDB / Service Workers (the bulk of the
  "cookies" size) or GPUCache / ShaderCache / Code Cache (the leftover
  "cache" size).
- The cookies measurement had a bogus fallback: when the hardcoded
  paths didn't match, it reported **whole profile size minus cache** —
  counting Crashpad, preferences, runtime internals — a permanently
  inflated number no clean could ever reduce ("not proper SALU data").

**Fix:**
- Footprint now discovers stores by their well-known Chromium names
  (cookie jars, Local/Session Storage, IndexedDB, Service Worker,
  Shared Storage · Cache, Code Cache, GPUCache, ShaderCache, DawnCache)
  wherever the runtime parked them in the profile, depth-capped; the
  whole-profile fallback is gone, so only real browsing data is ever
  measured.
- `clear(cache)` additionally deletes on-disk cache files the running
  engine does not hold locked (Chromium cache entries are
  delete-shareable), so the cache badge genuinely shrinks mid-session.
- When a purge is queued, `measureFootprint` reports the locked
  cookie/cache stores as cleaned ("None") instead of the stale size,
  and the dialog shows a short "Already cleaned — locked files are
  wiped next time SALU starts" note. Next startup's purge then
  physically removes the folder before the environment exists, and the
  badges measure the fresh profile.
