# SALU Remote — Expert Opinion (Plain English, No Code)

*Written after reading the actual SALU code at commit `2551473` — `PlayerService`,
`TransportActions`, `BrowserService`, `SettingsService`, the right-click strip,
and your existing `phase_8_details.md` plan.*

---

## 1. The one-minute answer

Your plan is **correct**. Build it exactly this way:

```
   PHONE (Flutter APK)                PC (SALU — Flutter Windows)
   ┌───────────────┐                  ┌────────────────────────────┐
   │ buttons+screens│  ── commands ──▶ │ tiny WebSocket server      │
   │ slider, queue  │   (over Wi-Fi)   │   ↓                      │
   │               │  ◀── state ────  │ TransportActions / Player  │
   └───────────────┘                  └────────────────────────────┘
```

- The **PC is the server**, the **phone is the client**. Never the other way around.
- **WebSocket**, not HTTP polling. One connection, stays open, both directions.
- The phone **never talks to mpv**. It talks to *your* `TransportActions` facade —
  the same one your keyboard, buttons and video-tap already use.
- The phone **never invents state**. It only shows what `PlayerService`'s
  `ValueNotifier`s already publish.

That is it. Everything below is detail about the five things that will actually
decide whether this feels amazing or feels broken.

**Honest size:** this is a *medium* project, not a small one. The server is the
easy half. The phone app UI is straightforward. The part that eats time is
**pairing + discovery + "it just reconnects"** — that is where 70% of the polish
lives, and it is the part your current Phase 8 plan skips.

---

## 2. Good news: your code is already shaped for this

You did the hard architectural work long before Phase 8, whether you noticed or not:

| What you already have | Why it makes the remote easy |
|---|---|
| `TransportActions.instance` — "the single transport facade" | Your comment literally says every action is defined once here. The remote becomes a **third caller** next to the buttons and the keyboard. Zero duplicated logic. |
| `PlayerService` full of `ValueNotifier`s (`isPlaying`, `transportState`, `position`, `duration`, `volumeLevel`, `isMuted`, `currentTitle`, `isBuffering`, `repeatMode`, `shuffleOn`, `subDelay`, `trackSurface`) | The broadcaster is just "listen to these, send JSON". You never have to ask mpv anything. |
| `QueueService` (334 lines, immutable snapshots, undo) | Phase-2 feature — "jump to item 14" — is nearly free. |
| `BrowserService.instance.mode` (Player · Web) | The remote can know which mode the PC is in, and the auto-switch rule is one listener. |
| `SettingsService` (`shared_preferences`, one key per toggle, load-before-first-frame) | `enable_remote` toggle slots in exactly where `mouseOverPreview` and `autoEq` live. |
| `right_menu.dart` already says **"Remote has no widget, no disabled mark and no hit target"** | The slot is reserved and documented. That is where the Remote panel goes. |
| `main.dart` starts `BrowserService` warm-up *after* the first frame | Copy that pattern for the server: never let networking delay a cold start. |

**Conclusion:** the remote is not a new subsystem. It is a **thin adapter** bolted
onto a facade you already designed. If it ever starts to feel like a big new
subsystem, something has gone wrong in the design.

---

## 3. The five things that decide success

### 3.1 Discovery — how the phone finds the PC

Your plan says **mDNS/Bonjour** as the main method. My advice: **make mDNS the
bonus, not the foundation.**

Reality check on mDNS at home:
- Windows Firewall blocks the multicast traffic unless the user allows it.
- Many cheap routers **drop multicast** entirely.
- Guest Wi-Fi and "AP isolation" silently break it.
- Android 13+ needs an extra permission (`NEARBY_WIFI_DEVICES`) just to look for
  devices on Wi-Fi, and the multicast lock has to be held.

Any one of those fails and your app looks broken — while the network is perfectly fine.

**Recommended order of reliability:**

1. **QR code on the PC screen (primary).** PC shows a QR in the Remote panel.
   Phone scans it once → it knows the IP, the port and the pairing secret.
   This is one tap, works on every router, needs no permissions, and is
   genuinely nicer than typing an IP on a phone. This should be the headline feature.
2. **Saved device (default after pairing).** Phone remembers the PC. Every launch
   after that = open app → already connected. The user may never see the QR again.
3. **Manual IP + port (always available).** The escape hatch. Some users like it.
4. **mDNS auto-discovery (nice-to-have).** Only worth it if you want the
   "no QR at all, it just appears in a list" magic. Do it *last*, and treat
   failure as normal, not as an error.

A small but crucial detail: **the port must be flexible.** Your PC might already
have something on 8080. Bind to a preferred port, and if it is taken, take the
next free one — then advertise the **actual** port through the QR and through the
mDNS record. Never let the phone assume a fixed port.

