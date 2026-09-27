# SALU Keyboard Shortcuts Reference & Implementation Manual

> **Document Status:** Comprehensive reference and specification of all standardized keyboard shortcuts implemented in SALU across **Player Mode**, **Mini Mode**, **Web Mode**, and **Popups/Dialogs**. §4 adds the spec (not yet implemented) for the discoverability layer: the Settings **Shortcuts tab** and **Alt-Peek**.  
> **Design Contract Note ([follow.md](follow.md) Rule 2):** In SALU, all shortcuts operate silently; shortcut labels are never printed on icons, menus, or tooltips. (The two §4 reference surfaces are an owner ruling, recorded in §4 — Rule 2 itself is untouched.)

---

## 1. Architectural Principles & Mode Separation

1. **Clean Mode Separation:**  
   Player Mode and Web Mode are distinct application modes. When an industry-standard shortcut shares the same key combination across both domains (e.g. `Ctrl + F` for Find or `Ctrl + L` for List/Location), each mode executes its domain-appropriate standard action without interference or collision:
   * **In Player Mode:** `Ctrl + F` focuses Find / Search in the playlist; `Ctrl + L` opens the Playlist panel.
   * **In Web Mode:** `Ctrl + F` opens Find in Page; `Ctrl + L` focuses the Address Bar.
2. **Universal Standards Alignment:**  
   * **Player Mode:** Aligned with industry-standard desktop media players (mpv, VLC, MPC-HC, YouTube).
   * **Web Mode:** Aligned with Microsoft Edge on Windows (and Chromium standard browser conventions).
3. **Typing Guard Safety (`_isTyping`):**  
   All bare single-key shortcuts automatically stand down when focus sits inside an active text input field (`EditableText`). Keystrokes type letters into the field instead of triggering transport actions. Modifier combinations (`Ctrl`, `Alt`) remain active globally.

---

## 2. Standardized Shortcut Inventory (By Group)

### Group A: Player Mode (Full Window)

#### 1. Playback & Transport Controls
*Transport keys drive the OSD deck — they never wake the top chrome. Single-key shortcuts automatically stand down when typing.*

| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Space` | **Play / Pause** | Toggles playback (standard across all players). |
| `←` (Left Arrow) | **Seek Backward** | Seeks backward 5s (hold ramps to 10s, 15s...). |
| `→` (Right Arrow) | **Seek Forward** | Seeks forward 5s (hold ramps to 10s, 15s...). |
| `↑` (Up Arrow) | **Volume Up** | Increases volume by 5%. |
| `↓` (Down Arrow) | **Volume Down** | Decreases volume by 5%. |
| `M` (Bare key) | **Mute / Unmute** | **Standardized:** Universal media player standard (mpv, VLC, MPC-HC, YouTube). |
| `Ctrl + M` | **Toggle Mini Mode** | **Standardized:** Moves Mini player toggle to `Ctrl+M` so bare `M` is safely reserved for Mute. |
| `S` | **Stop** | Stops playback and parks queue (MPC-HC standard). |
| `Shift + S` / `Alt + S` | **Toggle Shuffle** | **Assigned:** Toggles shuffle with OSD confirmation card. |
| `R` (Bare key) | **Cycle Repeat Mode** | **Assigned:** Cycles Repeat (Off → All → One → Off) with OSD card. |
| `Page Up` | **Previous Item** | Previous playlist item / channel (MPC-HC standard). |
| `Page Down` | **Next Item** | Next playlist item / channel (MPC-HC standard). |

#### 2. Playback Speed & Frame Control
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `[` | **Speed Slower (-0.1x)** | **Assigned:** Decreases playback speed by 0.1x with OSD card (mpv standard). |
| `]` | **Speed Faster (+0.1x)** | **Assigned:** Increases playback speed by 0.1x with OSD card (mpv standard). |
| `\` or `Backspace` | **Reset Speed (1.0x)** | **Assigned:** Resets playback rate to normal 1.0x (mpv standard). |
| `.` (Period) | **Frame Step Forward** | **Assigned:** Steps one frame forward (mpv / VLC standard). |
| `,` (Comma) | **Frame Step Backward** | **Assigned:** Steps one frame backward (mpv / VLC standard). |

#### 3. Seeking & Position Jumps
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `0` through `9` | **Jump to 0% – 90%** | **Assigned:** Jumps to 0%..90% of file duration (mpv / YouTube standard). |
| `Home` | **Jump to Beginning** | **Assigned:** Seeks directly to `0:00`. |
| `End` | **Jump to End** | **Assigned:** Jumps to next item / end of stream. |

#### 4. Fullscreen & Window Controls
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `F` (Bare key) | **Toggle Fullscreen** | **Assigned:** Universal media player standard (mpv, VLC, YouTube). |
| `F11` | **Toggle Fullscreen** | **Assigned:** Windows application standard (MPC-HC, Edge, Chrome). |
| `Esc` | **Close Popup / Exit Fullscreen** | **Standardized:** Closes open popup/dialog in hierarchy order; if no popups are open and window is in Fullscreen, **exits Fullscreen**! |

#### 5. Subtitle Synchronization & Tracks
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Z` | **Subtitle Sync Earlier** | Shifts subtitles by -100 ms (-0.1 s). mpv standard. |
| `X` | **Subtitle Sync Later** | Shifts subtitles by +100 ms (+0.1 s). mpv standard. |
| `Shift + Z` | **Coarse Sync Earlier** | Shifts subtitles by -1000 ms (-1.0 s). |
| `Shift + X` | **Coarse Sync Later** | Shifts subtitles by +1000 ms (+1.0 s). |
| `Shift + Backspace` / `Ctrl + Shift + Z` | **Reset Subtitle Sync** | **Assigned:** Resets subtitle delay back to `0.0s` with OSD card. |
| `C` or `T` (Bare key) | **Toggle Tracks / Lyrics** | **Assigned:** Video toggles Track panel (`T` / `C` for Captions); Audio toggles Lyrics. |
| `B` (Bare key) | **Cycle Audio Track** | **Assigned:** Cycles through available audio languages with OSD card (mpv / VLC standard). |
| `V` (Bare key) | **Cycle Subtitle Track** | **Assigned:** Cycles subtitles (Off → Sub 1 → Sub 2 → Off) with OSD card (VLC standard). |

