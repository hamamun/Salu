import 'package:flutter/material.dart';

import '../widgets/custom_title_bar.dart';
import 'fetch_control.dart';
import 'fullscreen_control.dart';
import 'media_timeline.dart';
import 'open_media_control.dart';
import 'playlist_control.dart';
import 'transport_cluster.dart';
import 'tune_control.dart';

/// SALU's on-screen controller container.
///
/// Designed to sit directly beneath the top title bar and read as the
/// same single window: it paints no background, border or shadow of its
/// own — the fused parent block (HomeScreen's top chrome) supplies one
/// continuous scrim behind both, edge to edge.
///
/// Layout, top to bottom (follow.md · §5 — rows never shift):
///   · Row 1 — the unified media timeline (identical for video and audio)
///   · Row 2 — the control row: the Open Media control at the very left,
///     the transport cluster + sound group
///     (`> □ |<< >>| << >> ⊂)) [bar]` — see [TransportCluster] — centered
///     in the space between the two end zones, and the tune / fetch /
///     fullscreen trio at the very right.
///
/// Row 2 is a plain Row, not a Stack: the end zones keep their natural
/// widths and the center zone takes exactly what is left between them, so
/// no control ever covers another at any window width. When that space is
/// narrower than the cluster (snap mode lowers the window floor to
/// 320 × 180), the `FittedBox` scales the whole cluster down as one piece
/// instead of pushing the Row into a RenderFlex overflow — the marks
/// shrink proportionally, nothing is ever clipped.
///
/// The row below the timeline keeps a fixed height: hover popups from
/// the timeline float OVER it, nothing is ever pushed or shifted.
class ControllerPanel extends StatelessWidget {
  const ControllerPanel({super.key});

  /// Total fixed height of the panel (timeline + controls + padding).
  /// Public — `kChromeBlockHeight` (HomeScreen / OSD anchor) is
  /// computed from it so the two can never drift.
  static const double height = 108;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(18, 4, 18, 12);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: _padding,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Row 1 · the timeline (bar + floating hover chip in its box).
          MediaTimeline(),
          // Row 2 · the control row (fixed height, never pushed). A Row,
          // not a Stack: the end zones keep their natural widths and the
          // center zone takes exactly what is left between them.
          SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Row(
              children: <Widget>[
                // Left zone · the Open Media control (+ → pill) then the
                // Playlist control, 6 px apart — the sibling pair of the
                // row's left edge (playlist_imp.md §1.1).
                OpenMediaControl(),
                SizedBox(width: 6), // §1.1 — set 2 to fuse them
                PlaylistControl(),
                // Center zone · the transport cluster + sound group,
                // centered in the space left between the end zones. When
                // that space is narrower than the cluster (snap-mode
                // windows go down to 320 px), the FittedBox scales the
                // whole cluster down as one piece — it measures the row
                // at its natural width first, so a narrow window shrinks
                // the marks proportionally instead of pushing the Row
                // into a RenderFlex overflow.
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: TransportCluster(),
                  ),
                ),
                // Right zone · the Equalizer button (eq_imp.md §1.1 — the
                // tune-family mark, greyed-inert on live media, NEVER
                // hidden) immediately left of the Fetch button (cc.md
                // §6/D14 — a caption-family mark, same rule), then
                // fullscreen at the outermost edge.
                TuneControl(),
                SizedBox(width: 6),
                FetchControl(),
                SizedBox(width: 6),
                FullscreenControl(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Exposed so the OSD deck anchor never drifts from the real block.
const double kChromeBlockHeight =
    CustomTitleBar.height + ControllerPanel.height;