### 3.2 Windows Firewall — the #1 "why doesn't it work" support ticket

A background server on a Windows PC is **blocked by default.** The first time
SALU listens, Windows pops "Allow SALU to communicate on private networks?"
If the user clicks **Cancel** (very common — it looks scary), the phone will
never connect, forever, and nothing will look wrong on either side.

Handle it like a pro:
- Detect "server is up but nobody has ever connected and it has been 60 seconds" →
  the Remote panel says, in plain words: *"Windows may be blocking the connection.
  Click here to open Windows Firewall settings."*
- Better: your Inno Setup installer (Phase 9) adds the firewall rule, so a
  proper install never sees the prompt at all.
- Also say in the panel which network it is offering itself on, e.g.
  *"Available on Home-WiFi at 192.168.1.42"*. That single line prevents most confusion.

### 3.3 Security — the biggest gap in the current plan

Right now `phase_8_details.md` says: run a WebSocket server on `0.0.0.0`, accept
JSON commands, and put a single on/off toggle in Settings. That means **any device
on the same Wi-Fi can pause your movie, change your volume, or open URLs on your PC**
— no questions asked. On a home network that is *mostly* fine. On hostel, café,
office or hotel Wi-Fi it is a real problem.

Simple, low-effort fixes (do all of them):

1. **Pairing secret.** The first message from a phone must include a token. No
   token → connection closed immediately. The token comes from the QR code or a
   6-digit PIN shown on the PC screen.
2. **Private addresses only.** If the connecting IP is not a private LAN address
   (192.168.x.x, 10.x.x.x, 172.16–31.x.x), refuse it. Three lines of logic, kills
   the entire "someone found my public IP" class of problem.
3. **Pairing window.** The QR/PIN is only valid for ~60 seconds after the user
   clicks "Pair a new device". A QR taped to the screen forever is a permanent
   password.
4. **Remembered devices list.** PC panel shows *"Pixel 7 — connected"*, with a
   forget button. This is the feature that makes people feel safe, even if they
   never use it.
5. **Nothing outside the LAN.** Never port-forward. Never add an internet mode
   into the app itself. (See §8 for the right way to get "works anywhere".)
6. **The off switch is a real off switch.** Toggle off = the listener is closed and
   the port is freed, not just "ignore commands". Matches the promise in your plan.

### 3.4 Don't flood the phone — state updates need a throttle

Your Phase 8 text says *"millisecond-perfect UI updates"*. That is the one thing
I would explicitly overrule.

- `PlayerService.position` fires **many times per second**. Sending every change
  over Wi-Fi to a phone whose screen shows `12:34` is pure battery drain and
  radio wake-ups for zero visible benefit.
- **Rule of thumb:**
  - **Progress bar / time:** ~4 updates per second (250 ms). Looks perfectly smooth.
  - **Events (play, pause, stop, track change, volume, mute, mode):** send
    **immediately**, no throttle. These are what the user actually feels.
- **Always send a full snapshot, never a diff.** The state is ~200 bytes; sending
  the whole picture each time means a phone that reconnects mid-movie is instantly
  correct, and you never have to debug "the phone thinks it's paused but it isn't".
  Self-healing beats efficient here.

### 3.5 Reconnect — the difference between a toy and a tool

The phone will lose the connection constantly: screen off, Wi-Fi sleep, PC asleep,
router hiccup, user walks to the kitchen.

- **PC side:** on every new connection, push a full state snapshot *immediately*.
  The phone should never have to ask.
- **Phone side:** auto-reconnect with backoff (try at 0.5 s, 1 s, 2 s, 5 s…).
  No "Reconnect" button in the user's face unless it has been failing for a while.
- **Show connection health quietly:** a small dot — green connected / amber
  reconnecting / red disconnected. Never a modal dialog.
- **PC asleep / off** is not an error, it is a state: *"Can't find your PC.
  Is SALU running and is the PC awake?"* — that sentence solves 90% of support.
- **Keep the phone screen on while the remote is open** (wakelock). Obvious in
  hindsight, easy to forget, and it is the #1 reason people abandon a remote app.

---

## 4. What I would change in your existing Phase 8 plan

