import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/settings_service.dart';
import '../../theme/app_theme.dart';
import 'dot_grid_icon.dart';

/// SALU's settings window — a centered, SALU-styled dialog over a dimmed
/// backdrop, opened by the 6-dot button in the title bar.
///
/// Current tabs: General. The tab strip is structured so later phases'
/// Video / Audio / Subtitles tabs can slot right in.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

enum _SettingsTab { general }

class _SettingsDialogState extends State<SettingsDialog> {
  _SettingsTab _tab = _SettingsTab.general;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
      backgroundColor: Colors.transparent,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = math.min(640.0, constraints.maxWidth);
          final double height = math.min(540.0, constraints.maxHeight);
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF333336)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 48,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                _buildHeader(),
                _buildTabStrip(),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                Expanded(child: _buildBody()),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
      child: Row(
        children: <Widget>[
          const DotGridIcon(size: 20, color: AppColors.textPrimary),
          const SizedBox(width: 12),
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          _HoverIconButton(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: <Widget>[
          _TabButton(
            label: 'General',
            selected: _tab == _SettingsTab.general,
            onTap: () => setState(() => _tab = _SettingsTab.general),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_tab) {
      _SettingsTab.general => const _GeneralTab(),
    };
  }
}

// ── General tab ─────────────────────────────────────────────────────────────

class _GeneralTab extends StatelessWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context) {
    // The whole General tab is static, so build it once at compile time.
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Controls',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Choose when the top bar hides itself.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _TitleBarModePicker(),
          SizedBox(height: 28),
          Text(
            'Resume',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Which files continue from where you stopped.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _ResumeModePicker(),
        ],
      ),
    );
  }
}

/// The "Controls" section — one of three title bar modes, radio style.
class _TitleBarModePicker extends StatelessWidget {
  const _TitleBarModePicker();

  static const List<_ModeOption> _options = <_ModeOption>[
    _ModeOption(
      mode: TitleBarMode.borderless,
      icon: Icons.fullscreen,
      label: 'Borderless',
      helper: 'Hides 3s after inactivity — even when idle.',
      isDefault: true,
    ),
    _ModeOption(
      mode: TitleBarMode.pinWhenPlaybackOff,
      icon: Icons.push_pin_outlined,
      label: 'Pin (playback off)',
      helper: 'Stays pinned while nothing is playing; hides during playback.',
    ),
    _ModeOption(
      mode: TitleBarMode.locked,
      icon: Icons.lock_outline,
      label: 'Locked',
      helper: 'Always visible, never hides.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TitleBarMode>(
      valueListenable: SettingsService.instance.titleBarMode,
      builder: (BuildContext context, TitleBarMode mode, Widget? _) {
        return Column(
          children: <Widget>[
            for (final _ModeOption option in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OptionTile(
                  icon: option.icon,
                  label: option.label,
                  helper: option.helper,
                  isDefault: option.isDefault,
                  selected: mode == option.mode,
                  onTap: () => SettingsService.instance
                      .setTitleBarMode(option.mode),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The "Resume" section — which files continue from where you stopped.
/// Switching to Off stops saving AND resuming but never wipes stored
/// positions (switching back restores the memory).
class _ResumeModePicker extends StatelessWidget {
  const _ResumeModePicker();

  static const List<_ResumeOption> _options = <_ResumeOption>[
    _ResumeOption(
      mode: ResumeMode.all,
      icon: Icons.all_inclusive_outlined,
      label: 'All files',
      helper: 'Video and audio pick up where they stopped.',
      isDefault: true,
    ),
    _ResumeOption(
      mode: ResumeMode.videoOnly,
      icon: Icons.movie_outlined,
      label: 'Video only',
      helper: 'Video resumes; audio starts from the beginning.',
    ),
    _ResumeOption(
      mode: ResumeMode.audioOnly,
      icon: Icons.audiotrack_outlined,
      label: 'Audio only',
      helper: 'Audio resumes; video starts from the beginning.',
    ),
    _ResumeOption(
      mode: ResumeMode.off,
      icon: Icons.block_outlined,
      label: 'Off',
      helper: 'Everything starts from the beginning.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ResumeMode>(
      valueListenable: SettingsService.instance.resumeMode,
      builder: (BuildContext context, ResumeMode mode, Widget? _) {
        return Column(
          children: <Widget>[
            for (final _ResumeOption option in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OptionTile(
                  icon: option.icon,
                  label: option.label,
                  helper: option.helper,
                  isDefault: option.isDefault,
                  selected: mode == option.mode,
                  onTap: () => SettingsService.instance
                      .setResumeMode(option.mode),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ModeOption {
  const _ModeOption({
    required this.mode,
    required this.icon,
    required this.label,
    required this.helper,
    this.isDefault = false,
  });

  final TitleBarMode mode;
  final IconData icon;
  final String label;
  final String helper;
  final bool isDefault;
}

class _ResumeOption {
  const _ResumeOption({
    required this.mode,
    required this.icon,
    required this.label,
    required this.helper,
    this.isDefault = false,
  });

  final ResumeMode mode;
  final IconData icon;
  final String label;
  final String helper;
  final bool isDefault;
}

/// A single option row, shared by every picker: icon chip + label
/// (+ "Recommended" pill) + helper line + radio dot. Clicking applies
/// instantly.
class _OptionTile extends StatefulWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.helper,
    required this.selected,
    required this.onTap,
    this.isDefault = false,
  });

  final IconData icon;
  final String label;
  final String helper;
  final bool isDefault;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0x144C9EEB)
                : (_hovered ? const Color(0x14FFFFFF) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0x404C9EEB) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0x264C9EEB)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            widget.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (widget.isDefault) ...<Widget>[
                          const SizedBox(width: 8),
                          const _RecommendedPill(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.helper,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _RadioDot(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "Recommended" tag next to the default option.
class _RecommendedPill extends StatelessWidget {
  const _RecommendedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0x1F4C9EEB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Recommended',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// SALU's radio indicator — a thin ring that fills with the accent when
/// selected (animated).
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          width: selected ? 4.5 : 1.5,
          color: selected ? AppColors.accent : const Color(0xFF7A7A7A),
        ),
      ),
    );
  }
}

// ── Shared dialog building blocks ───────────────────────────────────────────

/// A tab in the settings tab strip (label + animated accent underline).
class _TabButton extends StatelessWidget {
  const _TabButton({
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: selected ? 44 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small square icon button with a soft hover wash (dialog close, …).
class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color:
                  _hovered ? AppColors.surfaceHighlight : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovered ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
