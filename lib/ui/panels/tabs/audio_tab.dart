import 'package:flutter/material.dart';

import '../../../core/audio_presets.dart';
import '../../../core/player_service.dart';
import '../../../theme/app_theme.dart';

/// The Audio tab (Phase 4 · Step 4): volume boost, audio sync, and a
/// 10-band graphic equalizer with dynamic presets.
class AudioTab extends StatefulWidget {
  const AudioTab({super.key});

  @override
  State<AudioTab> createState() => _AudioTabState();
}

class _AudioTabState extends State<AudioTab> {
  final PlayerService _player = PlayerService.instance;

  final List<double> _gains = List<double>.filled(10, 0);
  String _presetName = 'Flat';
  double _audioDelay = 0;

  @override
  void initState() {
    super.initState();
    // The preset library swaps between the music and video lists when the
    // file type changes; keep the selected value valid for the active list.
    _player.isMusicMode.addListener(_onModeChanged);
  }

  @override
  void dispose() {
    _player.isMusicMode.removeListener(_onModeChanged);
    super.dispose();
  }

  void _onModeChanged() {
    if (!mounted) return;
    final List<EqualizerPreset> presets = _player.isMusicMode.value
        ? EqualizerPresets.audio
        : EqualizerPresets.video;
    if (!presets.any((EqualizerPreset p) => p.name == _presetName)) {
      _resetEq();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        ValueListenableBuilder<double>(
          valueListenable: _player.volumeBoost,
          builder: (BuildContext context, double boost, Widget? _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SectionLabel('Volume boost', trailing: '+${boost.round()}%'),
                Slider(
                  value: boost.clamp(0.0, 100.0).toDouble(),
                  min: 0,
                  max: 100,
                  onChanged: (double v) => _player.setVolumeBoost(v),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _SectionLabel('Audio delay / sync', trailing: '${_audioDelay.toStringAsFixed(1)} s'),
        Slider(
          value: _audioDelay.clamp(-5.0, 5.0).toDouble(),
          min: -5,
          max: 5,
          divisions: 100,
          onChanged: (double v) => setState(() => _audioDelay = v),
          onChangeEnd: (double v) => _player.setAudioDelay(v),
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            const Expanded(child: _SectionLabel('Equalizer')),
            ValueListenableBuilder<bool>(
              valueListenable: _player.isMusicMode,
              builder: (BuildContext context, bool music, Widget? _) {
                return _PresetDropdown(
                  presets: music
                      ? EqualizerPresets.audio
                      : EqualizerPresets.video,
                  value: _presetName,
                  onChanged: _applyPreset,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < 10; i++)
                _BandSlider(
                  index: i,
                  gains: _gains,
                  onChanged: _onBandChanged,
                  onApply: _applyEq,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: _resetEq,
              icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.textSecondary),
              label: const Text('Reset', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
            const Spacer(),
            Text(
              _presetName,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  void _onBandChanged(int index, double value) {
    setState(() {
      _gains[index] = value;
      _presetName = 'Custom';
    });
  }

  void _applyEq() => _player.setEqualizer(_gains);

  void _applyPreset(String name) {
    final bool music = _player.isMusicMode.value;
    final List<EqualizerPreset> presets =
        music ? EqualizerPresets.audio : EqualizerPresets.video;
    final EqualizerPreset preset = presets.firstWhere(
      (EqualizerPreset p) => p.name == name,
      orElse: () => const EqualizerPreset('Flat', EqualizerPresets.flat),
    );
    setState(() {
      _presetName = preset.name;
      for (int i = 0; i < 10; i++) {
        _gains[i] = preset.gains[i];
      }
    });
    _player.setEqualizer(_gains);
  }

  void _resetEq() {
    setState(() {
      _presetName = 'Flat';
      for (int i = 0; i < 10; i++) {
        _gains[i] = 0;
      }
    });
    _player.setEqualizer(_gains);
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.index,
    required this.gains,
    required this.onChanged,
    required this.onApply,
  });

  final int index;
  final List<double> gains;
  final void Function(int index, double value) onChanged;
  final VoidCallback onApply;

  static const List<String> _labels = <String>[
    '31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 96,
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: gains[index].clamp(-12.0, 12.0).toDouble(),
                min: -12,
                max: 12,
                onChanged: (double v) => onChanged(index, v),
                onChangeEnd: (double v) => onApply(),
              ),
            ),
          ),
          Text(
            _labels[index],
            style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PresetDropdown extends StatelessWidget {
  const _PresetDropdown({
    required this.presets,
    required this.value,
    required this.onChanged,
  });

  final List<EqualizerPreset> presets;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      dropdownColor: AppColors.surface,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      items: presets
          .map((EqualizerPreset p) =>
              DropdownMenuItem<String>(value: p.name, child: Text(p.name)))
          .toList(),
      onChanged: (String? v) {
        if (v != null) onChanged(v);
      },
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
