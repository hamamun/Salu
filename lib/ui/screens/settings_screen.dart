import 'package:flutter/material.dart';

import '../../core/app_prefs.dart';
import '../../core/history_manager.dart';
import '../../core/player_service.dart';
import '../../core/updater_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/osd_indicator.dart';

/// Global Settings overlay (Phase 4 · Step 5 — UI only).
///
/// Drafts the IINA-style preferences window. Controls bind to [AppPrefs]
/// (in-memory for now); the heavy logic behind each category connects in
/// Phases 5–8 as noted in each section.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) => const SettingsScreen(),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _Category {
  general('General', Icons.palette_outlined),
  interface('User Interface', Icons.view_agenda_outlined),
  playback('Playback', Icons.play_circle_outline),
  subtitles('Subtitles', Icons.subtitles_outlined),
  updates('Updates', Icons.system_update_alt_rounded),
  keys('Key Bindings', Icons.keyboard_outlined);

  const _Category(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Category _selected = _Category.general;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 600),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _NavRail(
              selected: _selected,
              onSelect: (_Category c) => setState(() => _selected = c),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selected) {
      case _Category.general:
        return _GeneralTab();
      case _Category.interface:
        return _InterfaceTab();
      case _Category.playback:
        return _PlaybackTab();
      case _Category.subtitles:
        return _SubtitlesTab();
      case _Category.updates:
        return _UpdatesTab();
      case _Category.keys:
        return const _KeysTab();
    }
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.selected, required this.onSelect});

  final _Category selected;
  final ValueChanged<_Category> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 22, 18, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          for (final _Category category in _Category.values)
            _NavItem(
              category: category,
              selected: category == selected,
              onTap: () => onSelect(category),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SALU 0.1.0',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? AppColors.surfaceHighlight : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: <Widget>[
                Icon(category.icon,
                    size: 18,
                    color: selected ? AppColors.accent : AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(
                  category.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneralTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const List<Color> accents = <Color>[
      Color(0xFF4C9EEB),
      Color(0xFF9B6DFF),
      Color(0xFF3ECF8E),
      Color(0xFFF2C14E),
      Color(0xFFF25E7A),
    ];
    return _ScrollBody(
      children: <Widget>[
        const _Title('General'),
        const _BodyText('Accent color (applied to highlights and controls).'),
        const SizedBox(height: 14),
        ListenableBuilder(
          listenable: AppPrefs.instance,
          builder: (BuildContext context, Widget? _) {
            return Row(
              children: <Widget>[
                for (final Color color in accents)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => AppPrefs.instance.accentColor = color,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppPrefs.instance.accentColor == color
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 26),
        const _Title('Clear Cache & Data'),
        const _BodyText(
          'Wipe the browser cache, temporary downloaded .srt files, and the '
          'video resume history. (Wired in Phase 5/6.)',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => OsdController.instance
              .show('Cache cleared', icon: Icons.delete_sweep_outlined),
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('Clear Cache & Data'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
      ],
    );
  }
}

class _InterfaceTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ScrollBody(
      children: <Widget>[
        const _Title('User Interface'),
        const _BodyText('On-Screen Controller (OSC) layout architecture.'),
        const SizedBox(height: 14),
        ListenableBuilder(
          listenable: AppPrefs.instance,
          builder: (BuildContext context, Widget? _) {
            return DropdownButtonFormField<OscLayout>(
              value: AppPrefs.instance.oscLayout,
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
              items: OscLayout.values
                  .map((OscLayout layout) => DropdownMenuItem<OscLayout>(
                        value: layout,
                        child: Text(layout.label),
                      ))
                  .toList(),
              onChanged: (OscLayout? layout) {
                if (layout != null) AppPrefs.instance.oscLayout = layout;
              },
            );
          },
        ),
      ],
    );
  }
}

class _PlaybackTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ScrollBody(
      children: <Widget>[
        const _Title('Playback'),
        ListenableBuilder(
          listenable: AppPrefs.instance,
          builder: (BuildContext context, Widget? _) {
            return Column(
              children: <Widget>[
                _SwitchRow(
                  label: 'Resume last playback position',
                  subtitle: 'Silently continue from where you left off.',
                  value: AppPrefs.instance.resumeLastPosition,
                  onChanged: (bool v) => AppPrefs.instance.resumeLastPosition = v,
                ),
                _SwitchRow(
                  label: 'Auto-queue the rest of the folder',
                  subtitle:
                      'Opening Episode 1 lines up the whole folder in order.',
                  value: AppPrefs.instance.autoQueueFolder,
                  onChanged: (bool v) => AppPrefs.instance.autoQueueFolder = v,
                ),
                _SwitchRow(
                  label: 'Exact seeking by default',
                  subtitle:
                      'On: arrows seek exactly, Shift seeks by keyframe. '
                      'Off: the IINA default (arrows = keyframe, Shift = exact).',
                  value: AppPrefs.instance.exactSeekByDefault,
                  onChanged: (bool v) => AppPrefs.instance.exactSeekByDefault = v,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      HistoryManager.instance.clear();
                      OsdController.instance.show('Playback history cleared',
                          icon: Icons.delete_outline_rounded);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Clear playback history'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 8),
                const _Title('Hardware decoding'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: AppPrefs.instance.hwdec,
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
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'auto', child: Text('Auto (GPU)')),
                    DropdownMenuItem<String>(value: 'disabled', child: Text('Disabled (CPU)')),
                  ],
                  onChanged: (String? v) {
                    if (v == null) return;
                    AppPrefs.instance.hwdec = v;
                    // Phase 5 · Step 4 — push it into the live mpv instance.
                    PlayerService.instance.applyHwdecPreference();
                    OsdController.instance.show(
                      v == 'auto'
                          ? 'Hardware decoding: Auto (GPU)'
                          : 'Hardware decoding: Disabled (CPU)',
                      icon: Icons.memory_rounded,
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SubtitlesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ScrollBody(
      children: <Widget>[
        const _Title('Subtitles'),
        const _BodyText('OpenSubtitles API setup for the auto-download feature (Phase 7).'),
        const SizedBox(height: 14),
        TextField(
          obscureText: true,
          onChanged: (String v) => AppPrefs.instance.openSubtitlesApiKey = v.trim(),
          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'OpenSubtitles API Key',
            labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.divider),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.accent),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: AppPrefs.instance,
          builder: (BuildContext context, Widget? _) {
            return _SwitchRow(
              label: 'Auto-download subtitles on video load',
              subtitle: 'Silently fetch a perfect hash match (Phase 7).',
              value: AppPrefs.instance.autoDownloadSubtitles,
              onChanged: (bool v) => AppPrefs.instance.autoDownloadSubtitles = v,
            );
          },
        ),
      ],
    );
  }
}

class _UpdatesTab extends StatefulWidget {
  @override
  State<_UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<_UpdatesTab> {
  bool _busy = false;
  String? _status;

  Future<void> _run(Future<UpdateResult> Function() task) async {
    setState(() {
      _busy = true;
      _status = 'Checking…';
    });
    final UpdateResult result = await task();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = result.message;
    });
    OsdController.instance.show(
      result.message,
      icon: result.success
          ? Icons.check_rounded
          : Icons.error_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ScrollBody(
      children: <Widget>[
        const _Title('Updates'),
        const _BodyText(
          'SALU relies on external binaries for stream parsing and the built-in '
          "browser. Keep them fresh so videos don't break when a site changes.",
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(UpdaterService.instance.updateYtDlp),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Check for yt-dlp updates'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(UpdaterService.instance.updateWebView2Loader),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Check for WebView2 updates'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
        if (_busy) ...<Widget>[
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_status != null) ...<Widget>[
          const SizedBox(height: 14),
          _BodyText(_status!),
        ],
      ],
    );
  }
}

class _KeysTab extends StatelessWidget {
  const _KeysTab();

  static const List<(String, String)> bindings = <(String, String)>[
    ('Space', 'Play / Pause'),
    ('← / →', 'Seek back / forward 5 s (keyframe)'),
    ('Shift + ← / →', 'Seek back / forward 5 s (exact)'),
    ('↑ / ↓', 'Volume up / down'),
    ('M', 'Mute / unmute'),
    ('F', 'Fullscreen'),
    ('P', 'Picture-in-Picture'),
    ('I', 'Media Inspector'),
    ('Esc', 'Close panel / HUD'),
  ];

  @override
  Widget build(BuildContext context) {
    return _ScrollBody(
      children: <Widget>[
        const _Title('Key Bindings'),
        const _BodyText('Keyboard shortcuts (read-only in this phase).'),
        const SizedBox(height: 10),
        for (final (String key, String action) in bindings)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 110,
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    action,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ScrollBody extends StatelessWidget {
  const _ScrollBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  const _BodyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        color: AppColors.textSecondary,
        height: 1.45,
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
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
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      value: value,
      activeColor: AppColors.accent,
      onChanged: onChanged,
    );
  }
}
