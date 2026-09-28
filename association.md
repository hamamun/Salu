# SALU — association.md (File Associations · Default Player · Right-click)

> Owner request 2026-09-28. Three features, one Settings tab.
> Rules in force: follow.md — icon-only actions, labels + values only,
> no instruction lines, no confirm dialogs, hover-delay tooltips name a
> control and never teach.

---

## 1. What SALU does (and the one Windows rule)

| # | Feature | Result |
|---|---------|--------|
| A | File associations — Video / Audio / Playlist groups, one checkbox per extension + one per group | SALU registers / unregisters itself for exactly the ticked set |
| B | Default player | One mark opens **Windows Settings → Default apps → SALU** |
| C | Right-click menu | "Play with SALU" + "Add to SALU queue" on media files and folders; "Open with → SALU" comes free with A |

**The Windows rule (locked, not worked around).** Since Windows 8 no app may
silently set itself as the default — the choice is hashed in `UserChoice`
and only the user can make it. So:

- **Associate** = SALU is registered for the extension (icon, "Open with",
  Default Apps list). Where the extension has **no** user choice yet, SALU
  also becomes its class default — Windows accepts that without asking.
- **Default** = the user confirms once in Windows Settings (mark B).
- **Deassociate** = SALU removes only its own entries. Windows falls back to
  the previous app, or asks.

No `UserChoice` hash hacks, no admin rights, no SetUserFTA-style tools.

## 2. Registry plan (per-user, `HKCU` only — never elevates)

```
HKCU\Software\Classes\SALU.<ext>                       ProgID per extension
    (default)            = "SALU Video" | "SALU Audio" | "SALU Playlist"
    FriendlyTypeName     = same
    DefaultIcon\(def)    = "<exe>",0
    shell\open\command   = "<exe>" "%1"
HKCU\Software\Classes\.<ext>\OpenWithProgids   SALU.<ext>  (REG_NONE)
HKCU\Software\Classes\.<ext>\(default)         = SALU.<ext>  only if empty
HKCU\Software\Classes\Applications\salu.exe    FriendlyAppName, SupportedTypes,
                                               shell\open\command
HKCU\Software\SALU\Capabilities                ApplicationName, ApplicationIcon,
                                               ApplicationDescription,
                                               FileAssociations\.<ext> = SALU.<ext>
HKCU\Software\RegisteredApplications           SALU = Software\SALU\Capabilities
HKCU\Software\SALU                             RegisteredExe = <exe>
```

Right-click (feature C):

```
HKCU\Software\Classes\SystemFileAssociations\.<ext>\shell\SALU.Play
HKCU\Software\Classes\SystemFileAssociations\.<ext>\shell\SALU.Enqueue
HKCU\Software\Classes\Directory\shell\SALU.Play
HKCU\Software\Classes\Directory\shell\SALU.Enqueue
    MUIVerb = "Play with SALU" | "Add to SALU queue"
    Icon    = "<exe>",0
    command = "<exe>" "%1"   |   "<exe>" --enqueue "%1"
```

Every change ends with `SHChangeNotify(SHCNE_ASSOCCHANGED)` so Explorer
refreshes icons and menus right away.

**Windows 11:** custom verbs sit under "Show more options". The compact
top menu needs MSIX packaging — out of scope.

## 3. Lifecycle

- **Every launch (after first frame, background):** if `RegisteredExe`
  differs from the running exe (first run, moved, or updated elsewhere),
  refresh the base registration (Applications + Capabilities + ProgIDs of
  already-associated extensions + live context verbs). This keeps "Open
  with → SALU" present even if the tab is never opened. It never claims
  an extension on its own.
- **`salu.exe --unregister`:** removes everything SALU ever wrote, then
  exits. The hook a future uninstaller calls.
- **Arguments:** `"%1"` plays (file or **folder**); `--enqueue "%1"` appends
  to the running queue (plays if nothing is loaded).

## 4. Settings → new tab **Associations** (after Updates, before Shortcuts)

```
DEFAULT PLAYER
  Windows default                    18 / 35   [↗]
VIDEO                                          [☑]   ← group checkbox (tri-state)
  [☑ mp4] [☑ mkv] [☐ avi] …                     wrap of check chips
AUDIO                                          [☑]
  [☑ mp3] [☑ flac] …
PLAYLIST                                       [☐]
  [☐ m3u] [☐ m3u8]
                                  [↺] [✓]      ← revert · apply (only while edited)
RIGHT-CLICK
  Play · Add to queue                        (switch)   ← both verbs together
```

- Chips show the extension; accent text = SALU is already the **actual**
  Windows default for it (read live via `AssocQueryStringW`).
- Ticks are a draft; **apply mark** (tick) writes the set, **revert mark**
  drops the draft. Both only appear while the draft differs from what is
  registered — nothing shifts otherwise (reserved slot).
- Mark B (`open_in_new`) registers first, then opens
  `ms-settings:defaultapps?registeredAppUser=SALU`.
- No helper lines. Tooltips: "Apply", "Revert", "Open Windows default apps",
  "Select all video" etc.
- Apply leaves an OSD `Associations applied` card; no confirm.
- **Not preferences:** associations are system state, so neither group
  reset marks nor the master reset touch this tab.

## 5. Code layout

| File | Role |
|------|------|
| `lib/core/association/association_plan.dart` | Pure: extension groups, ProgIDs, key/value plan for register / unregister / context verbs. Unit-tested. |
| `lib/core/association/association_registry.dart` | `RegistryBackend` interface + Win32 FFI impl (advapi32 `RegCreateKeyExW` / `RegSetValueExW` / `RegDeleteTreeW` / `RegDeleteKeyValueW` / `RegGetValueW`, shell32 `SHChangeNotify` / `ShellExecuteW`, shlwapi `AssocQueryStringW`). |
| `lib/core/association/association_service.dart` | Singleton: state notifiers (associated set, defaults set, context-menu on), `apply`, `setContextMenu`, `openDefaultApps`, `ensureRegistered`, `unregisterAll`. |
| `lib/ui/widgets/associations_tab.dart` | The tab UI. |
| `lib/main.dart` | `--enqueue`, folder args, `--unregister`, launch-time `ensureRegistered`. |
| `test/association_plan_test.dart` | Plan + service against a fake registry. |

## 6. Verification checklist (needs a real Windows 10 + 11 box)

- [ ] Tick mp4 → Apply → Explorer shows SALU icon; "Open with" lists SALU.
- [ ] Fresh extension (no prior app) opens in SALU on double-click.
- [ ] Mark B opens Default apps on SALU's page (Win11 23H2+; older builds
      land on the Default apps root).
- [ ] Untick → Apply → SALU gone from "Open with"; previous app restored.
- [ ] Right-click file → Play / Add to queue; right-click folder → both.
- [ ] `salu.exe --unregister` leaves no `SALU*` keys under `HKCU`.
- [ ] Moving the SALU folder → next launch repoints every command.

## 7. Status

- [x] Plan (this file)
- [x] Implementation (§5).
- [ ] `flutter analyze` + `flutter test test/association_plan_test.dart`
      (the build sandbox could not download the Flutter SDK).
- [ ] Native checks (§6) on Windows 10 + 11.

Notes: multi-selecting files → "Play with SALU" launches one process per
file (Explorer's `%1` model); the last one wins. "Add to queue" appends
each, so it is the multi-select verb.
