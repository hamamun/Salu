# SALU Keyboard Shortcuts Reference & Implementation Manual

> **Document Status:** Comprehensive reference and specification of all standardized keyboard shortcuts implemented in SALU across **Player Mode**, **Mini Mode**, **Web Mode**, and **Popups/Dialogs**.  
> **Design Contract Note ([follow.md](follow.md) Rule 2):** In SALU, all shortcuts operate silently; shortcut labels are never printed on icons, menus, or tooltips.

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
