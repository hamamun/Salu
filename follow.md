# SALU — follow.md (Hard Rules & Design Contract)

> **Purpose:** This file is the binding design contract for SALU. Any AI or
> developer starting a new chat/session MUST read this file first and apply
> these rules to every piece of UI work. These rules were finalized with the
> owner by discussion and are NOT open for silent re-interpretation.

---

## 1. Hard rules (never break these)

1. **No instruction text anywhere.** No hints, no tips, no tutorials, no
   onboarding text, no "you can also…" lines. The UI must explain itself by
   design. (Standard OS-convention tooltips on hover-delay are allowed —
   they name a control, they never teach.)
2. **No keyboard-shortcut labels in any menu/popup.** Shortcuts (Ctrl+O,
   Ctrl+U, Space, …) silently work, but are never printed in the UI.
3. **No confirmation dialogs.** Destructive actions (delete) execute
   instantly and offer a 5-second **Undo** toast instead.
4. **No stock rectangle hover highlight on icons.** No filled boxes, pills
   or circles behind icons. No Material ripple/splash anywhere
   (`NoSplash.splashFactory` is already global).
5. **Container rows never shift.** The timeline is ALWAYS row 1 (top) of the
   controller container. Popups float OVER the video; they never push,
   resize or reflow the container.
6. **Custom SALU icon family, not stock icons, for signature controls.**
   Thin, monochrome, geometric marks drawn in the same stroke language as
   the existing dot-grid settings mark (`DotGridIcon`). Current family:
   - six dots = Settings
   - thin **+** = Open media (rotates 45° to **×** while its menu is open)
   - film frame = Open File · stacked frames = Open Folder · link = Open URL
7. **Colors/typography:** deep dark grays (#121212/#1E1E1E, never pure
   black), Segoe UI Variable only, monochrome icons. All colors come from
   `AppColors` in `lib/theme/app_theme.dart`.
8. **Modal vs panel:** focus tasks (e.g. the Open-URL window) = centered
   glass modal, dimmed barrier, open→act→gone. Live tasks used *while*
   watching (EQ, subtitles, playlist) = slide-out panels. Never mix.

---

## 2. The interaction recipe (applies to EVERY icon control)

**Hover — light + motion, no shapes:**
- Rest state: icon painted `AppColors.iconIdle` (soft gray).
- Hover: color glides to `AppColors.textPrimary` (full white) in ~120 ms,
  and the mark scales up to **1.06**.
- Nothing is drawn behind the icon. Ever.

**Click — a physical press:**
- Pointer down: icon scales down to **0.90** instantly.
- Pointer up: springs back (~120 ms, ease-out). No ripple, no flash.

**Active/toggled state (future toggles like shuffle/repeat):**
- Icon stays full white + a very faint static glow. Glow is reserved for
  active states ONLY — never for hover.

**Bars are the one exception:** flat bars (timeline, volume) keep their own
language — thicken slightly on hover, show the hover chip. *Bars breathe,
icons glow.* Two families, consistent forever.

**Implementation:** `SaluIconButton` (`lib/ui/widgets/salu_icon_button.dart`)
is the single source of this recipe. Every icon control in SALU must use it
(existing controls get retrofitted; new ones are born with it).

---

## 3. Motion language (one animation style for everything)

- Every popup/menu/modal: **fade + slight scale (0.96 → 1.0), ~130–220 ms,
  ease-out cubic.** Menus grow from their anchor direction.
- Esc closes. Click-outside closes. Opening one popup closes others.
- The Open plus mark rotates 45° into × over ~130 ms while its pill is open.

---

## 4. The Open Media control (finalized design)

**Placement:** the very LEFT of the control row, directly below the
timeline. (The rest of the control row — transport, volume, modes — is
designed separately, one item at a time.)

**Level 1 — the pill:** clicking the **+** rotates it to **×** and a small
horizontal frosted-glass pill fades in **below** the button, floating over
the video (downward — the space to the right is reserved for future
controls). Icon-only, three marks side by side:

| mark | action | silent shortcut |
|---|---|---|
| film frame | Open File… → native Windows picker (multi-select) | Ctrl+O |
| stacked frames | Open Folder… → native folder picker, scan & queue | Ctrl+F |
| link | Open URL… → SALU glass modal | Ctrl+U |

Tooltips on hover-delay only. No text rows, no shortcut labels.
(Recent-items area: later phase, silent, no labels.)

**Level 2 — the Open URL modal (glass, centered):**
- ONE input on top. Two actions: **Play** and **Play & Save**. Paste → play
  immediately; saving is optional. Never block playing.
- **Clipboard auto-fill:** on open, if the clipboard holds a URL-looking
  string (`http…`, `.m3u`, `.m3u8`), pre-fill it, fully selected — Enter
  plays instantly.
- **Saved list, max 7.** Row anatomy: `≡ drag-handle · ● status dot · name`,
  and on hover only: 👁 hide · ✎ edit · 🗑 delete (fade in on the right).
- Click a row = plays it. No "select then load".
- **Status dots:** green = last play attempt succeeded, red = last attempt
  failed, gray = never tried / unknown.
- **Hide:** hidden rows fall to the bottom at 40 % opacity. Still clickable.
- **Edit is inline** — the row itself becomes name + URL fields. No second
  dialog.
- **Delete:** instant + 5-second Undo toast inside the modal.
- **Reorder:** drag by the handle (no up/down arrow buttons).
- **7/7 full:** "Play & Save" dims (tooltip states list is full); plain
  Play always works.
- **Keyboard:** Enter = play input/selected row · Esc = close · ↑↓ = walk
  the list. Nothing about this is written in the UI.
- Persistence: `shared_preferences`, JSON list (name, url, hidden, status),
  via `UrlLibraryService` (`lib/core/url_library_service.dart`).

**Chrome interplay:** while the pill or the modal is open, the top chrome
must not auto-hide.

---

## 5. Current container outline (as of this phase)

- **Row 1 — timeline.** Full width, always on top, never moves.
- **Row 2 — control row.** For now the only *finalized* item is the Open
  control at the very left. Existing play/pause + mute + volume remain in
  the center (already retrofitted to the SaluIconButton recipe) until each
  is redesigned in its own step. Future items (transport cluster, shuffle/
  repeat, tracks, panels) are designed ONE AT A TIME in later steps.

---

## 6. Scope decisions on record

- **Web/browser (webview2), bookmarks (15), and the Stream Library panel
  are POSTPONED** — they are not mpv work and will be designed separately.
  The Open control deals only with: file, folder, direct URL (+ saved 7).
- No hardware media key support. Single instance only. Windows 10/11.
- Storage is `shared_preferences` only — no databases.
