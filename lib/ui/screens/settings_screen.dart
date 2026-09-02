import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_prefs.dart';
import '../../core/history_manager.dart';
import '../../core/language_utils.dart';
import '../../core/player_service.dart';
import '../../core/remote/remote_server.dart';
import '../../core/subtitles_api.dart';
import '../../core/thumbnail_service.dart';
import '../../core/updater_service.dart';
import '../../theme/app_theme.dart';
import '../modals/about_modal.dart';
import '../widgets/osd_indicator.dart';
import 'browser_screen.dart';

/// Global Settings overlay (Phase 4 · Step 5).
///
/// The IINA-style preferences window. Every control binds to [AppPrefs] and
/// persists through `shared_preferences`; Phases 5–8 wired up the logic for
/// resume/history, hwdec, updates, the stream library, the OpenSubtitles
/// subtitle engine (Phase 7) and the Android remote server (Phase 8).
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
  remote('Remote', Icons.smartphone_rounded),
  updates('Updates', Icons.system_update_alt_rounded),
  keys('Key Bindings', Icons.keyboard_outlined),
  about('About', Icons.info_outline_rounded);

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
        return const _SubtitlesTab();
      case _Category.remote:
        return const _RemoteTab();
      case _Category.updates:
        return const _UpdatesTab();
      case _Category.keys:
        return const _KeysTab();
      // Phase 9: About is a floating modal, not a page — the rail opens it
      // directly. This case is just the (never-selected) fallback.
      case _Category.about:
        return const AboutSection();
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
              // "About" pops the dedicated modal instead of switching pages.
              onTap: category == _Category.about
                  ? () => AboutModal.show(context)
                  : () => onSelect(category),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SALU ${AppInfo.version}',
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
          'Wipe the browser cache and cookies, the cached timeline '
          'thumbnails, and the video resume history.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            // Phase 6: destroy every live WebView2 (clears its cache and
            // cookies on the way out), then drop the resume history.
            await BrowserController.instance.closeBrowser();
            ThumbnailService.instance.clearCache();
            HistoryManager.instance.clear();
            OsdController.instance
                .show('Cache & data cleared', icon: Icons.delete_sweep_outlined);
          },
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
              initialValue: AppPrefs.instance.oscLayout,
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
                  initialValue: AppPrefs.instance.hwdec,
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

class _SubtitlesTab extends StatefulWidget {
  const _SubtitlesTab();

  @override
  State<_SubtitlesTab> createState() => _SubtitlesTabState();
}

class _SubtitlesTabState extends State<_SubtitlesTab> {
  final TextEditingController _keyField =
      TextEditingController(text: AppPrefs.instance.openSubtitlesApiKey);
  bool _revealed = false;
  bool _testing = false;

