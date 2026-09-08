# SALU — channel grouping & favourites study

**FINAL — approved by the owner on 2026-09-08 for points 5 and 6.**
Grouping and favourites **must be implemented exactly as shown in this preview**.
The version committed with this sign-off is the binding visual and interaction
reference; do not redesign or alter it without explicit owner approval.

This is still a **browser design reference**, not production Flutter/M3U code.
It does not open mpv or play actual streams. The binding decisions and exact
implementation contract are in `../../playlist_imp.md` §§10.0–10.16, especially
§10.15. Port the approved UI/behaviour into Flutter and `shared_preferences`;
do not copy study-only controls, fixture data, seeded favourites or mock playback.

## Run

From the repository root:

```sh
python3 -m http.server 8123 --bind 0.0.0.0 --directory design/iptv-channel-preview
```

Use the platform's port-8123 Live Preview. All browser assets and requests are
relative to that host; no browser request targets a sandbox localhost service.
No build step, JS framework or production dependency is needed.

## Approved interactions

- The first panel-header mark opens the **Group by** pill. Hover-delay tooltips
  name Flat, Category, Language and Country. **Every fresh load starts Flat.**
- Category preserves provider order; country/language sort alphabetically;
  `Unknown` is last. Only one group can be open. A collapsed current group
  carries the play chevron. Long open groups have a sticky head.
- Hover a row to reveal its bookmark. A saved bookmark stays filled and visible.
  The header bookmark filters favourites without flattening the groups.
- Search names/groups (not URLs). Search temporarily flattens; clearing it
  restores the selected grouping and browsed group. The search field always
  shows the **total** number of loaded channels, not a filtered count.
- Scroll away from the current row to try the edge reveal chevron. It never
  clears a search/favourites filter to force a hidden channel into view.
- Row clicks and Prev/Next update the simulated current channel in original
  order. Stop retains the list/current channel. Play resumes the same channel.
- Clear offers five-second Undo. Close only closes the panel; the playlist
  control opens it again. Esc/search focus and Ctrl+L can also be exercised.
- The three marks **outside the player, above it**, select study data:
  mixed metadata, category only, or no grouping metadata. They are study controls,
  not additions to SALU. The control-row `+` reloads the current sample in this
  preview only; it is not a proposed change to SALU's production Open menu.
- The artwork is original fictional station artwork. There are no per-channel
  numbers; an absent logo leaves its fixed slot empty. The landscape is an
  AI-generated still, **not live video**. Sound controls change simulated state.

## Fixtures

| URL query | Data |
|---|---|
| `?sample=mixed` (default) | 48 fictional channels, several absent fields, country/language aliases, some absent logos |
| `?sample=partial` | Categories available; country and language absent and their options dimmed |
| `?sample=missing` | No grouping metadata; Flat works and the other three options stay visible but dim |
| `?sample=large` | 50,000 synthetic entries for DOM-virtualisation checks; not a Dart/mpv benchmark |

A small set of favourites is seeded on the first visit so the visual states are
immediately reviewable. Later edits are saved, debounced, in the browser's
`localStorage` under a fictional provider-host key. Reload keeps these favourites
but recreates the queue in RAM and starts Flat. This **simulates** the approved
production `shared_preferences` favourites store; it does not persist the queue.
The study never calls an outside metadata, logo or stream service.

### Missing-information handling — FINAL with point 5

The `Artisan` sample carries its category in a same-file `#EXTGRP`-equivalent
field rather than `group-title`. This fallback is now approved for production:
nonblank `group-title` wins, otherwise use that entry's `#EXTGRP`; if neither
provides a value, the category remains unknown. An ID such as `horizon.uk` with
no country tag still stays **Unknown**; no country/language or category is
guessed from ambiguous names/IDs and no outside lookup is added.

## What is not being claimed

- No actual M3U network parsing, playback, failure-skip implementation, streaming
  reception detection, or Flutter integration is provided by this study.
- The large sample checks that DOM rows stay proportional to the viewport.
  Browser timings/memory are not production Flutter/Dart/mpv measurements.
- Logo elements exist only near the viewport and use local SVG fixtures. Native
  image caches are browser-managed here; production cache-byte budgets,
  download limits/concurrency and progressive parsing must still be implemented
  and measured in Phase B.
- Icon-only SALU app controls, dark material, 148 px chrome anchor, 322 px panel,
  no panel footer, no per-row drag/delete, and total-only count are preserved.
  The study heading/footer are explicitly outside the simulated application.

## Checks

Pure model tests need only Node 20+:

```sh
node --test design/iptv-channel-preview/model.test.mjs
```

Browser checks need Playwright and Chromium. Keep browser tools **outside Git**;
for example, from the repository root:

```sh
npm install --prefix "$HOME/.cache/salu-preview-tools" --no-package-lock playwright
"$HOME/.cache/salu-preview-tools/node_modules/.bin/playwright" install --with-deps chromium
SALU_PLAYWRIGHT_MODULE="$HOME/.cache/salu-preview-tools/node_modules/playwright/index.mjs" \
  node design/iptv-channel-preview/browser.test.mjs
```

The static server must already be running. Optional environment variables:

- `SALU_PREVIEW_URL`: HTTP base URL for the browser test (default port 8123).
- `SALU_CHROMIUM_EXECUTABLE`: use an already installed Chromium executable.
- `SALU_SCREENSHOT_DIR`: optional output folder for review screenshots; use an
  ignored/cache location, not a tracked generated-artifact directory.

The checks cover Flat-on-load, grouping/unknown/aliases, the bookmark states and
persistence, search/total-only count, keyboard focus/Esc, panel geometry, reveal,
Stop/Next/Undo, missing metadata, no outside requests, and 50,000-row virtualisation.
They are preview tests, **not** SALU's production Phase B acceptance results.