#### 6. Media Opening, Searching & Surface Toggles
*Activity keys — pressing any of these automatically wakes the top title bar and controller chrome.*

| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Ctrl + O` | **Open File(s)** | Opens native Windows file picker (supports multi-select). |
| `Ctrl + Shift + O` | **Open Folder** | **Standardized:** Universal media player standard (VLC) for opening a directory. |
| `Ctrl + U` | **Open URL Modal** | Opens the centered glass URL input modal. |
| `Ctrl + L` | **Toggle Playlist** | Slides out the Playlist and channel manager panel (VLC standard). |
| `Ctrl + F` | **Find in Playlist** | **Standardized:** Focuses search input field in Playlist panel. |
| `Ctrl + Shift + F` | **Search Subtitles** | **Assigned:** Opens the online subtitle search dialog directly. |
| `Ctrl + I` | **Toggle Info Panel** | **Assigned:** Opens/closes media technical info panel. |
| `Ctrl + E` / `Cmd + E` | **Toggle Tune Panel** | Opens/closes Equalizer, Tone, and Picture adjustments. |
| `Ctrl + Shift + R` | **Remote QR Pairing** | **Assigned:** Opens the Remote control QR pairing dialog. |
| `F2` / `Ctrl + ,` | **Open Settings** | **Assigned:** Universal standard for Settings / Preferences. |
| `Ctrl + Shift + W` / `Alt + W` | **Switch to Web Mode** | **Assigned:** Seamless toggle between Player and Web mode. |

#### 7. Tune / Equalizer Keyboard Tier
| Shortcut | Action | Description / Notes |
|---|---|---|
| `Ctrl + ↑` / `Ctrl + ↓` | **Nudge Parameter** | Steps the value of the currently focused parameter line. |
| `Ctrl + Alt + ↑` / `↓` | **Change Focused Parameter** | Walks focus across the 4 Tune sections (Tone, EQ, Picture, etc.). |

---

### Group B: Mini Mode (32-px Strip)

*Mini mode runs an ultra-compact keyboard set. Panels and dialogs are out of work.*

| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Esc` | **Exit Mini Mode** | Restores the full window. |
| `Ctrl + M` | **Exit Mini Mode** | **Standardized:** Matches full mode's Mini toggle. |
| `M` (Bare key) | **Mute / Unmute** | **Standardized:** Mute is now consistent across full player and mini mode. |
| `Space` | **Play / Pause** | Transport control. |
| `←` / `→` | **Seek Backward / Forward** | 5s step ramp seeks. |
| `↑` / `↓` | **Volume Up / Down** | ±5% steps. |
| `S` | **Stop** | Stops playback and parks queue. |
| `Page Up` / `Page Down` | **Previous / Next Item** | Queue stepping. |
| `Z` / `X` | **Subtitle Sync ±100ms** | Title swap shows offset. |
| `Shift + Z` / `Shift + X` | **Subtitle Sync ±1000ms** | Coarse adjustment. |

