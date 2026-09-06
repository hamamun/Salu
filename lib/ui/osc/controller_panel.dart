import 'package:flutter/material.dart';

import '../widgets/custom_title_bar.dart';
import 'media_timeline.dart';
import 'open_media_control.dart';
import 'playlist_control.dart';
import 'transport_cluster.dart';

/// SALU's on-screen controller container.
///
/// Designed to sit directly beneath the top title bar and read as the
/// same single window: it paints no background, border or shadow of its
/// own — the fused parent block (HomeScreen's top chrome) supplies one
/// continuous scrim behind both, edge to edge.
///
/// Layout, top to bottom (follow.md · §5 — rows never shift):
///   · Row 1 — the unified media timeline (identical for video and audio)
///   · Row 2 — the control row: the Open Media control at the very left
///     and, centered, the transport cluster + sound group
///     (`> □ |<< >>| << >> ⊂)) [bar]` — see [TransportCluster].
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
          // Row 2 · the control row (fixed height, never pushed).
          SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Left zone · the Open Media control (plus → pill) and,
                // 6 px right of it (in-group pitch — playlist_imp.md §1.1),
                // the Playlist control (Now Row mark → slide-out panel).
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      OpenMediaControl(),
                      SizedBox(width: 6), // §1.1 — set to 2 to fuse them
                      PlaylistControl(),
                    ],
                  ),
                ),
                // Center zone · the transport cluster + sound group.
                // The row's right edge stays free for the future
                // tracks / PiP / fullscreen / panel toggles.
                Center(child: TransportCluster()),
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
