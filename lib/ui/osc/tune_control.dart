import 'package:flutter/material.dart';

import '../../core/media_utils.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// The Equalizer button (eq_imp.md §1.1) — the control row's right zone,
/// immediately left of the subtitle (Fetch) button.
///
/// One thin custom mark — three sliders — in the family's stroke, so the
/// house recipe applies untouched: grey at rest, white on hover, a faint
/// glow while the panel is open.
///
/// Live on any LOCAL media (a music file needs the audio line as much as a
/// film does). Channels and URLs leave it **greyed out and inert — never
/// hidden** (§12's "safe by design", the same rule the subtitle button
/// follows), and an audio-only file dims the panel's video parts rather
/// than the button.
class TuneControl extends StatelessWidget {
  const TuneControl({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerService player = PlayerService.instance;
    final PanelService panels = PanelService.instance;
    return ValueListenableBuilder<String?>(
      valueListenable: player.currentPath,
      builder: (BuildContext context, String? path, Widget? _) {
        final bool enabled = path != null &&
            !path.contains('://') &&
            !QueueService.instance.isChannelList &&
            MediaUtils.isMedia(path);
        return ValueListenableBuilder<bool>(
          valueListenable: panels.tunePanelOpen,
          builder: (BuildContext context, bool open, Widget? _) {
            return SaluIconButton(
              tooltip: 'Equalizer',
              enabled: enabled,
              active: open,
              onTap: panels.toggleTunePanel,
              child: const EqualizerMark(size: 19),
            );
          },
        );
      },
    );
  }
}
