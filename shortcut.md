# SALU Keyboard Shortcuts Reference & Implementation Manual

> **Document Status:** Comprehensive reference and specification of all standardized keyboard shortcuts implemented in SALU across **Player Mode**, **Mini Mode**, **Web Mode**, and **Popups/Dialogs**. §4 carries the **finalized** design of the discoverability layer (owner-approved 2026-09-27, **implemented** — see §4.4): the Settings **Shortcuts tab** (the Living Map) and **Alt-Peek**.  
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
   All bare single-key shortcuts automatically stand down when focus sits inside an active text input field (`EditableText`). Keystrokes type letters into the field instead of triggering transport actions. Modifier combinations (`Ctrl`, `Alt`) remain active globally. Context-only keys are owned by their focused surface: while the playlist Group by pill is open, `1`–`4` select its four modes; they do not trigger Player seek jumps.

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
| `Shift + S` / `Alt + S` / `Ctrl + Shift + S` | **Toggle Shuffle** | **Assigned:** Toggles shuffle with OSD confirmation card. |
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
| `Ctrl + G` | **Open playlist Group by** | Opens the playlist panel and its Group by choices (Flat / Category / Country / Language). While the pill is open: `1` Flat, `2` Category, `3` Country, `4` Language (numpad aliases work; unavailable modes are ignored). These digits are context-only; normal Player seek keys and Web tab shortcuts are unchanged. |
| `Ctrl + D` | **Toggle channel favourites filter** | Opens the playlist and toggles its M3U favourites-only view. |
| `Ctrl + Shift + Delete` | **Clear playlist** | Clears the queue (local playlist or M3U list). |
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
| `Ctrl + ↑` / `Ctrl + ↓` / `Cmd + ↑` / `Cmd + ↓` | **Nudge Parameter** | Steps the value of the currently focused parameter line. |
| `Ctrl + Alt + ↑` / `↓` / `Cmd + Alt + ↑` / `↓` | **Change Focused Parameter** | Walks focus across the 4 Tune sections (Tone, EQ, Picture, etc.). |

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
| `Ctrl + F5` / `Ctrl + Shift + R` | **Hard Reload** | **Assigned:** Bypasses WebView2's HTTP cache for the reload. |
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
| `Ctrl + Shift + Delete` / `Ctrl + Shift + Backspace` | **Clear Browsing Data** | **Assigned:** Opens Clear Browsing Data dialog (Edge standard). |
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
| `Esc` | **Close Popup / Release Page Fullscreen** | Closes the top browser popup first; otherwise releases page fullscreen, then exits app fullscreen if active. |
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

#### 5. Playlist Group-by Choices (Player mode)
- `1` / `2` / `3` / `4` (numpad aliases work): Choose Flat / Category / Country / Language.
- `Esc`: Close the Group by choices.

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

> **FINALIZED (owner 2026-09-27) — the Living Map (§4.1) and Alt-Peek
> (§4.2 · Version C) both approved; built in the §4.3 order (status in
> §4.4).**
> **Interactive design mock:** `design/shortcut_preview.html` (self-contained,
> no dependencies — open in any browser; mock only, not app code; shows the
> superseded Version B — the §4.2 text is the truth).
>
> **Owner ruling on [follow.md](follow.md) Rule 2 (rules remain intact):** Rule 2
> governs SALU's **at-rest** chrome — menus, icons and tooltips stay silent, and
> that does not change. The two surfaces below are deliberate **reference
> surfaces** the viewer summons on purpose:
>
> * the **Shortcuts tab** is a page opened by an explicit click (a dictionary,
>   not a menu);
> * **Alt-Peek** is an on-demand reveal: while Alt is held, hovering a
>   control shows its key as a tooltip — it exists only while Alt is held
>   **and** the mouse is on the control, and vanishes on release or on
>   leaving the control.
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
  *subtitle selected*) · optional **anchor** — the always-visible control
  the Alt-Peek tooltip (§4.2) rides; keys without an anchor are the
  Living Map's rideless shelves.
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
> "did not like anyone." The Living Map below replaces it — and was
> approved in preview the same day. The Alt-Peek design (§4.2) is
> untouched.

A fifth tab in the Settings dialog (`SettingsTab.shortcuts`, rightmost —
after Updates; a reference page, not a setting). Pure reference: nothing on
it is configurable.

