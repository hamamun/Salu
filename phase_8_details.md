# Phase 8: Android Remote Server
**Status:** ✅ Completed — `lib/core/remote/` now ships the `shelf_web_socket` server (`websocket_server.dart`, plus a `GET /health` probe endpoint), the JSON command interpreter (`command_handler.dart` → `PlayerService`), the throttled state broadcaster (`state_broadcaster.dart`), a zero-dependency mDNS responder (`mdns_broadcaster.dart` announcing `_salu-remote._tcp.local`), and the `remote_server.dart` facade honoring the Settings → Remote "Enable Remote Control Server" switch (off = everything shut down).

## 🎯 Goal
Prepare SALU to be controlled remotely. By the end of this phase, the Windows application will run a lightweight, invisible local server in the background that is ready to accept commands (Play, Pause, Volume, Seek) from the future Android companion app.

*Note: This phase strictly builds the backend server logic inside the Windows app. The actual Android companion app UI and its implementation will be built as a separate project after the core SALU Windows app is fully completed.*

## 🛠️ Step-by-Step Execution Plan

### Step 1: WebSocket Server Setup (`lib/core/remote/websocket_server.dart`)
*   Implement the `shelf_web_socket` and `shelf` packages to create a lightweight, local server.
*   **Logic:**
    *   On SALU startup, initialize the server to listen on a specific port on the local network (e.g., `ws://0.0.0.0:8080`).
    *   **Auto-Discovery:** Implement an mDNS (Multicast DNS / Bonjour) broadcaster. This will broadcast a silent signal over the Wi-Fi network containing the PC's IP and port.

### Step 2: Command Receiver API (`lib/core/remote/command_handler.dart`)
*   Create an interpreter that listens for incoming JSON messages from the WebSocket.
*   **Supported Commands to Map:**
    *   `{"action": "play_pause"}`
    *   `{"action": "volume_up"}` / `{"action": "volume_down"}`
    *   `{"action": "mute_toggle"}`
    *   `{"action": "seek_forward"}` / `{"action": "seek_backward"}`
    *   `{"action": "next_track"}` / `{"action": "previous_track"}`
*   Connect these exact commands directly into the `PlayerService` (from Phase 2) to instantly trigger the video engine.

### Step 3: Player State Broadcaster (`lib/core/remote/state_broadcaster.dart`)
*   The server shouldn't just *receive* commands; it needs to broadcast what is happening.
*   **Logic:** Create a listener attached to the `mpv` engine that constantly broadcasts JSON data back through the WebSocket (ensuring millisecond-perfect UI updates for any connected client).
*   **Data to Broadcast:**
    *   Current playing filename/title.
    *   Current playback state (Playing vs Paused).
    *   Current volume level (0-200%).
    *   Current timestamp and total duration.

### Step 4: Security & Permissions
*   Add a toggle in the Global Settings (Phase 4): `[x] Enable Remote Control Server`. 
*   If toggled off, the WebSocket server completely shuts down to ensure maximum privacy and zero background network activity when not in use.