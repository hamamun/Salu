# Phase 2: Core Media Engine
**Status:** ✅ Completed

## 🎯 Goal
Breathe life into the player. By the end of this phase, SALU will successfully load and play a video file using the powerful `mpv` engine with hardware acceleration active. The video will sit perfectly behind the Phase 1 invisible title bar.

## 🛠️ Step-by-Step Execution Plan

### Step 1: Media Engine Dependencies (`pubspec.yaml`)
*   Add the holy trinity of the `media_kit` Flutter package:
    1.  `media_kit` (The core logic)
    2.  `media_kit_video` (The UI widget to display the video)
    3.  `media_kit_libs_video` (The actual native Windows `libmpv2` engine binaries)

### Step 2: Global Initialization (`lib/main.dart`)
*   Inject `MediaKit.ensureInitialized()` into the very first lines of the app startup. This safely boots up the `mpv` C++ engine in the background before the UI even draws.

### Step 3: The Player Service (`lib/core/player_service.dart`)
*   Create a dedicated manager for the player. We don't want player logic mixed with UI code.
*   Initialize the `Player()` object.
*   Setup the `VideoController()` which links the raw engine to the Flutter screen.
*   Enable `hwdec` (Hardware Decoding) by default so the user's graphics card (GPU) does the heavy lifting, keeping CPU usage low.

### Step 4: The Video Canvas (`lib/ui/screens/video_screen.dart`)
*   Create the widget that holds the actual video feed: `Video(controller: controller)`.
*   Ensure the video fits the screen perfectly (scaling) without distorting the aspect ratio.
*   Place this `VideoScreen` inside the `HomeScreen` we built in Phase 1, making sure it stretches edge-to-edge.

### Step 5: Local File Testing Logic (Drag & Drop)
*   Implement a basic drag-and-drop listener over the main window. 
*   This will allow you to drag your own local video file from your Windows desktop and drop it directly onto the SALU window to play it.
*   *(Note: You will run this on Windows to confirm your local video plays smoothly, and that dragging the edges of the window dynamically resizes the video fluidly without lag).*