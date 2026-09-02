import 'package:flutter/material.dart';

import '../../../core/player_service.dart';
import '../../../theme/app_theme.dart';
import '../../modals/subtitle_search_modal.dart';

/// The Subtitle tab (Phase 4 · Step 5): search & load subtitles, and
/// position / sync adjustments.
class SubtitleTab extends StatefulWidget {
  const SubtitleTab({super.key});

  @override
  State<SubtitleTab> createState() => _SubtitleTabState();
}

class _SubtitleTabState extends State<SubtitleTab> {
  final PlayerService _player = PlayerService.instance;

  double _position = 100; // mpv default: subtitles at the bottom.
  double _delay = 0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        FilledButton.icon(
          onPressed: () => SubtitleSearchModal.show(context),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('Search & Load Subtitles'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _player.disableSubtitles(),
          icon: const Icon(Icons.subtitles_off_outlined, size: 16),
          label: const Text('Disable subtitles'),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        _SectionLabel('Vertical position', trailing: '${_position.round()}%'),
        Center(
          child: SizedBox(
            height: 150,
            child: RotatedBox(
              // 90° so the slider's top maps to sub-pos 0 (top of screen).
              quarterTurns: 1,
              child: Slider(
                value: _position.clamp(0.0, 100.0).toDouble(),
                min: 0,
                max: 100,
                onChanged: (double v) => setState(() => _position = v),
                onChangeEnd: (double v) => _player.setSubtitlePosition(v),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SectionLabel('Subtitle delay / sync', trailing: '${_delay.toStringAsFixed(1)} s'),
        Slider(
          value: _delay.clamp(-5.0, 5.0).toDouble(),
          min: -5,
          max: 5,
          divisions: 100,
          onChanged: (double v) => setState(() => _delay = v),
          onChangeEnd: (double v) => _player.setSubtitleDelay(v),
        ),
        const SizedBox(height: 16),
        const Text(
          'Subtitle position slides the text up and down the screen; '
          'delay fixes subtitles that appear too early or too late.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
