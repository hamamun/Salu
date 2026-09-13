import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/language_names.dart';
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

enum _SettingsTab { general, subtitles }

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
          // cc.md §2 — the Subtitles tab (D1…D5, D13).
          _TabButton(
            label: 'Subtitles',
            selected: _tab == _SettingsTab.subtitles,
            onTap: () => setState(() => _tab = _SettingsTab.subtitles),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_tab) {
      _SettingsTab.general => const _GeneralTab(),
      _SettingsTab.subtitles => const _SubtitlesTab(),
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
          SizedBox(height: 28),
          Text(
            'Folder auto-load',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'What loads when a single file is opened.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _FolderAutoloadPicker(),
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

/// The "Folder auto-load" section (autoload_imp.md §5) — what happens
/// when exactly one local media file is loaded. Applies from the next
/// load; the live queue is never retrofitted.
class _FolderAutoloadPicker extends StatelessWidget {
  const _FolderAutoloadPicker();

  static const List<_FolderAutoloadOption> _options =
      <_FolderAutoloadOption>[
    _FolderAutoloadOption(
      mode: FolderAutoloadMode.allVideos,
      icon: Icons.video_library_outlined,
      label: 'All videos in folder',
      helper: 'The whole folder is queued, starting at the file you opened.',
      isDefault: true,
    ),
    _FolderAutoloadOption(
      mode: FolderAutoloadMode.sameSeries,
      icon: Icons.movie_filter_outlined,
      label: 'Same series only',
      helper: 'Only files named like the picked one — never the whole folder.',
    ),
    _FolderAutoloadOption(
      mode: FolderAutoloadMode.off,
      icon: Icons.block_outlined,
      label: 'Off',
      helper: 'Only the picked file is loaded.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FolderAutoloadMode>(
      valueListenable: SettingsService.instance.folderAutoloadMode,
      builder:
          (BuildContext context, FolderAutoloadMode mode, Widget? _) {
        return Column(
          children: <Widget>[
            for (final _FolderAutoloadOption option in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OptionTile(
                  icon: option.icon,
                  label: option.label,
                  helper: option.helper,
                  isDefault: option.isDefault,
                  selected: mode == option.mode,
                  onTap: () => SettingsService.instance
                      .setFolderAutoloadMode(option.mode),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Subtitles tab (cc.md §2 · D2 · D5 · D13) ─────────────────────────

/// Three sections: **OpenSubtitles** (API key with eye + clear; the
/// username + password pair — all three persisted, the password scrambled
/// per D13 amended 2026-09-13), **Language** (the preferred-language
/// dropdown — label + current value + chevron), **Auto-download** (a
/// switch row in the same tile styling).
class _SubtitlesTab extends StatelessWidget {
  const _SubtitlesTab();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // §2.1 — account + search fields.
          Text(
            'OpenSubtitles',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Where the subtitles come from.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _CredentialFields(),
          SizedBox(height: 28),
          // §2.2 — the preferred language (single selector).
          Text(
            'Language',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'The fallback stays English.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _LanguageSelector(),
          SizedBox(height: 28),
          // §2.3 — the auto-download toggle.
          Text(
            'Auto-download',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Fetching for videos that have no subtitles yet.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _AutoDownloadSwitch(),
        ],
      ),
    );
  }
}

/// API key (obscured by default + eye toggle + trailing ×) and the
/// username / password pair (§2.1). All three persist their changes the
/// moment they happen — no save button anywhere in the app. The password
/// is stored scrambled rather than as text (D13 AMENDED, owner
/// 2026-09-13 — `SettingsService.setSubtitlePassword`); the original
/// memory-only rule left `/download` dead after every restart, because it
/// needs a Bearer token that only `/login` can mint (cc.md §4).
class _CredentialFields extends StatefulWidget {
  const _CredentialFields();

  @override
  State<_CredentialFields> createState() => _CredentialFieldsState();
}

class _CredentialFieldsState extends State<_CredentialFields> {
  late final TextEditingController _apiKey;
  late final TextEditingController _username;
  late final TextEditingController _password;
  bool _keyObscured = true;
  bool _passObscured = true;

  @override
  void initState() {
    super.initState();
    final SettingsService s = SettingsService.instance;
    _apiKey = TextEditingController(text: s.subtitleApiKey.value);
    _username = TextEditingController(text: s.subtitleUsername.value);
    // D13 amended (owner 2026-09-13): the password is persisted
    // scrambled, so it comes back with the key and the username instead
    // of being empty after every restart.
    _password = TextEditingController(text: s.subtitlePassword.value);
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SecretField(
          controller: _apiKey,
          title: 'API key',
          helper: 'Needed for subtitle search & download.',
          obscured: _keyObscured,
          onToggleObscure: () =>
              setState(() => _keyObscured = !_keyObscured),
          onChanged: (String v) =>
              SettingsService.instance.setSubtitleApiKey(v),
        ),
        const SizedBox(height: 14),
        _PlainField(
          controller: _username,
          title: 'Username',
          onChanged: (String v) =>
              SettingsService.instance.setSubtitleUsername(v),
        ),
        const SizedBox(height: 14),
        _SecretField(
          controller: _password,
          title: 'Password',
          // D13 amended (owner 2026-09-13) — the old helper ("Never
          // written to disk — this session only") described the rule that
          // broke downloads after every restart. It now names what the
          // field does and how it is kept, honestly and in the same
          // naming-not-teaching register as the key's helper.
          helper: 'Remembered between sessions — stored scrambled.',
          obscured: _passObscured,
          onToggleObscure: () =>
              setState(() => _passObscured = !_passObscured),
          onChanged: (String v) =>
              SettingsService.instance.setSubtitlePassword(v),
        ),
      ],
    );
  }
}

/// One titled + helper'd secret field with the eye toggle and clear ×.
class _SecretField extends StatelessWidget {
  const _SecretField({
    required this.controller,
    required this.title,
    this.helper,
    required this.obscured,
    required this.onToggleObscure,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String title;
  final String? helper;
  final bool obscured;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (helper != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            helper!,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        _FieldShell(
          controller: controller,
          obscureText: obscured,
          onChanged: onChanged,
          trailing: <Widget>[
            _FieldMiniButton(
              icon: obscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              tooltip: obscured ? 'Show' : 'Hide',
              onTap: onToggleObscure,
            ),
            // §2.1: the × exists only while the field holds something.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (BuildContext context, TextEditingValue v, Widget? _) {
                if (v.text.isEmpty) return const SizedBox(width: 4);
                return _FieldMiniButton(
                  icon: Icons.close,
                  tooltip: 'Clear',
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  },
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// A plain (non-secret) titled field — same visuals as [_SecretField]
/// minus the eye/clear row (the username's shape; helpers, when a plain
/// field ever needs one, go through [_SecretField]'s pattern).
class _PlainField extends StatelessWidget {
  const _PlainField({
    required this.controller,
    required this.title,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String title;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _FieldShell(controller: controller, onChanged: onChanged),
      ],
    );
  }
}

/// The shared field surface: surface fill + hairline, Segoe text, and an
/// optional trailing mini-mark cluster (eye / clear).
class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.controller,
    required this.onChanged,
    this.obscureText = false,
    this.trailing = const <Widget>[],
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool obscureText;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF333336)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textPrimary,
                letterSpacing: 0.2,
              ),
              cursorColor: AppColors.textPrimary,
              cursorWidth: 1,
              onChanged: onChanged,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (trailing.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            ...trailing,
          ],
        ],
      ),
    );
  }
}

/// The small eye / clear squares inside a field — the dialog's own
/// HoverIconButton recipe at a tighter 28 px (stock icons, dialog-only).
class _FieldMiniButton extends StatefulWidget {
  const _FieldMiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_FieldMiniButton> createState() => _FieldMiniButtonState();
}

class _FieldMiniButtonState extends State<_FieldMiniButton> {
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
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.surfaceHighlight
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// §2.2 — the preferred-language dropdown row. Same tile styling as the
/// option rows; tapping opens the anchored pill with the curated list
/// (English → Bahasa, more later per cc.md), tick on the current one.
class _LanguageSelector extends StatefulWidget {
  const _LanguageSelector();

  @override
  State<_LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<_LanguageSelector> {
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      _dismiss();
      return;
    }
    final RenderBox box =
        _anchorKey.currentContext!.findRenderObject() as RenderBox;
    final Offset pos = box.localToGlobal(Offset.zero);
    final SettingsService settings = SettingsService.instance;
    _entry = OverlayEntry(builder: (BuildContext overlayContext) {
      return Stack(
        children: <Widget>[
          // Opaque: the choosing click must not fall through.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
              onSecondaryTap: _dismiss,
            ),
          ),
          Positioned(
            left: pos.dx,
            top: pos.dy + box.size.height + 6,
            width: box.size.width,
            child: _glassPill(settings),
          ),
        ],
      );
    });
    Overlay.of(context).insert(_entry!);
  }

  void _pick(String code) {
    unawaited(SettingsService.instance.setSubtitleLanguage(code));
    _dismiss();
  }

  Widget _glassPill(SettingsService settings) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceOutline),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 32,
              offset: Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: ValueListenableBuilder<String>(
            valueListenable: settings.subtitleLanguage,
            builder: (BuildContext context, String current, Widget? _) {
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: <Widget>[
                  for (final MapEntry<String, String> e
                      in LanguageNames.preferred.entries)
                    _LanguageRow(
                      name: e.value,
                      selected: e.key == current,
                      onTap: () => _pick(e.key),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;
    return ValueListenableBuilder<String>(
      valueListenable: settings.subtitleLanguage,
      builder: (BuildContext context, String code, Widget? _) {
        final String name = LanguageNames.nameOf(code) ?? code;
        return GestureDetector(
          key: _anchorKey,
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF333336)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.translate_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Preferred language',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Auto-downloads try it first.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.expand_more,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One language row in the anchored pill — label + tick when current.
class _LanguageRow extends StatefulWidget {
  const _LanguageRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LanguageRow> createState() => _LanguageRowState();
}

class _LanguageRowState extends State<_LanguageRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: _hovered
              ? AppColors.surfaceHighlight
              : Colors.transparent,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: widget.selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              if (widget.selected)
                const Icon(
                  Icons.check,
                  size: 15,
                  color: AppColors.textPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// §2.3 — the Auto-download switch row, same tile styling with a switch
/// at the right edge where the radio dot sits on General tiles.
class _AutoDownloadSwitch extends StatelessWidget {
  const _AutoDownloadSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.subtitleAutoDownload,
      builder: (BuildContext context, bool on, Widget? _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              SettingsService.instance.setSubtitleAutoDownload(!on),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? const Color(0x144C9EEB) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on
                    ? const Color(0x404C9EEB)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: on
                        ? const Color(0x264C9EEB)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.download_outlined,
                    size: 20,
                    color: on
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Auto-download',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        // §2.3's locked helper copy.
                        'Fetches the best match when a video has no subtitles.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _SaluSwitch(on: on),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// SALU's monochrome switch: a 34×20 pill, the knob on the right when
/// on — always monochrome except the animated knob (rules 6–7).
class _SaluSwitch extends StatelessWidget {
  const _SaluSwitch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: 34,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: on ? AppColors.accent : const Color(0xFF3A3A3C),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _FolderAutoloadOption {
  const _FolderAutoloadOption({
    required this.mode,
    required this.icon,
    required this.label,
    required this.helper,
    this.isDefault = false,
  });

  final FolderAutoloadMode mode;
  final IconData icon;
  final String label;
  final String helper;
  final bool isDefault;
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
