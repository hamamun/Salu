# Phase 5: Media Intelligence
**Status:** ⏳ Not Started

## 🎯 Goal
Make the player "smart." By the end of this phase, SALU will intuitively understand how to handle dragged files, remember where you stopped watching a movie, and automatically queue up TV show episodes in a folder without you having to click anything.

## 🛠️ Step-by-Step Execution Plan

### Step 1: Intelligent Drag-and-Drop (`lib/core/drag_drop_handler.dart`)
*   Implement `desktop_drop` or a similar Flutter package to handle files dropped onto the app window.
*   **Logic Rules (Mimicking  ):**
    *   **Drop a Video/Audio File on Main Screen:** Clear the current playlist and instantly play the new file.
    *   **Drop a Video/Audio File on Playlist Panel:** *Add* the file to the bottom of the current playlist without interrupting the playing video.
    *   **Drop a `.srt` or `.ass` File on Main Screen:** Instantly add it as a new Subtitle Track and enable it.
    *   **Drop a Folder:** Scan the folder for media files, clear the current playlist, load all media files into the playlist, and start playing the first one.

### Step 2: Folder Auto-Play & Smart Queuing (`lib/core/smart_queue_service.dart`)
*   **Logic (Mimicking  ):** When a user opens a file (e.g., `Episode_1.mp4`), automatically scan the directory for other media files.
*   **Natural Sorting:** Implement a natural sorting algorithm so it perfectly queues `Episode_2` through `Episode_10` in the correct human-readable order, exactly as   does, and silently adds them to the Right Panel Playlist Tab.

### Step 3: Seamless Resume Playback (`lib/core/history_manager.dart`)
*   Use `shared_preferences` to constantly save the playback timestamp of files.
*   **Logic (Mimicking  ):** 
    *   When the user opens a previously watched video, do NOT show a pop-up. Instantly auto-resume playback from the exact second they left off.
    *   Trigger the OSD (from Phase 3) to briefly flash a clean message in the top-right: *"Resumed from [Time]"*.
    *   Add a toggle in the Global Settings (Phase 4): `[x] Resume last playback position`, allowing users to turn this memory off completely.

> **Update (2026-09-05):** Step 3 is implemented — final design in
> `outline_transport_osd_resume.md` §5. `lib/core/resume_service.dart`
> (one JSON map, `5 s ≤ pos ≤ dur − 10 s` keep-rule, 1 000-entry cap,
> throttled disk writes + flush on pause/stop/switch/close), silent
> `Media(start:)` resume with no visible jump, the interactive **Resume
> toast** (`[>] 12:34 [↻ Restart]` — top-center OSD deck slot, not a
> corner message), and the Settings → General → **Resume** section
> (All files · Video only · Audio only · Off) replacing the checkbox.
> A second, in-session memory covers **Stop**: Stop parks the queue and
> Play resumes at the exact position through the same toast.

### Step 4: Hardware Decoding Settings (`lib/core/hwdec_manager.dart`)
*   **Logic (Mimicking  ):**   doesn't just silently fallback; it gives power users control. We will expose `hwdec` in the Global Settings.
    *   Options: `Auto` (Default - uses GPU), and `Disabled` (Forces CPU software decoding).
    *   Dart/`media_kit` supports passing this exact configuration directly to the `mpv` engine instance on startup.

### Step 5: Exact vs. Keyframe Seeking Config
*   **Logic (Mimicking  ):**   handles this via keyboard modifiers. 
    *   By default, Left/Right arrow keys will perform **Keyframe Seeking** (instantaneous jump, but maybe 1-2 frames off).
    *   Holding `Shift` + Left/Right arrow keys will perform **Exact Seeking** (takes a fraction of a second longer to calculate, but lands on the exact millisecond).
    *   Add a toggle in the settings to flip this default behavior if the user prefers.

### Step 6: Component Update Logic (`lib/core/updater_service.dart`)
*   Because SALU relies on external binaries to parse streams, these must be kept up to date so videos do not break when YouTube or websites change their code.
*   **Logic:**
    *   **yt-dlp Engine:** Create a backend function that connects to the `yt-dlp` GitHub releases page to download and replace the local binary with the newest version.
    *   **WebView2 Linkers:** Create a function to check for and download updates for the specific WebView2 `.dll` linker files (e.g., `WebView2Loader.dll`) that SALU uses to bridge to the Windows OS engine.
    *   Wire these functions to the "Check for Updates" button drafted in the Global Settings (Phase 4).