# Mini bar preview

Interactive mock for `mini.md` — open `index.html` in any browser, or serve
this folder (`python3 -m http.server`). No build, no media: playback is faked.

**v5 (final):** padding compression — hits 26×30, group pitch 5/11/20
(same rhythm as the full cluster's 6/14/26), tighter icon gap, margins
and padding. Bar **488 px**, title keeps its full ~141 px. Rule:
shrink the space, never the glyphs. Preview and `mini.md` (FINAL, v5)
are locked to this pass.

**v4 (after feedback):** the in-row volume bar is replaced by a literal
**volume wheel** — a thin 20 px ring dial (track ring + level arc from
12 o'clock + head tick) right after the speaker. Wheel-only ±5 %; the
exact % rides the title swap and tooltip. Bar width ~543 px.

**v3 (after feedback):**

1. **Previous mark fixed** — its skip-bar now rides the pointing edge
   (exact mirror of Next, `|<<`), matching `transport_marks.dart`.
2. **Volume bar back in the row**, right after the speaker — 96×14, value
   inside, **wheel ±5 % only**. The hover-reveal lip from v2 was
   abandoned: the gap between the bar and the lip made it impossible to
   reach before it vanished. Bottom-edge micro sliver removed with it.

Carried forward from v2: **always alive** (no fade/sleep ever),
**progress line on the TOP edge** (click to seek). Glyph fidelity unchanged:
paths from the real `transport_marks.dart` painters, the real
`SaluIconButton` hover recipe (mark brightens, ×1.06, no box), group
pitch 6 / 14 / 26.

| Preview behavior | mini.md section |
|---|---|
| 32 px fixed strip, ~488 px, Salu group order + real marks | §2, §3 |
| Previous = `|<<`, mirror of Next | §3 Group 2 |
| Volume bar in-row after the speaker, wheel-only | §3 Group 4 |
| Position = top edge, click to seek | §3 "Edge meter" |
| Title swaps as the only feedback | §6 |
| No fade / no sleep, ever | §7 |
| Esc / ⤢ / double-click dead space → restore pulse | §4 |
| What changed and why | §11 Change log |

Not reflected here (real-app concerns): always-on-top, min=max window
lock, geometry save/restore, single-instance routing, video-as-audio.