---

### Group C: Web Mode (Microsoft Edge / Chromium Standard)

*Active while SALU is switched to Web Browser mode. Keys respond while Flutter holds focus.*

#### 1. Tab Management
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Ctrl + T` | **New Tab** | Opens a fresh tab and focuses address bar (max 8 tabs). |
| `Ctrl + W` | **Close Tab** | Closes the currently active browser tab. |
| `Ctrl + Tab` / `Ctrl + PgDn` | **Next Tab** | **Assigned:** Switches to the next tab (Edge standard). |
| `Ctrl + Shift + Tab` / `Ctrl + PgUp` | **Previous Tab** | **Assigned:** Switches to previous tab (Edge standard). |
| `Ctrl + 1` through `Ctrl + 8` | **Jump to Tab 1–8** | **Assigned:** Switches directly to tab index 1–8 (Edge standard). |
| `Ctrl + 9` | **Jump to Last Tab** | **Assigned:** Switches directly to the rightmost tab (Edge standard). |
| `Ctrl + Shift + T` | **Reopen Closed Tab** | **Assigned:** Restores the most recently closed tab URL (Edge standard). |

#### 2. Navigation & Address Bar
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Ctrl + L` / `Alt + D` / `F6` | **Focus Address Bar** | **Standardized:** Selects address bar text (Edge standard). |
| `Ctrl + R` / `F5` | **Reload Page** | **Standardized:** Refreshes current page (Edge standard). |
| `Ctrl + F5` / `Ctrl + Shift + R` | **Hard Reload** | **Assigned:** Re-fetches page fresh from network. |
| `Alt + ←` (Left Arrow) | **Back** | **Assigned:** Navigates back in tab history (Edge standard). |
| `Alt + →` (Right Arrow) | **Forward** | **Assigned:** Navigates forward in tab history (Edge standard). |
| `Alt + Home` | **Home** | **Assigned:** Navigates website to its root / home page. |

#### 3. Panels & Browser Shelves
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Ctrl + H` | **History Panel** | **Assigned:** Opens slide-down History panel (Edge standard). |
| `Ctrl + J` | **Downloads Shelf** | **Assigned:** Opens Downloads panel / shelf (Edge standard). |
| `Ctrl + D` | **Add / Edit Favourite** | **Assigned:** Opens Favourite sheet for current page (Edge standard). |
| `Ctrl + Shift + O` | **Favourites Hub** | **Assigned:** Opens full Favourites manager hub (Edge standard). |
| `Ctrl + Shift + Delete` | **Clear Browsing Data** | **Assigned:** Opens Clear Browsing Data dialog (Edge standard). |
| `F2` / `Ctrl + ,` | **Browser Settings** | **Assigned:** Opens SALU settings directly on the **Web** tab. |

#### 4. Page Search (Find Bar)
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Ctrl + F` | **Find in Page** | Opens the custom in-page search bar. |
| `F3` | **Find Next Match** | **Assigned:** Advances to next match (Edge standard). |
| `Shift + F3` | **Find Previous Match** | **Assigned:** Steps back to previous match (Edge standard). |

#### 5. Zoom & Window
| Shortcut | Action | Standard / Behavior |
|---|---|---|
| `Ctrl + =` / `Ctrl + Num +` | **Zoom In** | Steps page zoom up. |
| `Ctrl + -` / `Ctrl + Num -` | **Zoom Out** | Steps page zoom down. |
| `Ctrl + 0` / `Ctrl + Num 0` | **Reset Zoom** | Resets zoom to 100%. |
| `F11` | **Browser Fullscreen** | **Assigned:** Toggles fullscreen window (Edge standard). |
| `Esc` (Page Fullscreen) | **Release Page Fullscreen** | Releases web page fullscreen mode back to browser chrome. |
| `Ctrl + Shift + W` / `Alt + W` | **Switch to Player Mode** | **Assigned:** Seamless toggle between Web and Player mode. |

