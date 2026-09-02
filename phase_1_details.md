# Phase 1: Foundation & Window Framework
**Status:** ✅ Completed

## 🎯 Goal
Set up the blank canvas. By the end of this phase, SALU will run as a native Windows application with a beautiful, borderless, dark-mode window that stretches edge-to-edge. It won't play video yet, but it will look like a premium, modern app.

## 🛠️ Step-by-Step Execution Plan

### Step 1: Dependencies & Assets (`pubspec.yaml`)
*   Add `window_manager` to control the native Windows API.
*   Setup the font assets to enforce **Segoe UI Variable** across the entire app.

### Step 2: The Core Entry Point (`lib/main.dart`)
*   Write the initialization code that tells Windows to hide the ugly default grey title bar (`TitleBarStyle.hidden`).
*   Set the minimum window size (e.g., 800x600) and position it in the center of the screen upon opening.

### Step 3: Global Theme (`lib/theme/app_theme.dart`)
*   Create a central theme file.
*   Define the rich dark gray (`#1E1E1E`) as the main app background.
*   Apply the smart, thin, monochromatic icon style and the Segoe UI Variable font.
*   *(Note: The actual UI menu for users to change accent colors will be built in Phase 4, but the foundation for it starts here).*

### Step 4: Custom Hover Title Bar (`lib/ui/widgets/custom_title_bar.dart`)
*   We will code a custom, invisible top bar that contains a `DragToMoveArea`.
*   **Auto-Hide (Unified Global Hover):** The top bar (Close, Maximize, Minimize, and Video Title) will be completely invisible to allow edge-to-edge video. Whenever the mouse moves *anywhere* over the app window, the top bar will gracefully fade in. If the mouse is still for 3 seconds, it will smoothly fade out.

### Step 5: The Main Screen (`lib/ui/screens/home_screen.dart`)
*   Create the primary screen layout (a blank dark canvas) wrapped with our custom title bar. This prepares the exact spot where the `mpv` video engine will be injected in Phase 2.

### Step 6: Single Instance & File Argument Handler (`lib/main.dart`)
*   **Single Instance:** Implement a package (e.g., `windows_single_instance`) to ensure only *one* window of SALU can ever be open at a time.
*   **Argument Parsing:** If SALU is already open and the user double-clicks a `.mp4` file on their computer, the OS will try to open a new window. The Single Instance logic will intercept that file path, send it to the already-open SALU window, and instantly play it without opening a second app.