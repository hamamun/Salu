import 'package:flutter/material.dart';

import '../../../core/player_service.dart';
import '../../../theme/app_theme.dart';

/// The Video tab (Phase 4 · Step 3): rotation, flip, and aspect ratio.
class VideoTab extends StatefulWidget {
  const VideoTab({super.key});

  @override
  State<VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<VideoTab> {
  final PlayerService _player = PlayerService.instance;

  int _rotation = 0;
  bool _hflip = false;
  bool _vflip = false;
  String _aspect = 'Auto';

  @override
  void initState() {
    super.initState();
    _loadInitialRotation();
  }

  Future<void> _loadInitialRotation() async {
    final String? value = await _player.getMpvProperty('video-rotate');
    final int rotation = int.tryParse(value ?? '') ?? 0;
    if (mounted) setState(() => _rotation = rotation);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const _SectionLabel('Rotation'),
        Row(
          children: <Widget>[
            for (final int deg in const <int>[0, 90, 180, 270])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _OptionChip(
                    label: deg == 0 ? '0°' : '$deg°',
                    selected: _rotation == deg,
                    onTap: () => _setRotation(deg),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionLabel('Flip'),
        _ToggleRow(
          label: 'Flip horizontally',
          value: _hflip,
          onChanged: (bool v) {
            setState(() => _hflip = v);
            _player.setHorizontalFlip(v);
          },
        ),
        _ToggleRow(
          label: 'Flip vertically',
          value: _vflip,
          onChanged: (bool v) {
            setState(() => _vflip = v);
            _player.setVerticalFlip(v);
          },
        ),
        const SizedBox(height: 22),
        const _SectionLabel('Aspect ratio'),
        DropdownButtonFormField<String>(
          value: _aspect,
          dropdownColor: AppColors.surface,
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.divider),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.accent),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
          items: const <String>['Auto', '16:9', '4:3', '21:9', '1:1']
              .map((String v) => DropdownMenuItem<String>(value: v, child: Text(v)))
              .toList(),
          onChanged: (String? value) {
            if (value == null) return;
            setState(() => _aspect = value);
            _player.setAspectOverride(value == 'Auto' ? null : value);
          },
        ),
      ],
    );
  }

  void _setRotation(int deg) {
    setState(() => _rotation = deg);
    _player.setVideoRotation(deg);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceHighlight : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? AppColors.accent : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
      ),
      value: value,
      activeColor: AppColors.accent,
      onChanged: onChanged,
    );
  }
}
