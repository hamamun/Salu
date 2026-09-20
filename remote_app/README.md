# SALU Remote — Android app (dev mode)

The phone half of SALU Remote (`remote.md` §17, `remote_apk_ui.md`).
Target: **Flutter Android app, run from Android Studio over USB, paired by scanning the
PC's QR.** No cloud, no accounts, LAN only.

> **Where the source lives.** This folder (`Salu/remote_app/`) is the staging copy —
> the session that writes it is pinned to the SALU repo, so it cannot commit into your
> separate repo. You copy it across; see §1. Only `lib/`, `pubspec.yaml` and `test/` come
> from here — **your `android/` folder stays yours** (it must match your Flutter version).

---

## 1. Bootstrap — do this once in your new repo

Create the repo, open a terminal in it, and run exactly this:

```bash
flutter create --org app.salu --project-name salu_remote --platforms=android .
flutter pub add mobile_scanner shared_preferences
flutter run            # with the phone plugged in — proves the toolchain BEFORE my code lands
```

That last `flutter run` matters: it installs the stock counter app on your phone. If that
works, everything that follows is my code's fault, not your toolchain's. **Tell me when it
works.**

Then copy these three things from this folder into the repo root:

| Copy | Over |
|---|---|
| `lib/` | the generated `lib/` (delete the stock `main.dart` first) |
| `pubspec.yaml` | the generated one (keeps your resolved versions — see the note below) |
| `test/` | new folder, if any |

**Do not copy `android/`.** Your generated one is correct for your Flutter version. It
only needs the edits in `android/APP_EDITS.md` (3 small changes: two permissions, one
intent filter, one `minSdk`).

**The one dependency note.** `pubspec.yaml` here asks for `mobile_scanner: ^5.2.3` and
`shared_preferences: ^2.3.0`. If `flutter pub get` complains that a version does not
match your SDK, run `flutter pub upgrade --major-versions` and if the scanner's API
changed, send me the `flutter analyze` output — I fix the call sites, you don't hunt
through them.

Then:

```bash
flutter analyze          # expect zero issues; if not, paste the output to me
flutter test             # protocol + model tests, no phone needed
flutter run              # the real thing
```

---

## 2. What is being built, and in what order

`remote_apk_ui.md` §10, all three tabs. Each step is runnable on the phone — the app is
never in a broken state between them.

| Step | Deliverable | State |
|---|---|---|
| A1 | Connect sheet (QR + manual) → **Play**: title, seek, transport, volume, mode pill, **playlist card** | building now |
| A2 | **Browse**: Files (PC drives, paging, quick ▶/＋, select mode) + Streams (M3U library, Add URL) | next |
| A3 | **Tune → Subtitles** (tracks, sync, OpenSubtitles search + download) and **Audio** | next |
| A4 | **Tune → Equalizer** (curve, 10 sliders, presets, Auto EQ, Speed chips) | next |
| A5 | **Web body** (both shapes) + **D-pad** + Focus mode + Settings → Play screen + activity dot | next |

### The file map — and what is already written

```
lib/
  main.dart                      app root, lifecycle, resume                🔜
  protocol/remote_protocol.dart  ✅ copied from the PC, do not edit separately
  core/
    models.dart                  ✅ snapshot + every *_result, parsed and typed
    client.dart                  ✅ WebSocket, auth, reconnect, ping, request/reply
    reply.dart                   ✅ one reply type for every verb
    prefs.dart                   ✅ remembered PC + UI prefs (Focus mode, checklist)
    error_copy.dart              ✅ the PC's error codes in the spec's own words
    screen.dart                  ✅ keep-screen-awake, via the channel in APP_EDITS §3
  ui/
    theme.dart                   🔜 SALU's palette + typography, ported
    marks.dart                   🔜 every CustomPainter mark (no image assets, per §9)
    widgets/…                    🔜 seek bar, volume bar, chips, cards, list rows
    screens/connect_sheet.dart   🔜 QR scan (mobile_scanner) + manual entry
    screens/home.dart            🔜 three tabs, header, mini strip, mode pill
    screens/play_tab.dart        🔜 Player shape + Web shape (§4.1, §4.2)
    screens/browse_tab.dart      🔜 Files + Streams (§5)
    screens/tune_tab.dart        🔜 EQ + Subs + Audio + D-pad (§6)
    screens/settings.dart        🔜 Play-screen checklist, forget PC, diagnostics
  dev/mock_pc.dart               🔜 debug-only fake PC, so the UI runs with no PC at all
test/
  parsing_test.dart              ✅ snapshot/results/errors/protocol — `flutter test`
android/APP_EDITS.md             ✅ the four platform edits, verbatim
```

🔜 = next turns, in the A1 → A5 order above.

### Two things worth knowing before A5

1. **`web_key` does not exist on the PC yet.** The D-pad (§6.0) needs it, plus the focus
   ring SALU must draw on the page so you are not steering blind. `remote.md` §17.4 lists
   `browser_nav` only. I will add the verb and the ring on the PC side when A5 lands — the
   phone hides the D-pad until the PC advertises it in `hello.features`, so a half-built
   PC never shows a dead button.
