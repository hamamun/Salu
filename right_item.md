# SALU — right_item.md (the right-button layer)

> **Purpose:** the working spec for SALU's right-mouse-button layer in **Player
> mode only** — five marks on the picture: shuffle · repeat · info · remote ·
> settings. Written as the handoff for the session that builds it.
>
> **Status:** DESIGN REVIEW — nothing here is locked and nothing is
> implemented. The owner reviews the preview first, answers §12, then the
> decisions land here as LOCKED and only then does code move.
>
> **Read first:** `follow.md` (the binding design contract), then `info.md`
> (the field inventory Info will show) and `salu_context.md` (phases).

Preview: `design/right-menu-preview/index.html` (+ its `README.md`).

---

## 1. The check the owner asked for, first

**Question:** may a window appear over the mpv video surface / the album-art
canvas, or is that blocked?

**Answer: allowed — over both. No exception needed, and nothing new is
required to make it work.**

The evidence, from Salu's own code:

| # | Fact | Where |
|---|---|---|
| 1 | mpv does **not** own a native child window in Salu. media_kit paints every frame into a **Flutter texture**, so ordinary Flutter widgets composite on top of it. | `video_screen.dart` — media_kit's `Video` widget inside a `Stack`, with `LyricsOverlay` / `AlbumArtView` stacked above it |
| 2 | Blurred glass over moving video **already ships**: the Playlist, Tracks and Tune panels are `BackdropFilter` surfaces floating over the picture. | `playlist_panel.dart`, `track_panel.dart`, `tune_panel.dart`, `glass_capsule.dart` |
| 3 | The texture is re-registered on **window resize only** — overlays are untouched by it. | `cc.md` §5 · D20, and the `ValueKey('video-…')` comment in `video_screen.dart` |
| 4 | Audio is **easier**, not harder: the album-art canvas and the lyrics view are plain Flutter widgets — no engine surface is in the way at all. | `album_art_view.dart`, `lyrics_overlay.dart` |
| 5 | Subtitles are drawn by **mpv into the texture**, so they stay *under* the menu. That is the correct order. | `cc.md` · D16 (mpv is the one subtitle renderer) |

**One honest cost:** `BackdropFilter` blurs a live surface every frame. Salu
already pays that for the panels — the menu adds exactly the same kind of
surface, only much smaller. Keep it small and it stays free.

**Where it must NOT appear:** Web mode. This is not a rule to remember — in Web
mode the player tree is not built at all (`home_screen.dart` · `if (!web)
_buildPlayer()`), so the gesture cannot exist there. Bonus: the WebView2
context menu is already switched off in the vendored engine
(`third_party/webview_windows/windows/webview.cc` ·
`put_AreDefaultContextMenusEnabled(FALSE)`), so a right-click on a page does
nothing today and nothing needs changing.

---

## 2. The five items — what already exists

| Item | State in Salu | What the menu adds |
|---|---|---|
| **Shuffle** | **Built.** `PlayerService.shuffleOn`, `toggleShuffle()`, `ShuffleMark` | a second door — the Playlist header keeps its pair |
| **Repeat** | **Built.** `PlayerService.repeatMode` (off → all → one), `cycleRepeat()`, `RepeatMark` with the repeat-one bead | a second door |
| **Info** | **Not built.** `info.md` holds the parked field inventory; Phase 9's About window is also unbuilt | the real new work — see §8 |
| **Settings** | **Built.** `SettingsDialog(initialTab:)`, already opened from the title bar; player doors open `general` | a door only |
| **Remote** | **Not built.** Phase 8 (WebSocket server) is not started; the Android app does not exist | blocked — see §9 |

---

## 3. Two concepts — the owner picks one (PROPOSED, not locked)

Both are built and live in the preview. Same five marks, same order, same
behaviour; only the arrival differs.

**A · the second row — RECOMMENDED.** One slim frosted strip, centred on the
cursor and dropped 10 px below it. Reads instantly, extends cleanly, and its
geometry is the panels' geometry (glass + hairline outline + radius).

**B · the ring.** The five marks bloom on a 58 px circle around the cursor,
staggered 20 ms apart — hairline glass, no rectangle anywhere, and its shapes
echo Salu's own circular grammar (the volume wheel, the Restart arc, the still
light). More Salu, harder to aim, harder to extend past five items.

**Decide:** A or B. (If A and B are still close after the preview, ship A and
keep B's arc in the notes — an arrival animation is a later, cheaper change
than a placement change.)

