# SALU Remote — interactive preview

Static mock (`index.html` + `app.js`) of the two halves of the Remote
workstream, side by side:

- **the PC side** — the right-click strip with its new **Remote** seat, and the
  **Remote** pairing panel with a real, scannable QR (`remote.md` §10.1–10.3);
- **the phone side** — the whole SALU Remote APK surface, all three tabs
  (`remote_apk_ui.md` v2).

Review artifact only. Not the real player, no Flutter code, nothing wired into
`lib/`. The APK is a separate later project (D1) and the PC side is specced but
not built; this page is how both are meant to look and behave before either is.

## Run

```bash
cd design/remote-preview
python3 -m http.server 8123 --bind 0.0.0.0
# → http://localhost:8123
```

(Or just open `index.html` in a browser — `app.js` is a classic script, so
`file://` works too.)

## The idea in one line

Right-click the picture, take the **fifth seat** at the end of the strip, and a
QR arrives on a white card. The phone scans it, and from then on the phone's
three tabs — **Play · Browse · Tune** — drive the PC over one WebSocket, with
**full state snapshots only**, never diffs (D5).

## How to look at it

Everything is wired: press things on one side and watch the other follow.

| Do this | Watch |
|---|---|
| **Right-click the picture** | the strip arrives with five seats — shuffle · repeat ‖ info · settings · **remote** — at the new `198 px` width (§5.3) |
| **Take the Remote seat** | the strip closes *first*, then the panel opens. Same `_door()` every other item uses |
| **Look at the QR** | it is a real code for the real payload, drawn by an encoder that ships in this page |
| **Close and reopen the panel** | a **new** code (A5) — one photographed over a shoulder stops working |
| **Scan / Enter a code** on the phone | the phone pairs, the PC logs `auth` → `auth_ok` → a full `state` |
| **Tap the mode pill** on the phone | the PC's canvas follows into Web mode; switch the PC and the pill follows back |
| **Browse → Files → tap a row** | the file never travels. The phone sends a **path**, the PC opens it locally — a 40 GB file costs one message |
| **Drag an EQ band** | the curve follows, the preset turns to **My**, and `eq_set` carries all ten gains |
| **Switch to Web, then open Tune** | the equalizer is gone and a D-pad is there instead. Walk it with `▲▼` and watch the ring move on the PC's page |
| **Turn Remote off** in Settings | the port frees, `Show pairing code` disables, no QR is offered, and the phone drops to its offline body (D10) |
| **Watch the socket panel** | every line is a real §6 frame. Press anything and read what actually goes over the wire |

Toolbar: **Switch PC to Web/Player mode** drives the PC side directly (to prove
the pill follows), **Forget the phone** breaks the pairing, **Reset** returns
everything to the opening state. `Esc` closes panel → sheet → strip.

## The QR is real

The panel does not draw a picture of a QR code. `index.html` carries a
hand-written byte-mode encoder (versions 1–10, levels L/M/Q/H) that builds the
actual pairing payload:

```
salu://pair?v=1&n=DESKTOP-ABC&h=192.168.0.12&p=7258&c=7K4MQP2X
```

62 characters → **version 4, 33×33**, rendered at **208 px** on white with a
12 px quiet zone and no animation (§10.2 — a dark code on dark glass scans
badly). The payload is a `salu://` URI, so any camera app can read it even
before the app exists.

It is verified, not trusted:

```bash
node design/remote-preview/qr_test.mjs     # needs: pip3 install qrcode
node design/remote-preview/preview.test.mjs # needs: npm i jsdom (outside the repo)
```

`qr_test.mjs` imports the exact encoder block out of `index.html` and demands a
module-for-module identical matrix from Python `qrcode` 8.2, with the reference's
own mask choice — 12 payloads across versions 1, 2, 4, 5, 6, 7 and 8 and all four
levels. `preview.test.mjs` then loads the page into a DOM, drives it, and compares
**the modules the page actually drew** against the same oracle, so a regression in
the encoder shows up as a broken panel rather than as a passing unit test.

Two things in that encoder follow the `qrcode` reference library rather than a
literal reading of the standard, both recorded in the source: masks are scored on
a grid whose 15 format cells are blanked, and rule 1 scores a run of *n* as
*n − 2*. Every mask still yields a valid symbol; this only decides which one other
tools would pick.

## What it demonstrates

### PC side