---

### Group D: Sub-Dialogs & Focused Components

#### 1. Open URL Modal (`Ctrl + U`)
- `Enter`: Play URL.
- `Ctrl + Enter`: Play & Save to saved URLs list.
- `↑` / `↓`: Walk saved URLs list.
- `Esc`: Close modal.

#### 2. Address Bar Dropdown (Web Mode)
- `↓` / `↑`: Walk suggestions list.
- `Enter` / `Num Enter`: Submit address or pick selected suggestion.
- `Esc`: Hide suggestions without navigating.

#### 3. Find-in-Page Bar (`Ctrl + F`)
- `Enter` / `Num Enter`: Next match.
- `Shift + Enter`: Previous match.
- `Esc`: Close find bar.

#### 4. Playlist Panel Search Field
- `Esc` (1st press): Clear search query.
- `Esc` (2nd press): Unfocus search field.
- `Esc` (group-by pill open): Close group-by pill.

---

## 3. Standardization & Conflict Resolution Matrix

| Key / Action | Previous State | Standardized Behavior | Cross-Mode Separation Rule |
|---|---|---|---|
| **`M`** | Toggled Mini player; mute required `Ctrl+M`. | **Bare `M` is MUTE** in both Full Player and Mini mode. | Standard across all media players. |
| **`Ctrl + M`** | Muted audio. | **`Ctrl + M` toggles Mini Mode**. | Standard modifier toggle for compact views. |
| **`Ctrl + F`** | Opened Windows Folder picker in Player; Find in Web. | **Player Mode:** Focuses Search in Playlist.<br>**Web Mode:** Opens Find in page. | **Same standard key used in separate modes** for each mode's search function. |
| **`Ctrl + Shift + O`** | None. | **Player Mode:** Opens Folder (VLC standard). | Resolves folder opening cleanly without hijacking `Ctrl+F`. |
| **`Ctrl + L`** | Playlist in Player; Address bar in Web. | **Player Mode:** Toggles Playlist (VLC standard).<br>**Web Mode:** Focuses Address bar (Edge standard). | **Same standard key used in separate modes** for each mode's list/location bar. |
| **`F` / `F11`** | No shortcut existed for fullscreen. | **`F`** and **`F11`** toggle Fullscreen in Player mode; **`F11`** in Web mode. | Universal media player (`F`) & Windows app (`F11`) standards. |
| **`Esc`** | Woke chrome in Player mode; only exited fullscreen in Web mode. | In Player mode, `Esc` dismisses open popups first, and **exits Fullscreen** if no popups are open. | Aligns player and browser behavior. |
| **`Ctrl + Shift + W`** | None. | Seamlessly toggles between **Player Mode** and **Web Mode**. | Global mode switch accessible from anywhere. |
| **`[` / `]` / `\`** | None. | Adjusts playback speed slower/faster and resets to 1.0x. | Standard mpv speed controls. |
| **`.` / `,`** | None. | Steps frame forward / backward. | Standard mpv / VLC frame-stepping controls. |
| **`0` .. `9`** | None. | Jumps to 0% .. 90% of duration. | Standard mpv / YouTube position jumps. |
| **`B` / `V`** | None. | Cycles audio tracks (`B`) and subtitle tracks (`V`). | Standard mpv / VLC track cycling with live OSD feedback. |
| **`Shift + S` / `R`** | Mouse-only in Right-Click menu. | `Shift+S` toggles Shuffle; `R` cycles Repeat. | Standard media playback toggles with live OSD feedback. |
| **Web Tabs** | No tab switching shortcuts. | Added `Ctrl+Tab`, `Ctrl+Shift+Tab`, `Ctrl+1..8`, `Ctrl+9`, `Ctrl+Shift+T`. | Complete Microsoft Edge standard tab control. |
| **Web Panels** | Mouse-only menus. | Added `Ctrl+H` (History), `Ctrl+J` (Downloads), `Ctrl+D` (Favourite), `Ctrl+Shift+O` (Hub), `Ctrl+Shift+Delete` (Clear data). | Complete Microsoft Edge standard shelf doors. |

---

## 4. Discoverability Layer — the Shortcuts Tab & Alt-Peek

> **Spec stage (owner 2026-09-27) — designed, not yet implemented.**
> **Interactive design mock:** `design/shortcut_preview.html` (self-contained,
> no dependencies — open in any browser; mock only, not app code).
>
> **Owner ruling on [follow.md](follow.md) Rule 2 (rules remain intact):** Rule 2
> governs SALU's **at-rest** chrome — menus, icons and tooltips stay silent, and
> that does not change. The two surfaces below are deliberate **reference
> surfaces** the viewer summons on purpose:
>
> * the **Shortcuts tab** is a page opened by an explicit click (a dictionary,
>   not a menu);
> * **Alt-Peek** is an on-demand reveal that exists only while Alt is held and
>   vanishes on release.
>
> Neither is a tooltip, neither prints anything at rest. Recorded here so no
> future session mistakes either surface for permission to print shortcut
> labels on menus, icons or tooltips.

### 4.0 The Shortcut Registry — one list, both surfaces read it

Before either surface is built, all shortcuts in §2 move into **one registry**
(a single data list). The Settings tab and Alt-Peek both *render* from it;
neither keeps its own copy. If a shortcut ships without a registry entry, that
is a bug.

* **Entry shape:** mode scope (`player` / `mini` / `web` / `dialog`) · key
  combination (logical key + Ctrl/Shift/Alt flags) · action id · group (the §2
  groups) · availability guard, where one applies (e.g. *seekable*,
  *subtitle selected*) · optional **anchor** — the visible control Alt-Peek
  chips (§4.2).
* **Consumers:** the Shortcuts tab (§4.1), Alt-Peek (§4.2). The existing key
  handlers keep working as they are; a later phase may have them consult the
  registry too, so drift becomes impossible. Until then the registry is the
  **display truth** and must be updated in the same commit as any handler
  change.
* **No custom key mapping — ever.** SALU's shortcuts are *standards*
  (§1.2: mpv / VLC / MPC-HC / Edge alignment); the standard IS the feature.
  The registry is a mirror, never an editor. The Shortcuts tab therefore has
  no "rebind" affordance anywhere.

### 4.1 Settings → Shortcuts tab — the Living Map

> **Revision (owner 2026-09-27):** the drawn-keyboard concept (board + mode
> pill + modifier latch, later + capture pill) was rejected in preview —
> "did not like anyone." The Living Map below replaces it. The Alt-Peek
> design (§4.2) is untouched.

A fifth tab in the Settings dialog (`SettingsTab.shortcuts`, rightmost —
after Updates; a reference page, not a setting). Pure reference: nothing on
it is configurable.

**The idea:** a keyboard is a grid of keys; SALU is a map of *places*. So
the tab shows **a miniature SALU that is alive** — the app itself, shrunken,
every visible control wearing its keys, and answering when they are pressed.
The cheat sheet is not a document about SALU; it is SALU.

**Layout (stacked in the real box):**

1. **The mode pill** — `Player · Mini · Web · Dialogs` (the four-option pill
   recipe). The miniature below becomes the chosen surface; the same key
   means different things per mode (§1.1) and the map never lies about which
   surface it is describing.
2. **The miniature** (~280 px) — the mock player: title bar, timeline,
   control row, video surface — with the Alt-Peek chip recipe pinned to
   every visible control, always visible here (this is the reference map;
   the peek is the same chips' on-surface, hold-Alt version). The title bar
   stays silent (no shortcuts live there). Keys with no control to ride
   (`Z/X`, `B/V`, `[ ]`, `R`, `Shift+S`, `. ,`) sit in one quiet cluster
   pinned to the video surface.
3. **The detail strip** — below the miniature: left column keycap + group +
   action (+ guard); right column the same key in the other three modes
   (the §3 conflict matrix — the one part of the rejected concept worth
   keeping).

**Accommodation (the real numbers):** the dialog is `min(640 × 540, window −
insets)`; header + tab strip + divider leave ≈ 640 × 450. Top row (30) +
miniature (280) + detail strip (~80) + note ≈ 430 — no scroll at full size;
narrower windows scale the miniature as one piece (the `FittedBox` recipe)
and the box never grows. The fifth tab label makes the tab strip overflow on
very narrow dialogs — below that width the strip slides horizontally (a few
lines, part of this work).

**It answers — the liveness engine:** while the tab is open it swallows the
keyboard, and every registered key fires its real mock feedback: transport
keys move the mock timeline and volume, `Space` swaps the play mark, the
mock OSD deck flashes its card, `Ctrl+L` slides the mock playlist panel,
`F`/`F11` really hides the mock chrome (and brings the bottom hairline
cluster), and the mode keys really flip the miniature: `Ctrl+M` drops it to
the mini bar, `Ctrl+U` raises the Open URL modal, `Alt+W` / `Ctrl+Shift+W`
flip Player ⇄ Web. `Esc` follows the app's own order — panel → fullscreen →
(in the app) close Settings — the rule taught by the mirror itself.
Unregistered keys do nothing.

**Fidelity rules:** the mock reuses the real recipes (glass capsule, chip,
marks) so the map can never drift from the surface it describes; every chip
maps to a registry entry (§4.0) or it does not ship; the mock never plays
real media and keeps no state — it is a mirror, not a player.

**Two build slices:** *(A)* the static map — mode pill + miniature + chips +
hover detail; *(B)* the liveness engine. A is the reference; B is what makes
it SALU.

### 4.2 Alt-Peek — hold Alt, see the keys (Excel-style, passive)

**Version B (owner 2026-09-27): a peek, never a ladder.** Holding Alt reveals
small key chips next to the controls **currently visible** — exactly what
Excel does with its ribbon. Pressing a chip's letter does NOT fire anything
from the peek; the real shortcuts (§2) are unchanged. The peek only watches;
it never swallows a key (`Alt+Tab`, `Alt+F4` belong to Windows).

**The chip recipe:** one small glass capsule (the OSD deck's `GlassCapsule`
material, radius 6, height 20), the key legend in tabular figures, hairline
outline — `IgnorePointer`, never focusable, never wakes the chrome. A chip
shows the **key only**; the control it rides is its own label — the mark is
the *what*, the chip is the *how*.

**Anchors — Player mode (chrome visible):**

| Visible control | Chip |
|---|---|
| Open media mark (`+`) | `Ctrl+O` |
| Playlist control | `Ctrl+L` |
| Play / Pause mark | `Space` |
| Stop mark | `S` |
| Previous / Next marks | `PgUp` / `PgDn` |
| Seek back / forward marks | `←` / `→` |
| Speaker (sound group) | `↑ ↓ · M` (one chip, three keys) |
| Timeline, left end | `0–9 · Home · End` |
| Tune mark | `Ctrl+E` |
| Fetch mark | `Ctrl+Shift+F` |
| Fullscreen mark | `F · F11` |

The title bar gets **no chips** — Min/Max/Close have no shortcuts, and the
peek stays honest by staying silent there. The right-click menu, the Open
menu's rows and open dialogs chip their Group D keys the same way while they
are on screen — the peek follows **visibility**, not a fixed map.

**Anchors — Web mode:** the browser row's visible marks chip their Group C
keys (new tab `+` → `Ctrl+T`, close `×` → `Ctrl+W`, address bar → `Ctrl+L`,
history → `Ctrl+H`, downloads → `Ctrl+J`, favourite → `Ctrl+D`, hub →
`Ctrl+Shift+O`, back / forward → `Alt+←` / `Alt+→`).

**Chrome hidden:** holding Alt does NOT wake the chrome. Instead one quiet
cluster floats just above the bottom hairline with the surface keys —
`Space · F · ← → · ↑ ↓ · M · 0–9` — and leaves when Alt does.

**Timing & safety:**

* Chips appear only after Alt has been held **~200 ms alone** (no other key in
  between) — so `Alt+Tab` and `Alt+F4` never flash a peek. Fade in 120 ms,
  fade out 100 ms.
* Hide on: Alt release · focus loss / window blur (Windows may never deliver
  the Alt-up after an `Alt+Tab` — the peek must never freeze on screen).
* Mode switch while Alt is held (`Alt+W`): the action fires, and the chips
  re-render for the new surface.
* **Mini mode: out of scope v1** — the 32-px strip has no room and few keys;
  the Shortcuts tab's Mini board covers it.

### 4.3 Build order

1. **The registry** (§4.0) — the foundation both surfaces read.
2. **Shortcuts tab, slice A** (the static Living Map: mode pill + miniature
   + chips + hover detail).
3. **Alt-Peek** (Player chrome first, then Web row, menus, dialogs).
4. **Shortcuts tab, slice B** (the liveness engine).
