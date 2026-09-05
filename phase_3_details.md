# Phase 3: The  -Style UI & OSC (On-Screen Controller)
**Status:** 🔄 In Progress — controller container + unified timeline implemented (top-anchored fused design, see bottom note)

## 🎯 Goal
Transform the raw video player into a premium, interactive experience. By the end of this phase, SALU will feature a beautiful, floating "glass" control bar at the bottom, smooth center-screen animations, and intelligent auto-hiding logic based on mouse movement.

## 🛠️ Step-by-Step Execution Plan

### Step 1: Global Mouse Tracker & Auto-Hide Logic (`lib/ui/managers/ui_visibility_manager.dart`)
*   Create a global state manager that wraps the entire video screen.
*   **Logic:** Listen for mouse movement (`MouseRegion` / `Listener`). When the mouse moves, set `isUIVisible = true`. 
*   Start a 3-second timer. If the mouse stops moving for 3 seconds, set `isUIVisible = false` to gracefully fade out **both the top title bar and the bottom OSC simultaneously** for a unified, clean view.

### Step 2: The Glass OSC Panel Foundation (`lib/ui/osc/osc_panel.dart`)
*   Build the main physical container (the On-Screen Controller bar) that will hold all the buttons, volume slider, and timeline.
*   **Styling:** 
    *   Apply `BackdropFilter` to blur the video behind it (In-App Glass Effect).
    *   Use the rich dark gray (`#1E1E1E`) with partial transparency and smooth, rounded corners.
*   **Layout Architecture (Configurable via Settings from Phase 4):** 
    *   **Top-Anchored (Default):** Attached directly beneath the top title bar, merging into a single clean glass UI block at the top of the screen that hides/shows together.
    *   **Floating Bottom:** Floats slightly above the bottom edge.
    *   **Fixed Bottom:** Attached flush to the bottom edge of the window.

### Step 3: Timeline & Scrub Bar (`lib/ui/osc/timeline_slider.dart`)
*   Create a custom slider to represent the video timeline.
*   Bind the slider to the `mpv` engine's current position and total duration.
*   **Click-to-Seek:** Ensure that clicking *anywhere* on the timeline instantly jumps the video to that exact point.
*   **Thumbnail Preparation:** Build the hover-listener UI structure so that when the mouse hovers over a specific point on the timeline, a small floating box appears (ready to hold the timestamp and video thumbnail preview).

### Step 4: Control Buttons (`lib/ui/osc/control_buttons.dart`)
*   Import a thin, modern, monochromatic icon pack (e.g., Cupertino or Lucide icons).
*   Add the essential buttons in a clean layout:
    *   **Playback:** Previous, Skip Backward, Play/Pause, Skip Forward, Next.
    *   **Audio (Quick Menu):** Mute toggle, and a Volume icon (with hover slider). Include an **Audio Track Icon**; clicking it opens a fast pop-up menu directly above the OSC to instantly switch between embedded audio tracks (Track 1, Track 2).
    *   **Subtitles (Quick Menu):** Add a dedicated **Subtitle Icon**. Clicking it opens a fast pop-up menu directly above the OSC to switch between embedded subtitle tracks, with a clear "Disable / Off" option at the top.
    *   **View Modes:** Picture-in-Picture (PiP) toggle, Fullscreen toggle.
    *   **Menus (Right Side):** 
        *   Info ('i' icon) toggle for Media Inspector (HUD).
        *   Right Panel Toggle (Quick Settings).
        *   Library / Stream Manager Toggle.
*   Connect these buttons directly to the `PlayerService`.

### Step 5: Center Play/Pause Animation (`lib/ui/widgets/center_play_pause.dart`)
*   Make the main video area clickable.
*   **Animation Logic:** When the user clicks the center of the video, toggle play/pause. Instantly show a large, thin Play or Pause icon in the dead center of the screen that smoothly expands (scales up) and fades out to 0% opacity within 500 milliseconds.

### Step 6: OSD (On-Screen Display) Indicators (`lib/ui/widgets/osd_indicator.dart`)
*   Create a minimalist overlay manager.
*   Whenever a user triggers an action (via keyboard or mouse), flash a small, clean text/icon indicator.
*   **Strict Position:** Top-Right corner (padded 20px down so it never overlaps with the Top-Anchored OSC or title bar).
*   **Covered Actions:** Play/Pause, Skip Forward/Backward, Next/Previous, and Volume/Mute changes.
*   Ensure this OSD text uses **Segoe UI Variable** and fades out automatically after 1 second without triggering the main OSC bar to appear.