| Behavior | Decision |
|---|---|
| Remote is the **last** seat, after Settings | **D9** — supersedes the old `right_menu.dart` comment that reserved the slot "between repeat and Info". That comment must be rewritten |
| Strip widths `82 → 118`, `162 → 198` | §5.3 — `30+6+30+14+30+6+30+6+30 + 16 = 198` on the full canvas (buttons 30, gaps 6, one 14 divider, capsule 16) |
| The strip closes before the panel opens | the shared `_door()`; one popup at a time |
| QR on a **white** card, no animation | §10.2 — dark-on-glass does not scan |
| The code rotates when the panel closes | **A5** |
| Status line, three of the five spec'd shapes | `● Connected · Wi-Fi · 192.168.0.12 · 7258` · `○ Waiting for your phone` · `Remote is off — turn it on in Settings`. §10.2 adds `Starting…` and `Couldn't start the remote (port busy)`, which need a real socket to be honest about |
| Footnote under the code | "This code is only for pairing. It changes when you close this panel." |
| Remembered phones, `Forget` with no confirm | §10.2 — names only, never tokens or IPs |
| The firewall hint, one line + one button | appears only while waiting, never as a wall of text |
| The panel never auto-closes | a QR that vanishes mid-scan is worse than one that lingers |
| Settings section, after the Equalizer block | §10.3, `_AutoEqSwitch` layout. Two switches + two rows |
| `Let phones browse PC files`, default ON | **v1.1** §17.6 — read-only, folders and media names only |

### Phone side

| Behavior | Decision |
|---|---|
| Three tabs, **Play · Browse · Tune** | `remote_apk_ui.md` §2 — Tune groups EQ, subtitles and audio because all three are meaningless with nothing playing |
| The header is one line: dot · name · chevron · ⋮ | §3 — the connection state is always visible, never a whole screen |
| The mode switch shows **both seats** | Not one pill that toggles — `Player` and `Web` sit side by side on the phone header and in the toolbar. Pick either; the other side follows |
| Web mode shrinks the remote | §4.2 shape 1 — back · forward · reload · full · tabs, then the **page's own** player. Dead buttons make an app feel broken |
| Web mode with no media on the page | §4.2 shape 2 — the nav body only; the transport rows are hidden rather than sitting there dead |
| **Browse greys out in Web mode** | Opening a PC file pulls the PC straight back to Player mode (**D8**), so the tab would only ever bounce you. Tapping it says why; switching to Web moves you off it |
| **Tune becomes a D-pad in Web mode** | No equalizer, no subtitles, no audio track — mpv is not in the picture. `▲▼` walk the page's focus, `◀▶` are history, `OK` clicks |
| **The PC draws a ring on the focused element** | The part that makes the D-pad usable at all — with no visible focus the phone steers the browser blind |
| The page's volume slider is the site's | §4.2 — it never touches the Windows volume |
| Transport `⏮ ⟲10 (▶72) ⟳10 ⏭` + chips + volume + collapsible queue | §4.1 — the queue card holds five rows and keeps the playing one inside them |
| A **transport** command in Web mode pulls SALU back to Player | **D8** — the phone talks to the page's player in Web mode, not to mpv |
| Side keys reuse `browser_nav`; arrows and OK send `web_key` | **`web_key {key}` is a NEW verb.** §17.4 defines `browser_nav` and the `web_media_*` family but nothing that moves focus. It would be injected JavaScript through the same `WebTab.executeScript` path `remote_web_media_bridge.dart` already uses |
| Volume and mute raise **no** OSD card | **A1** — you are already looking at your phone |
| Browse mirrors the PC's own folders; Streams mirrors `UrlLibraryService` | §5 — never a second list living on the phone |
| `⋯ 480 more` + `⚙ filters` | §5.1 — a folder is paged, not scrolled forever |
| Read-only, forever | §5.1 — no delete, no rename, no move |
| Files and media only, never paths in titles | **A3** |
| The PC's own EQ presets and its own speed stops, verbatim | §6.1 — the phone renders what the PC sends, so the two can never disagree |
| `±0.5s` subtitle sync, search, add-file, auto-download | §6.2 — the PC downloads and applies; the phone only asks and watches |
| Tune says **"Nothing is playing"** + a Browse shortcut | §6 — one place, instead of dead sliders. Player mode only — in Web mode Tune is the D-pad and needs no media |
| The mini bar while another tab is up | §3 — one line, and tapping it returns to Play |
| Every message is a full snapshot | **D5** — `rev` monotonic, `at` for latency, no `event` type in v1 |

## Marks

Drawn from the real painters, not a stock set: `_ChevronPainter` (apex
0.66/0.46/0.42), `_PausePainter` (0.36/0.64, y 0.24–0.76), `_StopPainter` (hollow
rounded square 0.58 s), `_RepeatPainter` (¾ arc r 0.32 s, bead 0.09 s),
`_ShufflePainter`, `_InfoPainter` (the sheet), `DotGridIcon` (six dots,
`clamp(size × 0.17, 1.6, 4)`), stroke
`markStrokeFor(size) = clamp(size × 0.085, 1.4, 2.2)` — 1.53 at the 18 px these
are used at.

New for this design: **`QrMark`** (three corner finder squares + a sparse dot
field, §10.1) and the phone-side set from `remote_apk_ui.md` §9 — folder, drive,
media, subtitle (CC), equalizer, globe, link, fullscreen, chevron, search and
queue. Same recipe throughout; at phone sizes the floor is a 1.8–2.0 stroke.

Colours are `AppColors` verbatim: `#1E1E1E` background, `#252526` surface,
`#4C9EEB` accent, `#A6A6A6` idle icons, `#57C777` / `#E05B5B` / `#5A5A5E` for
alive / dead / unknown.

## Not shown here

Deliberately out of scope for a static mock: real sockets, real mDNS or UDP
discovery (§12, a P3 bonus), the PC's actual firewall prompt, keep-screen-awake,
and every v2 item in `remote_apk_ui.md` §11 — gestures, picture-in-picture,
multiple phones fighting for control, casting, offline queue editing.

## Handoff

`remote.md` (repo root) carries the PC implementation — protocol §6, lifecycle
§11, storage keys, the `RemoteService` notifiers, the error table §17.8.
`remote_apk_ui.md` carries the APK — build order A1–A5 in §10.
`remote_opinion.md` is the plain-English reasoning behind both.
