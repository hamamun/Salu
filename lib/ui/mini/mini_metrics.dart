import 'dart:ui' show Size;

/// The mini bar's measurements (mini.md — FINAL v5).
///
/// Mini keeps the FULL window's group order, its exact marks and its hover
/// recipe; only the SPACE shrinks. The rule of the trim (§11 v5) is
/// *shrink the space, never the glyphs*:
///
/// | | mini | full |
/// |---|---|---|
/// | hit box (w × h) | **26 × 30** | 34 × 34 |
/// | in-group gap | **5** | 6 |
/// | between-groups gap | **11** | 14 |
/// | before the sound group | **20** | 26 |
/// | mark size | **18** | 18–20 |
///
/// Mini's pitch constants are deliberately its own: the cluster's
/// 6 / 14 / 26 are never imported (§9), and the hard floors recorded in
/// §11 v5 stand — no hit below 26 px, no in-group gap below 5 px.
///
/// The row adds up to exactly [windowWidth], which is why the title keeps
/// its full ~141 px:
///
/// ```text
/// 4 ∥ 25 + 8 ∥ 26 5 26 ∥ 11 ∥ 26 5 26 ∥ 11 ∥ 26 5 26 ∥ 20 ∥ 26 5 22
///   ∥ 8 + [title 141] + 4 ∥ 26 + 2 ∥ 4        =  488 px
/// ```
class MiniMetrics {
  MiniMetrics._();

  // ── The window contract (§2) ──────────────────────────────────────────

  /// Fixed width: what the items need, measured once and then locked.
  static const double windowWidth = 488;

  /// 32 px — the Windows caption height (DPI-aware: window sizes here are
  /// logical pixels, so the bar scales with the monitor exactly like a
  /// caption does).
  static const double windowHeight = 32;

  /// `minSize = maxSize` for the whole mini session (§2).
  static const Size windowSize = Size(windowWidth, windowHeight);

  /// Soft 8 px corners, as in `design/mini-bar-preview/index.html`.
  static const double cornerRadius = 8;

  // ── Hits & pitch (§3) ─────────────────────────────────────────────────

  /// One transport hit: 26 × 30 in mini (34 □ in full mode).
  static const double hitWidth = 26;
  static const double hitHeight = 30;
  static const Size hit = Size(hitWidth, hitHeight);

  /// Every transport mark — and the speaker — is drawn at 18 px, the same
  /// `transport_marks.dart` painters full mode uses.
  static const double markSize = 18;

  /// Gap inside a group (between the pair members).
  static const double inGroupGap = 5;

  /// Gap between the three transport groups.
  static const double betweenGroupsGap = 11;

  /// Gap before the sound group.
  static const double beforeSoundGap = 20;

  // ── The row's edges (§11 v5) ──────────────────────────────────────────

  /// Outer padding at both ends of the row.
  static const double outerPadding = 4;

  /// The SALU glyph's slot: a 19 px tile with 3 px of air on each side.
  static const double saluBox = 25;

  /// The tile's own size — identity, and the bar's drag handle (§3).
  static const double saluGlyph = 19;

  /// The gap between the tile and group 1 (11 → 8 in the v5 trim).
  static const double iconGap = 8;

  /// The title's own margins (10 → 8 on the left, 4 on the right).
  static const double titleLeftMargin = 8;
  static const double titleRightMargin = 4;

  /// The whisker between the Restore button and the right padding.
  static const double restoreTrailingGap = 2;

  // ── Group 4 · the volume wheel (§3 · §11 v4) ──────────────────────────

  /// The wheel's slot in the row (the ring itself is [wheelDial] wide).
  static const double wheelBox = 22;

  /// The thin ring dial's own size.
  static const double wheelDial = 20;

  // ── The top-edge meter (§3 "Edge meter") ──────────────────────────────

  /// The 2 px progress line along the top edge.
  static const double seekHeight = 2;

  /// Its own top offset inside the bar.
  static const double seekTop = 2;

  /// Inset from each end, so the line stays inside the rounded corners.
  static const double seekInset = 7;

  /// The invisible hit zone hanging from the top edge (≥ 8 px per §10).
  static const double seekHitHeight = 11;

  /// The head tick, shown while hovering or scrubbing the line.
  static const double seekHeadSize = 6;

  // ── Feedback (§6) ─────────────────────────────────────────────────────

  /// How long the title area stays swapped before it fades back.
  static const Duration swapHold = Duration(milliseconds: 1200);
}