  @override
  void dispose() {
    _keyField.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    final String? problem = await SubtitlesApi.instance.testConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    if (problem == null) {
      OsdController.instance
          .show('OpenSubtitles reachable — key accepted', icon: Icons.verified_rounded);
    } else {
      OsdController.instance.show(problem, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ScrollBody(
      children: <Widget>[
        const _Title('Subtitles'),
        const _BodyText(
          'Paste a free OpenSubtitles API key to unlock the in-player search, '
          'the "Top 3 Best Matches" flow and silent auto-download. Create one '
          'at opensubtitles.com → Developers → New API Key (username "SALU").',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _keyField,
          obscureText: !_revealed,
          onChanged: (String v) => AppPrefs.instance.openSubtitlesApiKey = v.trim(),
          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'OpenSubtitles API Key',
            labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            isDense: true,
            suffixIcon: IconButton(
              tooltip: _revealed ? 'Hide key' : 'Reveal key',
              icon: Icon(
                _revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
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
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_rounded, size: 16),
              label: const Text('Test connection'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.divider),
              ),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: () => AppInfo.openExternal(AppInfo.opensubtitlesKeyUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('Get a key'),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _Title('Auto-download'),
        ListenableBuilder(
          listenable: AppPrefs.instance,
          builder: (BuildContext context, Widget? _) {
            final String current = AppPrefs.instance.defaultSubtitleLanguage;
            final List<String> codes = <String>{
              'all',
              ...LanguageUtils.commonCodes,
              if (current != 'all' && current.isNotEmpty) current,
            }.toList()
              ..sort((String a, String b) {
                if (a == 'all') return -1;
                if (b == 'all') return 1;
                return LanguageUtils.displayName(a)
                    .compareTo(LanguageUtils.displayName(b));
              });
            return Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Default language for downloads',
                        style: TextStyle(
                            fontSize: 13.5, color: AppColors.textPrimary),
                      ),
                    ),
                    DropdownButton<String>(
                      value: codes.contains(current) ? current : 'all',
                      isDense: true,
                      dropdownColor: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary),
                      items: <DropdownMenuItem<String>>[
                        for (final String code in codes)
                          DropdownMenuItem<String>(
                            value: code,
                            child: Text(
                              code == 'all'
                                  ? 'All languages'
                                  : '${LanguageUtils.flagEmoji(code)}  '
                                      '${LanguageUtils.displayName(code)}',
                            ),
                          ),
                      ],
                      onChanged: (String? value) {
                        if (value != null) {
                          AppPrefs.instance.defaultSubtitleLanguage = value;
                        }
                      },
                      menuMaxHeight: 340,
                    ),
                  ],
                ),
                _SwitchRow(
                  label: 'Auto-download subtitles on video load',
                  subtitle: 'Silent OpenSubtitles hash match, saved next to '
                      'the video as movie.srt — never downloaded twice.',
                  value: AppPrefs.instance.autoDownloadSubtitles,
                  onChanged: (bool v) => AppPrefs.instance.autoDownloadSubtitles = v,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Remote control server (Phase 8 · Step 4): the single privacy switch that
/// starts/stops the whole LAN surface, plus a live status card.
class _RemoteTab extends StatelessWidget {
  const _RemoteTab();

  static const List<(String, String)> _commands = <(String, String)>[
    ('play_pause', 'Toggle play / pause'),
    ('volume_up · volume_down', '±5 % base volume'),
    ('set_volume', 'Absolute level 0–200 % (boost included)'),
    ('mute_toggle', 'Mute / unmute'),
    ('seek_forward · seek_backward', '±5 s'),
    ('seek_to', 'Jump to {"position_ms": 125000}'),
    ('next_track · previous_track', 'Playlist navigation'),
    ('set_rate', 'Playback speed 0.25×–4×'),
    ('get_state', 'Full snapshot reply'),
  ];

  @override
  Widget build(BuildContext context) {
    return _ScrollBody(
      children: <Widget>[
        const _Title('Remote Control'),
        const _BodyText(
          'SALU can run a lightweight local WebSocket server (ws://0.0.0.0:8080) '
          'and announce itself over mDNS, so the future Android companion app '
          'finds this PC on the Wi-Fi automatically and drives the player. '
          'Commands flow in, live state broadcasts flow out.',
        ),
        const SizedBox(height: 14),
        ListenableBuilder(
          listenable: Listenable.merge(
              <Listenable>[AppPrefs.instance, RemoteServer.instance]),
          builder: (BuildContext context, Widget? _) {
            final RemoteServer remote = RemoteServer.instance;
            final bool running = remote.running;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SwitchRow(
                  label: 'Enable Remote Control Server',
                  subtitle: 'Off = the server is completely shut down: zero '
                      'open ports, zero background network activity.',
                  value: AppPrefs.instance.remoteControlEnabled,
                  onChanged: (bool v) =>
                      AppPrefs.instance.remoteControlEnabled = v,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            running
                                ? Icons.broadcast_on_home_rounded
                                : Icons.circle_outlined,
                            size: 15,
                            color: running
                                ? const Color(0xFF3ECF8E)
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            running
                                ? 'Listening on port ${remote.port}'
                                : 'Stopped',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary),
                          ),
                          const Spacer(),
                          if (running)
                            Text(
                              remote.clientCount == 1
                                  ? '1 client connected'
                                  : '${remote.clientCount} clients connected',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                      if (running && remote.endpoints().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        for (final String endpoint in remote.endpoints())
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              endpoint,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontFamily: 'Consolas',
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        const Text(
                          'Auto-discovery: _salu-remote._tcp.local (mDNS/Bonjour)',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                      if (!running)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Enable the switch to open the server. Windows will '
                            'ask once for a private-network firewall allowance.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      if (running && remote.lastError != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'First bind attempt failed on port 8080 — SALU '
                            'climbed to the next free port.',
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const _Title('Wire protocol (JSON per frame)'),
                const SizedBox(height: 6),
                for (final (String action, String desc) in _commands)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 220,
                          child: Text(
                            action,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontFamily: 'Consolas',
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            desc,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                const _BodyText(
                  '…and SALU broadcasts {"type":"state", title, playing, '
                  'volume, position_ms, duration_ms, …} — instantly on every '
                  'state change, throttled to 4 Hz while scrubbing.',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _UpdatesTab extends StatefulWidget {
  const _UpdatesTab();

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
              : () => _run(() async {
                    final UpdateResult r =
                        await UpdaterService.instance.updateYtDlp();
                    // Re-point mpv at the (possibly new) binary.
                    await PlayerService.instance.applyYtDlpPath();
                    return r;
                  }),
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
      activeThumbColor: AppColors.accent,
      onChanged: onChanged,
    );
  }
}
