# Phase 4: Slide-Out Panels & Menus
**Status:** ✅ Completed

## 🎯 Goal
Build the "Quick Settings" architecture. By the end of this phase, SALU will have a sleek, blurred sidebar that elegantly slides in from the right side of the screen, housing the Video, Audio, and Subtitle controls without opening ugly separate windows.

## 🛠️ Step-by-Step Execution Plan

### Step 1: The Sliding Container Foundation (`lib/ui/panels/right_panel_container.dart`)
*   Create a reusable `Stack` layout that sits on top of the video screen.
*   **Animation Logic:** When toggled (via the OSC button from Phase 3), the panel smoothly slides in from the right edge (`SlideTransition`).
*   **Styling:** 
    *   Width: 300px to 350px.
    *   Background: Use `BackdropFilter` (blur effect) matching the OSC glass style (rich dark gray `#1E1E1E` with transparency).
    *   A clean, modern Tab Bar at the top to switch between **Playlist**, Video, Audio, and Subtitles.

### Step 2: Playlist Tab Implementation (`lib/ui/panels/tabs/playlist_tab.dart`)
*   Build the Playlist UI logic inside the Right Panel:
    *   **Current Queue List:** A scrolling list showing all currently queued videos/audio files. Highlight the currently playing file. Include an "Empty State" text if nothing is queued.
    *   **List Controls (Bottom Bar):** Add a minimal `+` (Plus) icon to open a file browser and manually add files to the list. Add a Trash Can icon to remove a selected item.
    *   **Chapter Markers:** A sub-section or toggle button within the Playlist tab that parses and displays the embedded chapters of the current movie, allowing the user to click and instantly jump to that point.
    *   **Loop/Shuffle Controls:** Minimalist icons to toggle "Loop Playlist", "Loop Single Track", and "Shuffle".

### Step 3: Video Tab Implementation (`lib/ui/panels/tabs/video_tab.dart`)
*   Build the UI controls and connect them to the `PlayerService`:
    *   **Rotation:** A row of buttons to rotate the video 90°, 180°, 270°.
    *   **Flip:** Toggle buttons for Horizontal Flip and Vertical Flip.
    *   **Aspect Ratio:** A dropdown/segmented control to force aspect ratios (e.g., Auto, 16:9, 4:3, 21:9).

### Step 4: Audio Tab Implementation (`lib/ui/panels/tabs/audio_tab.dart`)
*   Build the audio manipulation UI:
    *   **Volume Boost:** A dedicated slider allowing volume up to 200%.
    *   **Audio Delay/Sync:** A slider (-5.0s to +5.0s) to fix audio that is out of sync with the video.
    *   **10-Band Graphic Equalizer:** Build 10 vertical sliders for frequency control wired into `mpv`.
    *   **Dynamic EQ Presets:** A dropdown menu that changes based on the file type, sorted alphabetically:
        *   *Audio File Playing:* Acoustic, Bass and Treble, Bass Only, Classical, Dance, Electronic, Flat, Jazz, Pop, Rock, Soft, Techno, Treble Only.
        *   *Video File Playing:* Cinema, Documentary (Dialogue), Flat, Music Video (Bass Booster).

### Step 5: Subtitle Tab Implementation (`lib/ui/panels/tabs/subtitle_tab.dart`)
*   Build the subtitle formatting & management UI:
    *   **Subtitle Search & Load (Dedicated Modal):** A primary button that opens a beautiful, floating pop-up window (mimicking IINA). This window contains:
        *   A button to "Load Local Subtitle" from the computer.
        *   A live list of search results from OpenSubtitles (with language flags) that the user can click to instantly download and apply.
    *   **Position Slider:** A vertical slider to manually push the subtitle text higher up or lower down on the screen.
    *   **Subtitle Delay/Sync:** A slider (-5.0s to +5.0s) to fix subtitles that appear too early or too late.

### Step 5: Global App Preferences/Settings (UI Only) (`lib/ui/screens/settings_screen.dart`)
*   Create the main Settings window (accessed via a gear icon on the OSC or Right Panel).
*   Unlike the sliding panel, this will be a clean, centralized overlay (or a dedicated page state) mimicking the IINA preferences window.
*   **Categories to Draft:** 
    *   **General:** Theme/Accent Colors. Include a **"Clear Cache & Data"** section here to manually wipe the browser cache, delete temporary downloaded `.srt` files, and clear the video resume history.
    *   **User Interface:** A dropdown to change the **OSC Layout Architecture** (Top-Anchored, Floating Bottom, or Fixed Bottom).
    *   **Playback:** Default Behaviors (Seeking preferences).
    *   **Subtitles (API Setup):** A text input field where the user will paste their OpenSubtitles API Key to enable the auto-download feature.
    *   **Updates:** A dedicated button/section to manually trigger updates for `youtube-dl` / `yt-dlp` (which powers the network stream engine) and WebView2.
    *   **Key Bindings.** 
*   *Note: Only the UI layout is drafted here; the complex logic for these settings connects in Phase 7.*