**The idea:** a keyboard is a grid of keys; SALU is a map of *places*. So
the tab shows **a miniature SALU that is alive** — the app itself, shrunken,
every always-visible control as a clean icon (no key text on it or under
it), every key without an always-visible control on a quiet glass shelf at
the left of the video, and the whole thing answering when it is pressed —
naming what is hovered in the detail strip below. The cheat sheet is not a
document about SALU; it is SALU.

**Layout (stacked in the real box):**

1. **The mode pill** — `Player · Mini · Web · Dialogs` (the four-option pill
   recipe). The miniature below becomes the chosen surface; the same key
   means different things per mode (§1.1) and the map never lies about which
   surface it is describing.
2. **The miniature** (~280 px) — the mock player: title bar, timeline,
   control row, video surface. Every always-visible control is its clean
   icon — **no key text printed on or under it** (the Version B chips are
   gone). Every unanchored key lives on a **quiet glass shelf at the left
   of the video — one shelf per group, icons only**
   (the action's own mark where SALU has one — open folder, URL, find, info,
   remote, settings, mode switch, sync arrows —
   and its keycap where the key is the whole action — `[ ] \`, `. ,`,
   `F3`, `Enter`, …). A group taller than five keys runs in two lines so
   a shelf always fits the box. `Ctrl+L` opens the miniature playlist panel,
   which shows compact **Local** and **M3U** header variants, keeping each
   playlist-only key on its own
   real control instead of orphaning it on a shelf. The title bar stays
   silent (no shortcuts live there).
3. **The detail strip** — below the miniature, **the only place key text
   appears on the tab**: left column keycap + group + action (+ guard);
   right column the same key in the other three modes (the §3 conflict
   matrix — the one part of the rejected concept worth keeping). Mousing
   over **any** icon — a chrome mark or a shelf icon — writes it here;
   the hovered mark lights while it is the one shown.

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
mock OSD deck flashes its card, `Ctrl+L` opens the mock playlist panel and
`Ctrl+G` / `Ctrl+D` open it through their Group by / favourites actions,
`F`/`F11` really hides the mock chrome (and brings the bottom hairline),
and the mode keys really flip the miniature: `Ctrl+M` drops it to the mini
bar, `Ctrl+U` raises the Open URL modal, `Alt+W` / `Ctrl+Shift+W` flip
Player ⇄ Web. `Esc` follows the app's own order — panel → fullscreen → (in
the app) close Settings — the rule taught by the mirror itself.
Unregistered keys do nothing.

**Fidelity rules:** the mock reuses the real recipes (glass capsule,
keycap, marks) so the map can never drift from the surface it describes;
every icon or keycap maps to a registry entry (§4.0) or it does not ship —
the shelves are *generated from* `rideless(scope)`, so a shortcut can
never be listed twice or missed; the mock never plays real media and
keeps no state — it is a mirror, not a player.

**Two build slices:** *(A)* the static map — mode pill + miniature +
rideless shelves + hover detail; *(B)* the liveness engine. A is the
reference; B is what makes it SALU.

### 4.2 Alt-Peek — hold Alt, hover, and the key shows as a tooltip (Version C)

**Version C (owner 2026-09-27; supersedes Version B's "all chips at once"):
a peek, never a ladder.** Hold Alt alone for **~200 ms** to **arm** the
peek. While armed, **hovering a control shows that control's key as a
tooltip in SALU's own tooltip look** — the app's `TooltipTheme` (same
surface, border and font as the name tooltips), the key in tabular figures,
**sized to the text: the key is never cut off**. Move the mouse and the
tooltip follows the hovered control; leave the control and it leaves.
While armed, the control's own name tooltip **stands down** (the pointer is
absorbed while armed, so the inner `Tooltip` never wakes) — the key tooltip
takes its place; release Alt and the normal tooltips are back. The peek only
watches; it never swallows a key (`Alt+Tab`, `Alt+F4` belong to Windows) and
never fires anything — the real shortcuts (§2) are unchanged.

**The tooltip recipe:** the app's `TooltipTheme` decoration + font, the
key legend in tabular figures, no clipping or ellipsis, fade in 120 ms /
fade out 100 ms — `IgnorePointer`, never focusable, never wakes the chrome.
It floats in a 200-px zone centred on the control: **above** the control by
default (the player's bottom row), **below** for the browser's top rows
(tab strip + address row — there is no room above), and hugging the
timeline's left end for the timeline.

**Anchors — Player mode (chrome visible):** the Version B table, now
tooltips:

| Visible control | Key tooltip |
|---|---|
| Open media mark (`+`) | `Ctrl+O` |
| Playlist control | `Ctrl+L` |
| Play / Pause mark | `Space` |
| Stop mark | `S` |
| Previous / Next marks | `PgUp` / `PgDn` |
| Seek back / forward marks | `←` / `→` |
| Speaker (sound group) | `↑ ↓ · M` (one tooltip, three keys) |
| Timeline, left end | `0–9 · Home · End` |
| Tune mark | `Ctrl+E · Cmd+E` |
| Repeat mark (local playlist header) | `R` |
| Shuffle mark (local playlist header) | `Shift+S · Alt+S · Ctrl+Shift+S` |
| Group by mark (M3U playlist) | `Ctrl+G` |
| Flat / Category / Country / Language pill options | `1` / `2` / `3` / `4` (while the pill is open) |
| Favourites filter (M3U playlist) | `Ctrl+D` |
| Playlist search field (local + M3U) | `Ctrl+F` |
| Clear playlist mark (local + M3U) | `Ctrl+Shift+Delete` |
| Close playlist mark (local + M3U) | `Ctrl+L` |
| Search clear × (when visible) | `Esc` |
| Fetch mark | `Ctrl+Shift+F` |
| Fullscreen mark | `F · F11` |

The title bar stays **silent** — Min/Max/Close have no shortcuts, and the
peek stays honest by staying silent there.

**Transient surfaces answer too, while they are on screen** — the peek
follows **visibility**, not a fixed map:

* the **Open pill's marks** (while the pill is up): film frame `Ctrl+O`,
  stacked frames `Ctrl+Shift+O`, link `Ctrl+U`;
* the **right-click menu's rows**: Shuffle
  `Shift+S · Alt+S · Ctrl+Shift+S`, Repeat `R`, Info `Ctrl+I`, Settings
  `F2`, Remote `Ctrl+Shift+R`.

Both hold the `ChromeLock` while open (they ARE the modal), so they are
the surfaces that answer the peek *through* the lock.

**Anchors — Web mode:** the browser row's visible marks (new tab `+` →
`Ctrl+T`, close `×` → `Ctrl+W`, address bar → `Ctrl+L`, history →
`Ctrl+H`, downloads → `Ctrl+J`, favourite → `Ctrl+D`, hub →
`Ctrl+Shift+O`, back / forward → `Alt+←` / `Alt+→`).

**Chrome hidden:** holding Alt does NOT wake the chrome — and with the
chrome away there is no control to hover, so nothing appears. (Version B's
hairline cluster is gone; the surface stays silent.)

**Timing & safety:**

* The peek arms only after Alt has been held **~200 ms alone** (no other
  key in between) — so `Alt+Tab` and `Alt+F4` never flash a peek.
* Hide on: Alt release · mouse leaving the control · focus loss / window
  blur (Windows may never deliver the Alt-up after an `Alt+Tab` — the peek
  must never freeze on screen) · a modal holding the `ChromeLock`, except
  the modal/panel's own controls (the right-click menu rows and playlist
  header/pill opt in so their keys remain discoverable on their own surface).
* Mode switch while Alt is held (`Alt+W`): the action fires, and the
  tooltip follows the new surface.
* **Mini mode: out of scope v1** — the 32-px strip has no room and few
  keys; the Shortcuts tab's Mini miniature covers it.

**Unclippable recipe (fix pass 2026-09-27):** the key tooltip renders in
the **root Overlay** (`OverlayPortal` with `OverlayChildLocation.rootOverlay` — the same move
the Open pill itself makes), so no ancestor can clip it: not the pill's
glass capsule, not the right menu's, not the web rows. It is placed by a
layout delegate against the control's on-screen box: centred **6 px off
the control's edge** (it can never sit INSIDE the mark again), hugging
the timeline's left end for the timeline, clamped to the window —
flipping to the other side at an edge, so the key is never cut, not even
at the screen border.

**Everything with a key answers (owner ruling 2026-09-27 — "all
buttons"): while §4.2's anchors stand, these also answer the peek with
their exact registry entries (the pill-marks `entries` recipe):**

* the **title bar's doors** — the Mini-bar glyph (`Ctrl+M`), the
  Settings dots (`F2 · Ctrl+,` — `web.settings` while Web owns the
  window) and the **Player · Web switch** (`Alt+W · Ctrl+Shift+W`).
  Min / Max / Close have no keys and stay honestly silent;
* the **Web ⋮ menu's rows** while the menu is open — New tab `Ctrl+T`,
  Find `Ctrl+F`, History `Ctrl+H`, Downloads `Ctrl+J`, Clear browsing
  data `Ctrl+Shift+Delete`, Settings `F2`, and the zoom cluster
  (`Ctrl+-` · `Ctrl+0` · `Ctrl+=`). Rows with no key (Open in Edge,
  Desktop mode) stay silent;
* the **find bar's buttons** while it is open — Previous `Shift+F3`,
  Next `F3`, Close `Esc`;
* the **volume bar** beside the speaker (the sound group's `↑ ↓ · M`)
  and the **Web-mode title strip's download badge** (`Ctrl+J`).

The Living Map is untouched by this ruling: none of these ride a
registry anchor, so they stay on the map's rideless shelves where §4.1
keeps them.

### 4.3 Build order

1. **The registry** (§4.0) — the foundation both surfaces read.
2. **Shortcuts tab, slice A** (the static Living Map: mode pill + miniature
   + rideless shelves + hover detail).
3. **Alt-Peek** (Player chrome first, then Web row, then the right-click
   menu's rows).
4. **Shortcuts tab, slice B** (the liveness engine).

### 4.4 Implementation status (2026-09-27)

| Step | Where | Status |
|---|---|---|
| 1 · Registry | `lib/core/shortcuts/shortcut_registry.dart` (+ `test/shortcut_registry_test.dart`) | Done — every §2 key, scope · combos · action id · group · guard · anchor · legend (compact legends for the shelf keycaps: `Ctrl+Tab`, `Ctrl+Shift+Tab`, `↑ ↓`, `↓ ↑`). Display truth; handlers unchanged. |
| 2 · Shortcuts tab, slice A | `lib/ui/widgets/shortcuts_tab.dart`, `SettingsTab.shortcuts` | Done (Version C) — mode pill, miniature per mode (Player · Mini · Web · Dialogs), **clean icons on every always-visible control (no key text on or under them)**, the **rideless glass shelves at the left of the video — generated from `rideless(scope)`, one shelf per group, icons only** (the action's own mark or its keycap; two lines past five keys), hover/tap detail strip with the cross-mode column. Tab strip scrolls horizontally when narrow. |
| 3 · Alt-Peek | `lib/ui/widgets/alt_peek.dart` | Done (Version C) — hold-Alt **arming** (200 ms alone) + hover → the key as a **tooltip in the app's `TooltipTheme`** (never cut off), the name tooltip stands down while armed. Player chrome, the Web row (tab strip + address row), the **Open pill's marks** and the **right-click menu's rows** (`entries` + `ignoreLock` — those surfaces are their own modals). Chrome hidden: silent (no cluster). Mini: out of scope v1 (as specified). |
| 4 · Shortcuts tab, slice B | `ShortcutsTabState` liveness engine (+ `test/shortcuts_tab_test.dart`) | Done — registered keys drive the mock (timeline, volume, play mark, OSD card, playlist, fullscreen + hairline, mini / web / URL modal flips, web tabs, panels, find, zoom); `Esc` walks panel → fullscreen → closes Settings. |
| 5 · Fix pass | `lib/ui/widgets/alt_peek.dart` (+ the wrapped surfaces) | Done (2026-09-27) — the key tooltip moved into the **root Overlay** (`OverlayPortal` on the root Overlay + a `SingleChildLayoutDelegate` against the control's on-screen box): the **"got inside the peel and cut"** bug is gone — the tip sits **6 px outside** the mark, floats above the pill/menu glass and the web rows, and **clamps/flips at the window edges** so no legend is ever clipped (§4.2 · Unclippable recipe). Coverage per the owner's "all buttons" ruling: title bar's Mini / Settings / Player·Web switch, the **Web ⋮ menu's rows + zoom cluster**, the volume bar, and the Web title strip's download badge now answer the peek (`entries` recipe — registry unchanged, Living Map untouched). |