---

## 4. Marks — three reused, two new

Rule 6 says the family is closed and every new mark is drawn by hand in the
same stroke language. Geometry to add to `lib/ui/widgets/salu_marks.dart`
(stroke `markStrokeFor(size)`, round caps/joins, monochrome, ink from the
ambient `IconTheme`):

| Menu slot | Mark | Status |
|---|---|---|
| Shuffle | `ShuffleMark` | exists — reuse as-is |
| Repeat | `RepeatMark` (quiet / bead) | exists — reuse as-is |
| Settings | `DotGridIcon` (six dots) | exists — reuse as-is |
| Info | **`InfoMark`** | **new** — recommended proposal A: circle + i |
| Remote | **`RemoteMark`** | **new** — recommended proposal A: scan frame (four brackets + centre dot) |

**Legibility finding (from the preview's own true-size render, `design/right-menu-preview/marks-true-size.png`):** at the real 18–20 px
the circle-i, the scan frame, the six dots, the arc and the shuffle marks all
hold. **Remote proposal B (phone + arcs) fails at 20 px** — the two arcs merge
into the body and read as a blob. That is the exact reason a mark gets
rejected here. Do not ship B.

**Two more marks are needed later, not now:** a shuffle/repeat pair that
carries its state *without* the quiet-ink trick if the suspended state proves
too subtle in the real app — park until seen on a real build.

---

## 5. The strip (concept A) — geometry, matching the existing pitch language

| Property | Value | Why |
|---|---|---|
| Hit box per mark | **30 × 30** | the Playlist header's `_headerButton` size (`SaluIconButton(size: 30)`) — not a new number |
| Glyph size | **18 px** | the header's own mark size (`RepeatMark(size: 18)`) — stroke `markStrokeFor(18) ≈ 1.5` |
| Strip padding | **6 px vertical, 8 px horizontal** | reads as a capsule, not a toolbar |
| Corner radius | **12 px** | between the OSD deck (10) and the Open pill (21) |
| Inner pitch | **6 px** inside a group | rule 5's 6/14/26 rhythm |
| Group gap | **14 px** between the toggle pair and the door trio | same rhythm, nothing drawn around a group |
| Surface | `GlassCapsule` material — `BackdropFilter(18)` + `AppColors.glass` + `surfaceOutline` hairline | one material, never two |
| Drop from cursor | **10 px** | the cursor never sits under the strip |
| Edge nudge | **12 px** margin; the strip slides inward, the *cursor* is never moved | never opens half off-screen |
| Near the bottom edge | flips **above** the cursor | the same rule, the other way |

**Hover:** the shared recipe — ink glides `iconIdle → textPrimary` in ~120 ms,
mark scales **1.06**, nothing drawn behind it (rule 4).
**Hover chip:** after **600 ms** (`SaluIconButton`'s tooltip delay) a chip
names the control — reusing the timeline's `HoverChip` surface, width fitted
to the word. **The chip names, it never teaches** (rule 1) and never shows a
shortcut (rule 2).
**Press:** scales to **0.90** instantly, springs back.
**Arrival:** fade + scale 0.96 → 1.0, ~150 ms, ease-out cubic (rule 3) — the
strip fades in the way the settings window does.

---

## 6. Behaviour contract (this is the part that must not drift)

### 6.1 Right-click — close first, open second

Right-click already means something in Salu: it closes browser tabs, edits a
favourite, and closes the Playlist / Tracks / Tune panels (each panel's own
dismiss barrier already owns `onSecondaryTap`). The rule that keeps the
meaning honest:

> **A right-click closes whatever is open. It opens the menu only when nothing
> was open.**

Because the panels are mounted **above** the video in the same `Stack`
(`PlaylistPanel`, `TrackPanel`, `TunePanel` all sit higher than the picture),
their barriers eat the gesture first and this rule needs no extra code at the
menu's own layer. Verify it holds in the build; if a panel ever moves below the
menu layer, this rule has to be re-implemented by hand.

| Before the right-click | After |
|---|---|
| Playlist / Tracks / Tune panel open | panel closes, menu does **not** open |
| Menu open | menu closes |
| A door open (Info / Remote / Settings window) | the window closes |
| Nothing open | menu opens at the cursor |

### 6.2 Toggles stay, doors leave

- **Shuffle · Repeat** — the strip **stays open**; you flip both in one visit
  (quick-settings behaviour). State is reflected immediately in the mark.
- **Info · Remote · Settings** — the strip **leaves** first, then the surface
  arrives (rule 8: focus tasks are modals, live tasks are panels; the menu is
  neither and must not sit behind a modal).

### 6.3 The mark carries the state — nothing else

| State | How it reads |
|---|---|
| off | ink at ~55 % (`quiet`) — still hoverable |
| on | full white + a **very faint static glow** (follow.md §2: glow is for active states only) |
| repeat = one | the solid bead at the arc's centre (already implemented) |
| shuffle suspended by repeat-one | state kept, ink dropped to 55 % — **the header's existing rule, reused verbatim** |

No labels, no check marks, no text rows, no shortcut letters (rules 1, 2, 6).

### 6.4 Where the five items are allowed

| Item | Rule |
|---|---|
| Shuffle, Repeat | **dropped in channel mode** — live lists already drop both (`player_service.dart` · `_shuffleDriving`), and the channel header has no pair. Offering a dead switch is worse than offering four marks. |
| Info | live always; the *content* changes by what is loaded (media info / nothing loaded / channel) |
| Remote | live only when the server can actually answer (§9) |
| Settings | always live |

### 6.5 Esc, clicks and the chrome

- **Esc tiers (outermost first):** door → menu → panel. The panel tier already
  exists; the menu and door tiers slot in front of it without renumbering the
  rest.
- **A left-click on the picture** with the menu open **closes the menu and does
  nothing else** — it must never fall through and pause the video.
- **With the menu open, the chrome never auto-hides:** acquire `ChromeLock`
  (the exact recipe the panels already use, `ui_lock.dart`) on open, release on
  close/dispose.
- **One popup at a time** (rule 3): opening the menu is not allowed to leave a
  panel up, and vice versa — satisfied by §6.1's close-first order.

---

## 7. Where it goes in the code

| Piece | File | Kind |
|---|---|---|
| State (`rightMenuOpen`, maybe the strip's own tiny notifier) | `lib/core/panel_service.dart` | one notifier beside `playlistOpen` / `trackPanelOpen` / `tunePanelOpen` — "the one-popup world" already lives there |
| The strip, marks, doors wiring, placement, chip | `lib/ui/osc/right_menu.dart` *(new)* | one widget, built into `HomeScreen`'s player `Stack` **above** the video and **below** the OSD deck |
| Right-button detection | `lib/ui/screens/home_screen.dart` | a `Listener(onPointerDown:)` on the video layer reading `event.buttons == kSecondaryButton` — **not** `showMenu`, which is Material's own popup with ripples, boxes and Material text |
| `InfoMark`, `RemoteMark` | `lib/ui/widgets/salu_marks.dart` | two new painters in the family |
| Settings door | existing `SettingsDialog(initialTab: SettingsTab.general)` via `HomeScreen._openSettings` | no new window |
| Info surface | *decide first* — see §8 | new |
| QR / pairing payload | *blocked* — see §9 | |

**Why not Material's `showMenu`/`PopupMenuButton`:** they bring a rectangle, a
ripple, `MenuTheme` typography, elevation and shortcut labels — five separate
rule violations (rules 1, 2, 4, 6, 7). The menu is a SALU surface, drawn by
hand like every other one.

---

## 8. Info — the one genuinely new surface (DECIDE BEFORE BUILDING)

`info.md` is a **parked inventory**, and its own header says no field in it is
decided and nothing is implemented. What the Info door shows is a *design
decision*, not a build step:

1. **Merge Info and About.** Phase 9's About (app identity, mpv version,
   build, credits) and Info (what is playing) are one door with two faces —
   what is playing while something plays, Salu itself when nothing is.
2. **Info is a panel, not a modal** — the threshold in rule 8 is *used while
   watching*: reading the codec of the film in front of you is that.
3. **The field list comes from `info.md`, and only from it.** It marks its own
   uncertain items ⚠ — those get verified against the engine Salu ships
   (§7 of `info.md`, the harvest recipe) or dropped, never guessed.
4. **Audio/video/channel each get their own short list.** Four or five rows,
   read by type size alone, no labels — the `AlbumArtView` discipline.
5. **Live or frozen?** Live (bitrate, cache, fps) costs a read loop; frozen at
   open costs one. **Recommend frozen at open**, refreshed on reopen — live
   numbers turn a quiet surface into a dashboard.

---

## 9. Remote — blocked, and the block is real (DECIDE)

The QR itself is trivial. What it *points at* is not: Phase 8's server does not
exist and the Android app does not exist, so today a scan leads nowhere — and
rule 1 forbids explaining that with text.

Two honest routes, owner's call:

- **(a) Park it.** Ship the other four; Remote arrives with Phase 8 and the
  menu has four marks until then. *Recommended — nothing untrue is shown.*
- **(b) Design the payload once, use it twice.** The QR encodes address + port
  + token; the future app reads it as a pairing code, and until then the
  server (once built) answers the same scan with a compact dark page in the
  phone's browser. Note this brushes against `salu_context.md`'s "No PWA or
  WebView" line for the companion app — the page would be the *browser's*, not
  the app's, but the owner must agree.

Either way: **the QR is generated inside Salu**, and no QR dependency is added
until the payload is defined — a `qrcode` package is fine, but the payload
decision comes first.

---

## 10. Gating summary (build these as tests, not as comments)

| Condition | Menu |
|---|---|
| Player mode, nothing open, right-click | opens |
| Player mode, a panel is open | right-click closes the panel only |
| Player mode, menu open | right-click closes it |
| **Web mode** | **never** — the player tree is not built |
| **Mini mode** | **never** — the 32 px bar builds no popups |
| Channel (IPTV) list playing | opens with **four** marks (no shuffle/repeat) |
| Nothing loaded / STOPPED | opens; toggles idle-quiet, Info shows the app's own face |
| Clean screen, left-click | play/pause — unchanged, the menu never eats it |

---

## 11. Non-goals (say no now, not later)

- Not a Windows-style context menu: no text rows, no dividers, no shortcut
  column, no submenus, no checkmarks.
- **Not a place to grow.** Five marks is the ceiling; a sixth means the layer
  needs a different design, not a wider strip.
- Not a second home for the transport — play/pause/seek stay in the control row.
- Not in Web mode, not in mini mode, never over a modal.
- No new visible door is added for the menu itself: right-click is a bonus for
  people who already know the app, never the only way to anything.

---

## 12. Open questions — the owner answers these before code starts

1. **Concept A or B?** (§3)
2. **Info mark:** circle-i (recommended) or sheet? **Remote mark:** scan frame
   (recommended) or phone + arcs (fails at true size — see §4)?
3. **Info or About first?** Merge them (§8.1) or ship About as it stands and
   make Info a later phase?
4. **Frozen at open** (recommended) or live numbers? (§8.5)
5. **Remote:** park until Phase 8 (recommended) or define the payload now
   (§9)?
6. **Suspended shuffle ink:** keep 55 % (consistency with the header) or give
   the suspended state its own quieter-but-lit reading?

---

## 13. Tests to write (`test/right_menu_test.dart`)

Widget tests, in the style of `test/mini_bar_test.dart`:

1. Right-click on the player opens the strip; a second right-click closes it.
2. Left-click on the picture with the strip open closes the strip and calls
   **nothing else** (the play/pause facade is untouched).
3. A panel open → right-click closes the panel and the strip stays closed.
4. Shuffle and repeat taps **keep the strip open**; the marks flip state.
5. Repeat cycling reaches `one` and the bead is drawn; shuffle goes quiet while
   `one` is active and keeps its state.
6. Info / Remote / Settings taps close the strip before the surface appears.
7. Settings opens the existing dialog on the **General** tab.
8. `SaluMode.web` → right-click produces no menu (the tree is not even built).
9. Channel-mode queue → the strip builds **four** marks, no shuffle/repeat.
10. Edge placement: a right-click 4 px from each edge keeps the strip fully
    on-screen.
11. `ChromeLock` counts up on open and back to zero on every close path
    (Esc, click-outside, door, dispose).

---

## 14. Definition of done

- [ ] Concept locked in this file, §3 updated from PROPOSED to LOCKED.
- [ ] §12 answered and written into this file.
- [ ] `InfoMark` + `RemoteMark` added to the family, listed in the family's own
      header comment in `salu_marks.dart`.
- [ ] Strip ships with the §5 numbers — pitch and glass identical to the
      existing recipe, nothing invented.
- [ ] §10 gating table holds as tests.
- [ ] `flutter analyze` clean; `test/right_menu_test.dart` green.
- [ ] README's "What works right now" gains one line; `salu_context.md` Phase 4
      notes the layer under Slide-Out Panels & Menus.
- [ ] Seen on a real Windows build with hardware decoding on (blur cost over a
      live 4K texture is the one thing a test cannot prove).
