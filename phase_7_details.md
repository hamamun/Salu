# Phase 7: Advanced Player Tools & Search Logic
**Status:** ✅ Completed — lyrics engine (`core/lyrics_parser.dart` + `ui/widgets/lyrics_view.dart` injected into Music Mode), OpenSubtitles v1 API (`core/subtitles_api.dart` with the classic size+128KB 64-bit hash), the reworked `ui/modals/subtitle_search_modal.dart` (Top-3 hash matches + all results + flag chips + one-click download next to the video), and the silent auto-download hook in `PlayerService._maybeAutoDownloadSubtitles` wired to the Settings toggle.

## 🎯 Goal
Implement the heavy logic for the features that required standalone architecture. By the end of this phase, SALU will feature a dynamic scrolling Lyrics engine synced to audio files, and a fully functional OpenSubtitles API integration for instant subtitle downloading.

## 🛠️ Step-by-Step Execution Plan

### Step 1: The Lyrics Engine (`lib/core/lyrics_parser.dart`)
*   Create a parser to read standard `.lrc` text files (which contain timestamps and lyrics: e.g., `[01:12.40] Hello world`).
*   **Smart Matching:** If `song.mp3` is playing, silently check the same folder for `song.lrc` and load it.

### Step 2: The Scrolling Lyrics View (`lib/ui/widgets/lyrics_view.dart`)
*   Inject the lyrics UI into the **Music Mode** layout (built in Phase 3).
*   **Animation Logic:**
    *   Display the lyrics as a vertical list in the center/right of the screen (next to the Album Art).
    *   Use a `ScrollController` linked to the `mpv` engine's current position to smoothly auto-scroll the lyrics.
    *   Highlight the currently sung line (e.g., bright white text), while surrounding lines are dimmed (gray text).
    *   **Interactive Sync:** If the user clicks a specific line of lyrics, instantly seek the audio player to that exact timestamp.

### Step 3: OpenSubtitles API Integration (`lib/core/subtitles_api.dart`)
*   Implement the API connection to `api.opensubtitles.com` using standard HTTP requests.
*   **Authentication:** Retrieve the API Key that the user pasted into the Global Settings (built in Phase 4).
*   **Search Logic:** When a video is playing, extract its filename and file hash. Send this data to the API to retrieve a list of perfectly matching `.srt` files.

### Step 4: The Subtitle Search UI Logic (`lib/ui/modals/subtitle_search_modal.dart`)
*   Wire the UI (drafted in Phase 4) to the backend API.
*   **Modal Behavior:** 
    *   Display the API search results in a clean list inside the floating modal.
    *   **Sorting:** Split the results visually. Show the "Top 3 Best Matches" (based on file hash) in a distinct top section, followed by "All Results" below it.
    *   Include a visual flag icon indicating the language of each subtitle.
    *   When a user clicks a result, download the `.srt` file **directly into the same directory as the playing video** (using the exact same filename as the video, e.g., `movie.mp4` gets `movie.srt`). This ensures the player's Smart Queuing will automatically load it in the future without downloading it again.
    *   Instantly tell `mpv` to load that newly downloaded `.srt` file as the active subtitle track.
    *   Display a quick OSD message: *"Subtitle Downloaded: [Language]"*.

### Step 5: Auto-Download Subtitles Logic
*   Wire up the toggle switch from Phase 4 ("Auto-Download Subtitles on Video Load").
*   **Background Logic:** If toggled ON, whenever a user opens a video file, silently ping the OpenSubtitles API in the background. If a perfect hash match is found for the user's default language, silently download and apply it, triggering the OSD message.