| Your plan says | My advice |
|---|---|
| WebSocket server on `0.0.0.0:8080` | Keep the idea, but: **flexible port**, **private-IP filter**, **token required before anything else**. |
| mDNS as the auto-discovery mechanism | Keep it, but **demote it to step 4**. QR pairing is the primary path. |
| `shelf` + `shelf_web_socket` packages | Not needed. `dart:io`'s built-in HTTP server can upgrade to WebSocket directly — **fewer dependencies** for a tiny LAN server. Reach for `shelf` only if you later want to serve an optional debug page. |
| "State broadcaster, millisecond-perfect" | **Throttle the position** to ~4/sec; send events instantly; always full snapshots. |
| Steps 1–4 (server, commands, state, toggle) | Add three steps the plan is missing: **(5) pairing + token**, **(6) Remote panel UI on the PC** (QR, PIN, device list, live status), **(7) reconnect + version handshake**. |
| Commands connect "directly into `PlayerService`" | Connect into **`TransportActions`** instead — that is your facade, and it is where the OSD, seek ramp and queue semantics live. Going straight to `PlayerService` would give the remote different behaviour from the buttons. |
| — | **Version handshake.** Phone and PC must exchange a protocol version on connect. Mismatch = *"Update the remote app"*, not a mysterious half-working app. Both sides are Dart, so share one protocol file (see §6) and this is free. |

---

## 5. The phone app — what v1 should be

Think of the phone as a **TV remote**, not a second player. Big thumb targets,
dark theme copied from SALU, one hand.

**v1 screens (this is the whole app):**

1. **Connect screen** — "Scan QR" (big) · "Enter IP manually" (small) · list of
   previously paired PCs.
2. **Remote screen** — the one that matters:
   - Now-playing: title, position / duration, playing-or-paused.
   - Big round **Play/Pause** in the middle, **Stop**, **Prev/Next**.
   - **Seek bar** you can drag (and it should *not* fight the PC's updates while
     your thumb is down — lock the slider during the drag, then commit).
   - **Volume slider**, mute button.
   - Shuffle / repeat toggles (they already exist in your service).
   - Gestures if you like: swipe up/down = volume, swipe left/right = seek.
     Optional, but it makes the app feel expensive.
3. **Queue screen (v2)** — the list from `QueueService`, tap to jump. This is the
   single most-loved remote feature in any player, because it means "put on
   episode 6" without touching the PC.
4. **Channels / streams (v2)** — search your loaded M3U list and start a channel.
   Your `ChannelLoadService` already holds everything needed.
5. **Send a link (v2)** — paste a URL or YouTube link, play it on the PC.
   Tiny feature, enormous satisfaction.

**What NOT to build (scope traps):**

- ❌ Playing media *on the phone* / casting your phone's screen to the PC.
  That is a completely different product (streaming, transcoding, sync).
  This is a **remote control**, and it should stay one.
- ❌ A live video preview of the PC screen on the phone. Everyone asks for it.
  It is a stream, not a command, and it is 10× the work.
- ❌ Your own lighting/blur animations "like SALU". The phone must be *fast*.
  Remote apps live and die on input lag, not beauty.
- ❌ Cloud accounts, login, sharing. Not now.

---

## 6. One shared protocol file — the cheap trick that saves you weeks

Both apps are Dart. So do this:

- Put the message shapes in **one small file** with a version number, and have
  **both** projects use that exact file (a local path package, or just copied and
  kept in sync with a comment saying "copied — do not edit separately").
- The PC then **cannot drift** from the phone. Renaming `volume_up` on one side
  becomes a compile error instead of a silent runtime bug you chase at 1 a.m.

**Message direction and shape, in plain words:**

- Phone → PC: a small command name, plus a value if needed.
  Verbs to start with: `play_pause`, `stop`, `next`, `previous`, `seek_forward`,
  `seek_backward`, `seek_to` (the slider), `volume_up`, `volume_down`,
  `volume_set`, `mute_toggle`, `shuffle_toggle`, `repeat_cycle`, `jump_to_index`.
- PC → phone: `state` (full snapshot), `event` (something just happened),
  `ack` (command worked), `error` (command refused, with a plain-words reason),
  `mode` (Player or Web), and on connect `hello` (name + version + features).
- Add **one version number** to everything. It costs nothing now and saves a
  support nightmare later.

---

## 7. Web mode and the "two modes" question

Since SALU owns a whole window and has two modes, you must decide: what does the
remote do when the PC is in **Web mode**?

My recommendation:

- **v1: player-only.** The remote controls playback. Simple, clear, done.
- **But add one rule now: a playback command arriving while the PC is in Web mode
  switches SALU back to Player mode.** Otherwise the user taps Play on their phone
  and *nothing visibly happens on the PC* — because the browser is on top.
  That is the kind of thing that makes an app feel broken even though it worked.
- Same idea for a minimized window: when a remote command starts real playback,
  `show()` + `focus()` the window so the user isn't left staring at nothing.
- **v2: web controls** — `browser_open_url`, `back`, `forward`, `reload`,
  `new_tab`, `close_tab`, list of open tabs. Sending a URL from the phone
  keyboard into the PC browser is a genuinely nice feature, and it is just more
  verbs on the same socket. No new architecture.

---

## 8. "I want to use it from outside my house"

Out of the box, this works on **LAN only** — same Wi-Fi. That is the correct
default, and it is also the safe default.

