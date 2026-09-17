# Vendor notes — why this copy of `webview_windows` lives in SALU

SALU vendors the `webview_windows` plugin (upstream:
<https://github.com/jnschulze/flutter-webview-windows>, pub 0.4.0,
upstream commit `ed81bbe`) so it can reach **one** WebView2 API the
upstream plugin never exposed:

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

## The delta from upstream 0.4.0 (the ONLY changes)

| File | Change |
| --- | --- |
| `windows/webview.h` | declares `bool SetPreferredColorScheme(int scheme);` |
| `windows/webview.cc` | implements it: query `ICoreWebView2_13` → `get_Profile` → `put_PreferredColorScheme` (no-op `false` on runtimes older than 1.0.1155.38) |
| `windows/webview_bridge.cc` | routes the `setPreferredColorScheme` method-channel call (int arg: 0 = auto, 1 = light, 2 = dark — the `CoreWebView2PreferredColorScheme` values exactly) |
| `lib/src/webview.dart` | `WebviewController.setPreferredColorScheme(int scheme)` |

Everything else is byte-identical to upstream `ed81bbe`.

## Upgrading

Re-copy upstream over this folder (keep `VENDOR_NOTES.md`), re-apply the
four edits above (they are small and marked with "SALU addition" in
comments), and update the upstream commit in this file.