2. **Fixed on the PC while writing this client:** `normalizePairingCode` used
   `RegExp(r'[-\\s]')`. In a *raw* string that class is `-`, backslash and the letter `s`
   — so it stripped the `S` out of any code containing one (about one code in thirty-one
   could never pair, at random) and never stripped spaces. It is now
   `code.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '')`, with
   `test/remote_pairing_test.dart` pinning it. Worth knowing, because the old behaviour
   looked exactly like a flaky app.

---

## 3. What *you* need installed (you said this is already done — checklist)

1. **Flutter SDK** (3.22+) on `PATH` — `flutter doctor -v` shows no red for Android.
2. **Android Studio** + the **Flutter** and **Dart** plugins (Settings → Plugins).
3. **Android SDK** + **Platform-Tools** + a **build-tools** version — accept the licences:
   `flutter doctor --android-licenses`.
4. On the **phone**: Settings → About → tap *Build number* 7×, then
   Developer options → **USB debugging ON** (+ *Install via USB* on Xiaomi/Redmi).
5. Plug in, choose **File transfer / MTP** on the phone's USB notification, accept the
   **"Allow USB debugging?"** prompt (tick *always allow*). `flutter devices` must list it.

Nothing else. No phone-side app, no scrcpy, no SDK-emulator work.

---

## 4. The dev loop

1. Android Studio → **Open** → your repo folder (the one with `pubspec.yaml`).
2. It runs `pub get` + Gradle sync. First sync is slow (2–5 min); after that it is cached.
3. Pick your phone in the device dropdown → **Run** (▶). First install takes ~30 s.
4. Edit code → **hot reload** (`Ctrl+\`), hot restart (`Ctrl+Shift+\`).
5. **Logcat** inside Android Studio shows `[SALU remote] …` lines from `debugPrint`.

**The PC side, on the same Wi-Fi as the phone:**

1. Run SALU on the PC → Settings → General → Remote **ON** (default).
2. Right-click the picture → the strip → **Remote** (rightmost) → the QR panel.
3. On the phone: the **Connect** sheet opens on first launch → **Scan QR** → point at the
   PC screen → it pairs, saves the token, and never asks again.
4. Next launches go straight to **Play**, already connected.

**The dev-only shortcut (no PC needed).** If the app is started with
`--dart-define=SALU_MOCK=1`, it runs a fake PC inside the app: full snapshot stream, a
real queue, fake file listings and a fake tune/subtitle surface. That is how the UI can be
worked on with the PC switched off. (Lands with A1.)

---

## 5. Things that will bite you — read before debugging anything

| Symptom | Cause / fix |
|---|---|
| Phone can never reach the PC, PC looks fine | **Windows Firewall** on the PC (the panel shows a hint after 90 s), or the Wi-Fi network profile is **Public** — set it to Private. |
| Paired yesterday, dead today | The PC's IP changed (router DHCP). The Connect sheet shows the old address; re-scan the QR. The client tries the remembered address first, then asks you. |
| Works on Wi-Fi, fails on USB tethering/mobile data | The PC refuses non-private peers by design (`remote.md` §7.1) — the phone must be on the same LAN. |
| `SocketException: Connection refused` | SALU is not running, or Remote is toggled off, or the port moved (it tries 7258, then 7259…7267). |
| `Cleartext HTTP traffic not permitted` | The manifest edit in `android/APP_EDITS.md` was skipped. `ws://` on the LAN is cleartext by design. |
| Gradle fails after a Flutter upgrade | `flutter clean && flutter pub get`, then re-sync. |
| The phone sleeps and the app goes stale | Expected — the socket is reaped. It reconnects on resume and asks for a fresh snapshot. Keep-screen-awake is on while the app is open (v1; a foreground service is v2). |

---

## 6. When something fails, send me this

1. `flutter analyze` output (whole thing — it is short).
2. The **first** red block from the Android Studio Run console, not the last.
3. If it is a runtime problem: the Logcat lines containing `[SALU remote]`, plus what the
   PC printed (the `[SALU] remote: …` lines in SALU's own console).

With those three I can fix it in one pass without guessing.

---

## 7. Rules this app obeys (from the specs — so nothing drifts)

- The phone **never plays media**, never holds its own truth, never talks to anything but
  the PC (`remote_apk_ui.md` §1).
- The PC's snapshot is the only pushed message; everything else is request → reply, paged
  (`remote.md` §17.2). The phone diffs the snapshot; it never invents state.
- Transport goes through the PC's own facade — the phone sends verbs, never "plays" anything.
- **No thumbnails, ever.** Names, sizes, marks. Images over the socket would make the
  fastest screen the slowest.
- **Read-only file browser.** There is no delete/rename/move/upload path in this app, and
  none in the PC's API either.
- The OpenSubtitles key never leaves the PC; the phone sends a query and gets rows.
- Optimistic where it matters (transport, sliders, EQ), locked against incoming updates
  while a finger is down (`remote_apk_ui.md` §8).