### Step 7: Media Inspector (HUD) & Music Mode Setup (`lib/ui/widgets/media_hud.dart`)
*   **Media Inspector (HUD):** Build a small, semi-transparent overlay that displays real-time `mpv` engine stats (current video/audio codec, bitrate, dropped frames, hardware decoding status). **Trigger:** Toggled strictly via the dedicated "Info" ('i' icon) button placed on the right side of the OSC.
*   **Music Mode Transition:** Build the logic that detects if the loaded file has no video stream (e.g., MP3/FLAC). When triggered, the UI transitions into "Music Mode".
    *   The center of the screen will clearly display the **Album Art**.
    *   Alongside the Album Art, elegantly display the extracted **Metadata** (Track Title, Artist, Album Name, Year).
    *   The PiP (Picture-in-Picture) and Fullscreen toggle buttons on the OSC will be strictly disabled/grayed out.
*   *(Note: The actual scrolling Lyrics View will be fully implemented in Phase 7, but the physical Music Mode layout that houses it is established here).*
---

## ✅ Implemented so far (Arena session — fused top chrome + unified timeline)

> UI decision locked with the user: the controller container sits DIRECTLY under the auto-hide title bar and the two are drawn as ONE single window block — shared continuous gradient scrim, no border/outline between them, edge to edge, same show/hide animation. (Not a floating bottom OSC.)

### Files
- `lib/ui/screens/home_screen.dart` — fused chrome block (`_chromeBlockHeight = 148` = 40 title + 108 controller), slide/fade as one piece (300ms), `_scrimColors` gradient melts to transparent at the block's bottom edge; chrome content MouseRegion suspends auto-hide while interacting; `_AutoHideProgress` = thin 2px bottom hairline when chrome hides (**display only** — absorbs pointer events, no click/drag/hover/tooltip).
- `lib/ui/osc/controller_panel.dart` — `ControllerPanel` (height 108): MediaTimeline + play/pause, mute, volume bar. Paints nothing itself (parent scrim supplies the background).
- `lib/ui/osc/media_timeline.dart` — unified timeline, identical for video AND audio (user dropped thumbnail-frame preview by design).
- `lib/core/player_service.dart` — added `position`, `duration`, `volumeLevel`, `isMuted` ValueNotifiers + smooth position glide ticker; `seekTo` (clamps, no pause), `seekBy`, `toggleMute`, `setVolumeUI`; `keep-open=yes`.
- `lib/ui/widgets/custom_title_bar.dart` — gained `immersive` mode (no own gradient/animation; parent block drives both).
- `lib/theme/app_theme.dart` — `barTrack`, `barFill`, `barThumb`, `barTick`, `chipBackground`, `threadFill`.

### Timeline design (locked with user)
- Paste-window style thick bar: gentle translucent fill over dark track; flat 2px playhead notch, **no glow anywhere**.
- Time text INSIDE the bar, single color, `hh:mm:ss` always (zero-padded hours, tabular figures, no wiggle):
  left = playback position · center = `-` remaining (hidden when narrow) · right = total media time.
- Hover = faint auto-scaled tick ruler + small time chip below bar showing target time.
- Click = precise jump · press+drag = scrub preview, seek on release · mouse wheel over bar = ±1s per notch.
- Playback is never paused/disturbed by seeking (no frame-preview seeking exists anymore).

### Not yet from Phase 3 plan
Center play/pause animation (Step 5), OSD indicators (Step 6), media HUD + music mode (Step 7), more transport/track buttons (Step 4), configurable OSC position settings.

> **Update (transport pass, 2026-09-05):** the transport cluster, OSD deck,
> volume bar and resume memory described in
> `outline_transport_osd_resume.md` are implemented (steps A–F there).
> **Step 4's transport buttons** are done as SALU marks (not an icon pack):
> `> □ |<< >>| << >>` + sound group in Row 2 (see follow.md §5 for the
> locked layout). **Step 5 (center play/pause animation) is superseded and
> will NOT be built** — the OSD deck's `>`/`II` card is the one feedback,
> and the video's visual center stays untouched. **Step 6 (OSD
> indicators) is superseded by the OSD deck** (one top-center slot at
> 156 px; discrete transport actions flash it, bars never do; the Resume
> toast is its one interactive card). Track/PiP/fullscreen/panel buttons
> remain future work (the row's right edge is reserved for them).
