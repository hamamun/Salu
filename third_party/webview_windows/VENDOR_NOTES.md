# Vendor notes — why this copy of `webview_windows` lives in SALU

SALU vendors the `webview_windows` plugin (upstream:
<https://github.com/jnschulze/flutter-webview-windows>, pub 0.4.0,
upstream commit `ed81bbe`) so it can reach WebView2 controls the upstream
plugin never exposed. There are exactly **two** deltas, both small and both
marked with "SALU addition"/"SALU delta" in the comments where they live.
Everything else is byte-identical to upstream.

---

## Delta 1 — Page colours (`put_PreferredColorScheme`)

> `ICoreWebView2Profile::put_PreferredColorScheme` — the engine's own
> control for what `prefers-color-scheme` answers. It is the same control
> Microsoft Edge's own Appearance setting drives, it applies to the live
> page immediately, and its default (`Auto`) is "follow the OS theme" —
> which is exactly why pages rendered dark inside SALU on a dark-mode PC
> while Edge showed them white.

Command-line tricks (`--blink-settings=…`) are not a supported WebView2
configuration path and lose to the host's own preference sync; this
profile API is the documented, supported way. SALU's Settings → Web →
**Page colours** (Light · Dark · Follow Windows) is wired straight onto it.

### The changes

| File | Change |
| --- | --- |
| `windows/webview.h` | declares `bool SetPreferredColorScheme(int scheme);` |
| `windows/webview.cc` | implements it: query `ICoreWebView2_13` → `get_Profile` → `put_PreferredColorScheme` (no-op `false` on runtimes older than 1.0.1155.38) |
| `windows/webview_bridge.cc` | routes the `setPreferredColorScheme` method-channel call (int arg: 0 = auto, 1 = light, 2 = dark — the `CoreWebView2PreferredColorScheme` values exactly) |
| `lib/src/webview.dart` | `WebviewController.setPreferredColorScheme(int scheme)` |

---

## Delta 2 — Downloads: where a file lands

> `ICoreWebView2DownloadStartingEventArgs::put_ResultFilePath` and
> `put_Cancel`, held on a `GetDeferral()` — the engine's own hook for what
> Edge and Chrome call "Ask where to save each file before downloading" —
> plus `ICoreWebView2Profile::put_DefaultDownloadFolderPath` for the
> folder itself. Both are in the SDK this plugin already pins
> (`1.0.1210.39`), so nothing about the build changed.

Upstream's `DownloadStarting` handler took a deferral, set `Handled`
(hiding the engine's own download flyout — which SALU *wants*, because SALU
draws its own download shelf), read the engine's suggested result path and
wrote it straight back. A download therefore always went to the Windows
Downloads folder without a question, and Dart only ever heard about it
afterwards — as a report, never as a decision.

SALU's handler asks first, when the viewer wants to be asked:

* `Webview::SetDownloadPreferences(bool ask, const std::string& folder)`
  stores the ask flag and puts `folder` on the profile as its
  `DefaultDownloadFolderPath` (an empty folder means "leave the engine's
  alone", which is Windows' own Downloads). It answers whether the folder
  half applied; the ask half is SALU's own flag and always applies.
* **Ask off** — the handler is upstream's: the engine's own path stands
  and there is no round trip at all. The deferral upstream took and never
  completed is now completed, as its contract says.
* **Ask on** — the handler holds the deferral and calls the new
  `OnDownloadStarting` callback (url · suggested path · mime type · total
  bytes · a completer). The bridge turns that into a `downloadStarting`
  method-channel call and waits for the reply; Dart answers `{'path': …}`
  to redirect the download or `{'cancel': true}` to drop it. The completer
  then sets `ResultFilePath` (or `Cancel`), reports `DownloadStarted` to
  the host **only for a download that is really happening**, and completes
  the deferral.
* Every leg that cannot produce an answer — no delegate set, Dart threw,
  the reply has the wrong shape — answers "your own path is fine", never
  "cancel": a prompt SALU could not show must not cost the viewer their
  file.
* The dialog itself is deliberately **not** in this plugin: SALU opens the
  native Windows Save As from Dart through `file_selector` (see
  `lib/core/web/web_download_service.dart`), one download at a time. The
  round trip exists so the plugin stays a plugin and grows no UI.
* Safety: the answer outlives the event handler, so the completer holds
  its own reference to the event args and checks a shared `alive_flag_`
  that `~Webview` flips. A view torn down while the viewer is choosing is
  a download that quietly never happens — not a use-after-free.

### The changes

| File | Change |
| --- | --- |
| `windows/webview.h` | declares `SetDownloadPreferences` and `OnDownloadStarting`, the two callback typedefs (`DownloadStartingCallback`, `WebviewDownloadStartingCompleter`), and the three members behind them (`download_starting_callback_`, `ask_where_to_save_`, `alive_flag_`) |
| `windows/webview.cc` | the `DownloadStarting` handler above; `SetDownloadPreferences`; `~Webview` flips `alive_flag_` |
| `windows/webview_bridge.h` | declares `WebviewBridge::OnDownloadStarting` |
| `windows/webview_bridge.cc` | routes the `setDownloadPreferences` method-channel call (map arg: `askWhereToSave` bool, `defaultDownloadFolder` string) and asks Dart with `downloadStarting`, waiting on the reply exactly as `permissionRequested` already does |
| `lib/src/webview.dart` | `WebviewDownloadRequest`, `WebviewDownloadDecision`, `DownloadStartingDelegate`, `WebviewController.downloadStartingDelegate`, `setDownloadPreferences(...)`, and the `downloadStarting` leg of the method-call handler |

---

## Upgrading

Re-copy upstream over this folder (keep `VENDOR_NOTES.md`), re-apply the
edits in **both** tables above (they are small and marked with "SALU
addition"/"SALU delta" in comments), and update the upstream commit in
this file.
