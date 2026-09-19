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

Right-click the picture and five marks arrive at the cursor —
**shuffle · repeat · info · remote · settings** — in a slim frosted strip
(concept **A**) or blooming around the pointer (concept **B**). Toggles stay
open; doors leave. Player mode only.

## What it demonstrates

| Behavior | Decision |
|---|---|
| Overlay over mpv video **and** album art | Allowed — both are Flutter textures/widgets; Salu already stacks glass panels there (§0 of the page) |
| Two concepts, switchable live | A · **the second row** (recommended) · B · **the ring** |
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
| Esc tiers | door → menu → panel |
| 5 marks is the ceiling | a sixth means a different design |

## Keys in the preview (reviewer conveniences, not the shipping design)

| Key | Does |
|---|---|
| Right-click on the picture | opens the menu at the cursor |
| `Esc` / left-click the picture | closes, in the order door → menu → panel |
| `I` | swaps the Info mark between proposal **A** (circle-i) and **B** (sheet) |
| `R` | swaps the Remote mark between proposal **A** (scan frame) and **B** (phone + arcs) |

The **Playlist panel** button in the toolbar exists only to prove the
close-first contract; the **Reset states** button clears the toggles.

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

**The finding:** at true size the circle-i, the scan frame, the six dots, the
arc and the shuffle marks all hold. **Remote proposal B (phone + arcs) does
not** — the two arcs merge into the body and read as a blob. Recommend
**Info A** and **Remote A**.

## Handoff

`right_item.md` (repo root) carries the implementation points for the build
session — state recipe, injection point in `home_screen.dart`, gesture
contract, gating rules, tests and the definition of done.
