# Right-click layer — interactive preview

Static, self-contained mock (`index.html`) of the proposed **right-button menu**
for SALU's Player mode. Review artifact only — not the real player, no Flutter
code, nothing wired into `lib/`.

## Run

```bash
cd design/right-menu-preview
python3 -m http.server 8533 --bind 0.0.0.0
# → http://localhost:8533
```

(Or just open `index.html` in a browser.)

## The idea in one line

Right-click the picture and four marks arrive at the cursor —
**shuffle · repeat ‖ info · settings** — in a slim frosted strip (**concept A ·
the second row**). Toggles stay open; doors leave. Player mode only.

> **Superseded 2026-09-20.** Remote is no longer a reserved empty seat. `remote.md`
> **D9** puts it as the **last** item, after Settings — not between repeat and Info —
> and the stale comment in `right_menu.dart` that reserved the old slot must be
> rewritten. The QR door, the pairing panel and the phone it pairs with are built out
> in `design/remote-preview/`. This page still shows the four-mark strip as locked.

## Status: locked (2026-09-19)

| Thing | State |
|---|---|
| Concept **A · the second row** | ✅ LOCKED — the default view of this page |
| **Info mark = the sheet** | ✅ LOCKED (the circle-i proposal was dropped by the owner) |
| **Remote** | ↗ moved out of this page — **D9** makes it the **fifth and last** seat. See `design/remote-preview/` |
| **Suspended shuffle** | ✅ 55 % ink + the chip reading `Shuffle · suspended` |
| Concept B · the ring | ⏸ parked, not rejected — still switchable in the toolbar |

The owner picked **A · the second row** from this page; it is now the design of
record in `right_item.md` §3. **B · the ring** stays switchable here as a parked
alternative — not rejected, not built.

| Concept | State |
|---|---|
| **A · the second row** | ✅ LOCKED 2026-09-19 — the default view of this page |
| Info mark · Remote mark | ✅ LOCKED to proposal A in both cases (press `I` / `R` to compare) |
| B · the ring | ⏸ parked (the staggered arrival is the one piece worth borrowing later) |

## What it demonstrates

| Behavior | Decision |
|---|---|
| Overlay over mpv video **and** album art | Allowed — both are Flutter textures/widgets; Salu already stacks glass panels there (§0 of the page) |
| Two concepts, switchable live | A · **the second row** (**LOCKED**) · B · **the ring** (parked) |
| Right-click closes first (panel → door → menu) | follow.md rule 3's one-popup world; the panels' own dismiss barriers already own the gesture |
| Opens only on a clean screen | else the menu would fight the panel it just closed |
| Shuffle / repeat = **toggles that stay** | one visit flips both; the Playlist header keeps the same two controls |
| Info / Remote / Settings = **doors that leave** | menu closes, its surface arrives |
| Mark carries the state | quiet 55 % ink = off · white + faint glow = live · bead = repeat-one |
| Shuffle suspended by repeat-one | 55 % ink, state kept — the header's existing rule |
| No labels, no shortcuts, no boxes | follow.md rules 1, 2, 4, 6 |
| Hover: light + 1.06, press: 0.90, chip at 600 ms | the shared recipe + `SaluIconButton`'s tooltip delay |
| Pitch-only grouping | 6 px inside a group, 14 px between the toggle pair and the door trio |
| Edge nudge | the strip slides inward near the window edges; the cursor is never moved |
| Web mode = nothing | by construction: the player tree is not built while the browser owns the window |
| Mini mode = nothing | the 32 px bar builds no popups, and this is not the exception |
| Channel (IPTV) lists | repeat + shuffle dropped, as the channel header already drops them |
| Esc tiers | door → info panel → menu → playlist panel |
| **Info opens as a LEFT panel** | `info.md` §0 — left edge, top at the chrome block's bottom (148 px), 322 wide (the Playlist panel's width, mirrored) |
| **The Open pill ↔ Info, both directions** | the measured collision: the pill spans y 142–184 while the chrome ends at 148, so 36 px of it lands in the panel's strip. Opening either closes the other — one popup at a time |
| The mock's chrome is the real one | 40 px title strip + 108 px control row = 148, with the `+` and its pill drawn at their true offsets |
| Info re-reads on a media change, stays open | unlike the Track panel, which closes — it describes what is playing |
| The media switch in the toolbar | proves the presence rules: **video** = Picture + Clock & file · **audio** = no Picture group · **live** = no Clock & file, Stream instead |
| A group with nothing to say is not drawn | and a row with no truth is not drawn — never `—`, never `N/A` |
| Four marks ship — and four is the working ceiling | Remote's reserved seat is the fifth; a sixth means a different design |

## Keys in the preview (reviewer conveniences, not the shipping design)

| Key / gesture | Does |
|---|---|
| Right-click on the picture | opens the menu at the cursor |
| `+` in the control row | opens the real Open pill (and closes Info, if it is up) |
| `Esc` / left-click the picture | closes, in the order door → info panel → menu → pill → playlist panel |

The **Playlist panel** button exists only to prove the close-first contract,
the **media switch** (video · audio · live channel) exists only to prove the
presence rules of `info.md` §0.5, and **Reset states** clears the toggles.

## Marks

Drawn from the real painters, not from a stock set — `RepeatMark` (¾ arc, bead
at `0.09 × size`), `ShuffleMark` (crossing rules + chevron-V heads),
`DotGridIcon` (six dots, `dot = clamp(size × 0.17, 1.6, 4)`), stroke
`markStrokeFor(size) = clamp(size × 0.085, 1.4, 2.2)`. Only **Info** and
**Remote** are new; both are shown in two proposals each.

Two static renders sit beside this file, produced from the same geometry the
page draws (not exported from Flutter — the shapes were rasterized offline for
review):

| File | What it is |
|---|---|
| `marks-row.png` | the eight states enlarged — repeat off · repeat one · shuffle · settings · info A · info B · remote A · remote B |
| `marks-true-size.png` | the same row at **true UI size (20 px)**, then magnified with nearest-neighbour so the blur is honest |

**The finding:** at true size the **sheet**, the six dots, the ¾ arc and the
shuffle marks all hold. A phone-with-arcs proposal did **not** — its two arcs
merged into the body and read as a blob, which is the bar every new mark is
judged against. The Info mark is now locked to the sheet.

## Handoff

`right_item.md` (repo root) carries the implementation points for the build
session — state recipe, injection point in `home_screen.dart`, gesture
contract, gating rules, tests and the definition of done.
