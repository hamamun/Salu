# Phase 6: Web & Stream Manager
**Status:** ✅ Completed

## 🎯 Goal
Expand SALU beyond local files. By the end of this phase, users will be able to browse streaming websites directly inside the app, and save up to 10 M3U network streams and 15 Web Bookmarks instantly using `shared_preferences`.

## 🛠️ Step-by-Step Execution Plan

### Step 1: The Left Library Sidebar (`lib/ui/panels/library_panel.dart`)
*   **Final Layout Decision:** Create a new, dedicated sidebar that slides in from the **Left Edge** of the screen (triggered by the Library button on the OSC). This prevents it from conflicting with the Quick Settings panel on the right.
*   **Layout:** A clean, blurred-glass sidebar divided into two distinct sections:
    1.  **Saved Streams (M3U):** A list showing the saved names of network streams.
    2.  **Web Bookmarks:** A list of saved website URLs.
*   *Note: Both lists will display a small "Empty" message if nothing is saved yet.*

### Step 2: Stream Data Management (`lib/core/stream_manager.dart`)
*   Implement `shared_preferences` to handle the data saving.
*   **Logic:**
    *   Create a function to save a Stream Name and its `http://` or `.m3u` URL (Enforce a strict maximum limit of 10 items).
    *   Create a function to save a Website Name and its URL (Enforce a strict maximum limit of 15 items).
    *   Add a small `+` icon in the Left Library Sidebar to manually paste and save a new URL.
    *   Add a "Trash" icon next to saved items to delete them.

### Step 3: Network Stream (IPTV/M3U) Playback (`lib/core/network_player.dart`)
*   When a user clicks one of their saved M3U streams, pass the URL directly to the `mpv` engine.
*   **Handling Massive IPTV Playlists:** 
    *   When an M3U file is loaded, it populates the **Playlist Tab** (Right Panel). 
    *   **IPTV Playlist UI Adjustments:** When a massive M3U is detected, the Playlist Tab dynamically updates to include a "Clear Playlist" button and a **"Group By" dropdown filter** (Group by: Category, Country, Language, or Flat/None), assuming the M3U file contains these standard metadata tags.
*   **Live Stream OSC Adjustments:** 
    *   Detect if the current media is a "Live Stream" (where duration is unknown).
    *   Automatically disable/hide the Timeline Slider and Exact Seeking buttons.
    *   Keep Play/Pause, Volume, and the **Previous/Next buttons** (which act as "Channel Up / Channel Down" to cycle through the IPTV list).

### Step 4: The Built-in Web Browser (`lib/ui/screens/browser_screen.dart`)
*   Install the `webview_windows` package (which strictly utilizes the built-in Windows WebView2 engine).
*   **Logic:** When a user clicks a saved Web Bookmark, transition the main SALU screen to the `BrowserScreen`.
*   **Browser UI & Restrictions:**
    *   **NO Media Controls:** The SALU OSC (Play/Pause, Volume) is completely hidden in this mode. The streaming website will provide its own video player controls.
    *   **Top Tab Bar:** Create a multi-tab interface at the top of the screen (similar to standard browsers).
    *   **Navigation Buttons:** Inside the active tab, include exactly four buttons: **Home**, **Back**, **Forward**, and **Close Browser** (to return to the main SALU video player).
    *   **Multi-Tab Navigation:** If a user clicks a new Web Bookmark while the browser is already open, it spawns a new Web Tab within the `BrowserScreen` instead of overwriting the current page.
*   **Memory Management (Auto-Cleaning):** Implement a `dispose()` function. Whenever the user clicks "Close Browser" to return to the video player, instantly destroy the WebView controllers, clear the session cache, and flush the RAM to ensure SALU remains lightweight.