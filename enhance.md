# SALU Personalisation Enhancements

Decisions agreed for future implementation. This document records the intended behavior; it does not implement the features.

## 1. Theme

Add a theme preference with three options:

- **Default** — SALU's current appearance. This remains the default for existing and new users.
- **Light** — a complete light appearance, including text, controls, panels, menus, and dialogs; not just a light canvas.
- **System** — follow the Windows light/dark appearance and respond when the system preference changes.

The selected option is saved and restored on the next launch. “Default” means the existing SALU appearance, not the Windows system preference.

## 2. Media controller placement

Add a controller placement preference:

- **Default** — preserve the current placement, directly beneath/attached to the title bar.
- **Top** — show the controller detached from the title bar, near the top of the window.
- **Bottom** — show the controller near the bottom, with a gap from the bottom edge.
- **Bottom edge** — show the controller aligned with the bottom edge.

The placement is saved and restored on the next launch. “Top” must be visually distinct from Default: it is a separate floating controller near the top, rather than the current title-bar-attached block.

### Panel and message placement rules

- The playlist remains on the right side of the window. Its available height and vertical position adapt so it does not overlap the controller or title bar where avoidable.
- Track/subtitle and equalizer panels continue to open from the controller side: downward for top placements and upward for bottom placements.
- Toasts and playback messages are positioned so they are not obscured by the controller. For bottom placements, use a clear area higher on the screen or near the center.
- Panels remain overlays; moving the controller must not resize or move the video.
- Placement changes must be applied consistently to hover popups and other controls anchored to the controller.

## 3. Overlay transparency

Add a saved **Overlay transparency** preference that changes the transparency of SALU-owned interface surfaces, including the controller background, playlist, track/subtitle and equalizer panels, in-app popups, and toasts.

- The current appearance is the default setting, preserving today's look.
- The user can adjust the transparency as a percentage (for example, 80%). The exact range and slider increments should be finalized during implementation and tested for readability.
- Adjust surface backgrounds only. Text, icons, and interactive marks remain fully opaque and readable.
- Existing blur can remain; transparency controls the surface tint/opacity and is not the same as blur strength.
- The setting applies to SALU's in-app interface, not the entire native window or Windows-owned dialogs.
- Apply the setting consistently wherever practical. If a surface cannot support the preference without harming usability, document that exception rather than silently behaving differently.

## 4. Settings organization and SALU presentation rules

Place these preferences together in a new **Appearance** tab in Settings:

1. **Theme**: Default / Light / System
2. **Media controller placement**: Default / Top / Bottom / Bottom edge
3. **Overlay transparency**: percentage slider, with the selected percentage visible on the control

This keeps visual and layout choices together, avoids overcrowding General, and leaves room for future appearance preferences. The existing General tab remains for general and playback behavior.

Follow SALU's established presentation style:

- Do not add explanatory guidance, instructional paragraphs, onboarding, or help text for these options.
- Use SALU-style icons/marks for the choices and controls, with clear, proper labels and tooltips. Tooltips identify what each option does; they are not shortcut displays.
- Keep labels concise and consistent with existing SALU settings. Do not rely on icons alone where a label or tooltip is needed to make a choice understandable.
- Apply changes immediately and persist them without requiring an app restart, unless implementation reveals a concrete platform constraint.

## 5. Keyboard shortcuts

- Do not assign keyboard shortcuts to these appearance settings.
- Do not add shortcut entries for them to `shortcut.md`, the shortcut registry, or the Settings → Shortcuts tab.
- Do not add Alt-Peek behavior for these settings. Existing shortcuts and Alt-Peek behavior remain unchanged.

## 6. Implementation and verification notes

- Preserve Default behavior and appearance so current users are not surprised.
- Store all three preferences in the existing settings persistence system.
- Test each controller placement with playlist, track/subtitle, equalizer, hover, OSD, and toast surfaces open, in windowed and fullscreen modes.
- Test light theme for readable contrast across the whole app, not only the main player.
- Test transparency at low, middle, and high values over both bright and dark video; ensure controls remain legible and clickable.
- Confirm System theme responds to Windows appearance changes and that manual Default/Light choices do not get overridden.
- Keep Settings free of instructional copy; verify icons, labels, and tooltips are clear and consistent with SALU style.

## 7. Implementation phases and forecast

Implement in the agreed phases:

### Phase 1 — Theme