If you later want it to work from anywhere, there are two roads:

- ✅ **The free, zero-code road: a mesh VPN like Tailscale or WireGuard.**
  Install it on the PC and the phone, and they behave as if they are on the same
  Wi-Fi. The remote app needs **no changes at all**. This is what I would do, and
  I would write one line about it in the docs.
- ❌ **The expensive road: your own relay/cloud server.** Accounts, hosting,
  security, TLS, scaling. Months of work, and it is a different product. Do not
  start here.

---

## 9. Build order (and rough sizing)

Do it in this order. Each step is usable and testable on its own — that is the
whole point of the order.

| Step | What you build | Size | Why first |
|---|---|---|---|
| **R1** | PC server: listen, token check, accept commands, push state. **Test it with a plain desktop client** — no phone at all. | Medium | You can prove the entire protocol before writing a single Android screen. Huge time saver. |
| **R2** | Android APK skeleton: connect screen (manual IP), transport buttons, now-playing. | Medium | The payoff moment. You now have a working remote. |
| **R3** | PC Remote panel: on/off toggle, QR code, PIN, "Pair new device", connected devices list, forgotten devices. | Small–Medium | Turns "a developer's tool" into something your family can use. |
| **R4** | Polish: remembered devices, auto-reconnect + backoff, connection dot, keep-screen-on, version handshake, Windows firewall guidance. | Medium | This is the step that decides whether you use it every day. |
| **R5** | Extras: queue list + jump, channel search + start, send-a-link, web-mode verbs, subtitle/audio track picker. | Medium+ | Now it is better than every generic remote app. |

**R1 is the step people skip and regret.** A 60-line desktop test client that
prints every state message will save you days of guessing whether a bug is in the
PC server or the phone UI.

---

## 10. Cheat sheet: symptom → real cause

| What the user sees | What is actually wrong |
|---|---|
| Phone connects, then instantly drops | No token / wrong token — the server is refusing it correctly. |
| Phone can never connect, PC side looks fine | **Windows Firewall** blocked it. The #1 cause, by far. |
| Works on Ethernet, not on Wi-Fi (or vice versa) | The PC has multiple network adapters (VPN, Hyper-V, WSL, VirtualBox all add fake ones). You must enumerate the real private IPv4s and pick the right one — or let the user choose in the panel. |
| Phone can't find the PC, but the IP is right | Router has **AP isolation** / guest network isolation on, or the two devices are on different subnets (2.4 GHz vs 5 GHz guest, or phone on mobile data). |
| Connects but Android logs silent failures on `ws://` | Android blocks plaintext traffic by default on newer versions — allow cleartext **for private LAN addresses only**. |
| Time display stutters / freezes while the movie plays | You are sending either too many updates, or diffs instead of snapshots. §3.4. |
| Phone app is dead after the screen was off | No auto-reconnect, or no keep-awake. §3.5. |
| Remote presses flash OSD cards on the PC | Expected with `TransportActions` (that is the facade's job). If it annoys you, add a "silent" flag for remote-originated commands — but keep it one code path, never a second implementation. |
| Remote and buttons behave differently for Stop / Next | You wired the remote to `PlayerService` instead of `TransportActions`. |

---

## 11. Decisions to make before R1 starts

1. **Pairing method:** QR code first (my recommendation), or PIN first, or both?
2. **One controller or many?** One phone at a time is simpler and clearer
   ("Pixel 7 has control"). Alternatively allow many — but then you must decide
   who wins a volume tug-of-war. I recommend **one active controller**, with
   extra phones allowed to watch-only.
3. **Should remote commands show OSD cards on the PC screen?** (My vote: yes,
   except volume — you are already looking at the phone for that.)
4. **Should the remote be able to control Web mode, or player only?** (My vote:
   player only in v1; Web verbs in v2.)
5. **Is this going in this same repo** as a second Flutter project, or a separate
   repo? (My vote: a second app in a folder of the same repo — the shared protocol
   file is the whole reason, and one repo keeps the two from drifting.)

---

## 12. Short version, if you read nothing else

- Your architecture plan is right: **PC = WebSocket server, phone = APK client.**
- Make the remote a **thin adapter**: commands into `TransportActions`, state out
  of `PlayerService`'s notifiers. No new engine, no duplicated logic, ever.
- **QR pairing beats mDNS.** mDNS is a bonus, never the only road.
- **Add the token now.** Your Phase 8 has no authentication at all — that is its
  one real design flaw.
- **Throttle the position** (4/sec), send everything else instantly, and always
  send full snapshots.
- **Reconnect + keep-screen-on** turn this from a demo into something you use daily.
- Build the PC side and test it from a desktop before touching Android.
- The remote is a **remote**, not a caster. Keep it that way and it will be great.