- Add persisted **Default / Light / System** theme preference with migration-safe default behavior.
- Add the Appearance tab and its theme control using SALU's existing icon/mark, label, tooltip, and control patterns.
- Introduce light and system-aware theme data and move shared colors into theme-aware tokens. Audit fixed-color surfaces in player, panels, settings, browser chrome, and transient overlays. The current theme is dark-only and many widgets use fixed `AppColors` or literal colors; changing only `ThemeData` would leave parts of Light mode dark or unreadable.
- Verify that System follows Windows appearance changes, and assess WebView2 separately because page colors are controlled independently from SALU's own chrome.

### Phase 2 — Transparency

- Add a persisted **Overlay transparency** control to Appearance settings. Changes apply live and preserve the current appearance by default.
- Route eligible SALU surface backgrounds through a shared appearance value while keeping text, icons, and interactive marks fully opaque.
- Audit glass, gradients, popup/deck cards, playlist, track/tune panels, and chrome scrims. Test over both bright and dark video and check blur/animation performance on Windows.
- The control must be clear that 0% means the current/default solidness and higher values mean more see-through. “80% transparency” means 80% see-through, not 80% opaque. Select the maximum during visual testing to protect readability.
- Do not claim every surface is covered until the audit verifies it. Record any intentionally excluded surface.

### Phase 3 — Controller position

- Add a persisted **Default / Top / Bottom / Bottom edge** controller placement preference to Appearance settings. Changes apply live; Default preserves current behavior.
- Make controller position a shared layout value rather than relying on the current fixed top-chrome height. Update title chrome, panel anchors, playlist bounds, hover surfaces, OSD/toast anchors, and auto-hide/hover handling together.
- Keep playlist on the right and bound it to available space. Panels should fit and scroll internally where needed, without covering active controller controls.
- Test windowed, maximized, fullscreen, and mini-mode transitions. Verify bottom and bottom-edge spacing remains consistent at different window sizes.

### Verification across all phases

Add settings persistence/widget tests and targeted theme, transparency, and layout tests. Run the full existing suite, perform a Windows build, and visually check each phase before moving to the next.

Known constraints and risks:

- Theme work has wide reach because colors are explicitly specified in many widgets; a partial conversion would produce a mixed theme. SALU's custom marks and painted/gradient surfaces may need explicit light variants.
- The controller currently belongs to a fused title-bar/controller top block. Its OSD and panels use fixed top offsets. Bottom placement therefore needs a coordinated shared anchor/layout refactor to avoid panels appearing at old locations or colliding with the title bar.
- Playlist, track, and equalizer panels have different sizes and interaction rules. On short windows or when the controller sits at the bottom, the available panel area may be too small. Panels should be bounded to available space and scroll internally; avoid covering the controller's active controls.
- “Bottom” means a gap above the bottom edge; “Bottom edge” touches the bottom edge. The exact gap should match SALU spacing and be consistent across window sizes.
- A theme or transparency preference cannot reliably restyle Windows-owned file pickers/dialogs or the video itself. Web content's own colors are controlled separately from SALU chrome.
- High transparency reduces contrast over some video scenes. Keep labels/icons opaque, retain a sensible limit, and verify actual worst-case readability rather than assuming blur alone solves it.
- For the transparency control, use the word **Transparency** and make its direction unambiguous: 0% means the current/default solidness; a higher value means more see-through. The exact maximum should be selected during visual testing. Thus “80% transparency” means 80% see-through, not 80% opaque.
- Do not claim every surface is covered until the audit verifies it. If a surface is intentionally excluded, record that exception.

No keyboard shortcuts or Alt-Peek additions are part of this work; the existing shortcut inventory and Shortcuts tab remain unchanged.

## Phase 1 implementation / validation status

Theme selection, first-frame restoration, live System selection, Appearance
icon choices, resets/Undo, Material themes, context-based chrome palettes and
palette-aware custom painters are implemented. Browser page colours remain
independent. Video letterboxing, QR content and operating-system dialogs are
not recoloured as application chrome. Shortcuts-tab code and the shortcut
registry remain unchanged; its illustrated reference views retain their
original colours.

Validation in the agent workspace: Dart sources parsed/formatted using the
WASM port of dart_style; `git diff --check` passes. Flutter analysis, widget
tests and Windows visual/runtime checks are **not yet run**: the workspace
has no working Flutter/Dart SDK and SDK downloads are blocked. Added
`test/theme_test.dart` covers persistence, first frame, live System brightness,
page-scheme independence, palette contrast, painter invalidation and reset/Undo.
Run `flutter analyze` and `flutter test` on an SDK-equipped machine, then check
open dialogs/panels over bright and dark video on Windows before sign-off.
Phase 2 is implemented (Windows validation pending); Phase 3 is not implemented.

## Phase 2 implementation / validation status

Overlay transparency is implemented as a saved 0–40% setting in Appearance.
The slider changes tint live in 5% steps; release commits the value. Zero
leaves the original colours and alpha values untouched. The percentage is the
**fraction of the existing tint removed**, not the opacity retained: at 40%,
a previously 80%-opaque glass tint is 48%-opaque. The 40% ceiling is
conservative pending Windows contrast testing; do not raise it without checking
light/dark chrome over bright/dark moving video. Reset and master Undo restore
both the UI and the saved value.

Audited SALU-owned floating surface backgrounds: fused player chrome gradient,
standalone title chrome, mini bar, glass controller pills/deck/toasts, hover
chips, playlist/track/tune/info panels, settings and subtitle dialogs,
Open URL/remote/update/firewall dialogs, and Flutter browser menus, shelves,
popups and tooltips. The same tint function preserves each surface's colour
and adjusts only its background alpha. Foreground text, marks, strokes, hover
feedback, focus indicators and shadows are left unchanged. Blur strength
is unchanged. Intentional exclusions: the opaque video/letterbox and browser
canvas, Flutter browser start page, lyric canvas, WebView2 page content, Windows
owned dialogs, modal dim barriers, QR/images/artwork, the mini bar's 2 px edge
meter, editable form-field fills, interactive tabs/selected pills, and shortcut
reference illustrations. These are not floating interface surface tints;
reducing their opacity would expose unrelated layers or reduce usability.

The **media seek bar** (`ui/osc/media_timeline.dart`) and the **volume bar**
(`ui/osc/volume_bar.dart`, including its read-only copy in the OSD volume
card) were originally excluded here as "media progress tracks". They are now
tinted like every other surface: the track and the progress fill run through
the same `overlayTint` function. Only the surface parts fade — the timeline's
playhead notch, ruler ticks and in-bar time readouts, and the volume bar's
in-bar percent label, stay fully opaque so the position and level remain
readable over bright video. The volume bar tints the FINAL colour, after its
hover highlight is blended in, so the brightened state simply sits on a
proportionally more see-through bar. Still excluded in the same family: the
subtitle-delay bar in the track panel and the mini bar's edge meter, which
remain at the original opacity unless reported.

Added `test/overlay_transparency_test.dart` for persistence, migration/clamp,
live changes, tint/foreground isolation, the seek/volume bar surfaces and
reset/Undo. All 30 changed Dart sources parse with the WASM dart_style
formatter; `git diff --check` passes.
Flutter analysis/tests and Windows visual/blur-performance checks are
**not yet run** in this workspace (no Flutter/Dart SDK). Verify the new
setting over bright and dark moving video in both themes, fullscreen/windowed
and mini modes, including all listed panels and dialogs, on Windows before
sign-off. Phase 3 remains unimplemented.

## Phase 3 implementation / validation status

Controller placement is now persisted in `SettingsService` as
`appearance_controller_placement`, with a migration-safe `Default` fallback.
The Appearance tab has a four-choice, icon-and-label placement picker and a
group reset/Undo path. Placement applies live. Default retains the fused
148 px title/controller block; Top keeps the title bar at the top and places
the controller below it with a visible gap; Bottom floats the controller 24 px
above the lower edge; Bottom edge aligns it flush to that edge. The bottom
controller animates upward as it appears, while top/default continue to enter
from above. Controller placements trigger recreation/re-anchoring of the
playlist, track, tune, info and OSD surfaces. Playlist remains right-aligned;
its bottom-placement bounds stop above the controller. Track and tune panels
open upward for bottom placements, and the info panel is similarly bounded.
The OSD deck moves to a clear upper-middle position for bottom placement.

Added `test/controller_placement_test.dart` for the migration default, invalid
stored values, and persistence of every enum choice. `git diff --check` passes.
Flutter analysis, widget tests, and Windows visual/runtime checks are still
pending because this workspace has no working Flutter/Dart SDK. In particular,
verify short-window panel scrolling, hover popups, fullscreen/maximized and
mini-mode transitions, toast placement, and the 24 px bottom gap on Windows
before sign-off. Mini mode remains its existing dedicated mini bar and does
not adopt these full-player placements.
