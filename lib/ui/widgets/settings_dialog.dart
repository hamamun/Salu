import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/language_names.dart';
import '../../core/remote/remote_service.dart';
import '../../core/settings_service.dart';
import '../../core/tune/eq_memory.dart';
import '../../core/tune_service.dart';
import '../../core/web/web_data_control.dart';
import '../../core/web/web_download_service.dart';
import '../../core/web/web_popup_service.dart';
import '../../theme/app_theme.dart';
import '../osd/osd_controller.dart';
import 'dot_grid_icon.dart';
import 'salu_marks.dart';

/// SALU's settings window — a centered, SALU-styled dialog over a dimmed
/// backdrop, opened by the 6-dot button in the title bar and by the
/// browser's own ⋮ menu.
///
/// Current tabs: General · Subtitles · Web. The tab strip is structured
/// so later phases' Video / Audio tabs can slot right in.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, this.initialTab = SettingsTab.general, this.onOpenRemote});

  /// The tab the window opens on. General is the default at every door;
  /// the browser's own doors ask for Web — a viewer who came from the web
  /// section is after the web settings and should not have to hunt for
  /// them through General first.
  final SettingsTab initialTab;
  final VoidCallback? onOpenRemote;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

/// The window's three tabs. Public because a caller picks the one to open
/// on ([SettingsDialog.initialTab]).
enum SettingsTab { general, subtitles, web }

class _SettingsDialogState extends State<SettingsDialog> {
  /// Opens on the door the viewer came through, then moves only by their
  /// own taps. `late` because a field initializer cannot reach `widget`
  /// any other way — and it is read once, at the first build, so a later
  /// rebuild never throws the viewer back to the tab they arrived on.
  late SettingsTab _tab = widget.initialTab;

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
            selected: _tab == SettingsTab.general,
            onTap: () => setState(() => _tab = SettingsTab.general),
          ),
          // cc.md §2 — the Subtitles tab (D1…D5, D13).
          _TabButton(
            label: 'Subtitles',
            selected: _tab == SettingsTab.subtitles,
            onTap: () => setState(() => _tab = SettingsTab.subtitles),
          ),
          // web.md — the Web tab: the browser's settings (Search
          // suggestions + pop-ups + the auto-clear schedule).
          _TabButton(
            label: 'Web',
            selected: _tab == SettingsTab.web,
            onTap: () => setState(() => _tab = SettingsTab.web),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_tab) {
      SettingsTab.general => _GeneralTab(onOpenRemote: widget.onOpenRemote),
      SettingsTab.subtitles => const _SubtitlesTab(),
      SettingsTab.web => const _WebTab(),
    };
  }
}

// ── Web tab (web.md) ───────────────────────────────────────────────────────

/// The browser's settings, and only the browser's: the address bar's
/// Google leg (web.md · "controlled by a Settings 'Search suggestions'
/// toggle"), the pop-up default + per-site exceptions (web.md · pop-ups
/// lock, 2026-09-17 cut), and the auto-clear schedule (web.md ·
/// Auto-clear — LOCKED: off by default, every 7/15/30 days, at opening /
/// closing / both). Everything else the browser does is a lock, not a
/// setting.
class _WebTab extends StatelessWidget {
  const _WebTab();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Address bar',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'What typing into the bar may offer.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _WebSearchSuggestionsSwitch(),
          SizedBox(height: 28),
          Text(
            'Page colours',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'What sites are told you prefer. SALU itself stays dark either '
            'way. Applies right away — pages re-theme in place.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _WebPageSchemePicker(),
          SizedBox(height: 28),
          Text(
            'Downloads',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Where the files you download land. Asking opens the Windows '
            'Save As, one download at a time.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _WebAskDownloadSwitch(),
          SizedBox(height: 8),
          _WebDownloadFolderRow(),
          SizedBox(height: 28),
          Text(
            'Pop-ups',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'What sites may open on their own. Held-back pop-ups show in '
            'the address bar.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _WebPopupDefaultPicker(),
          SizedBox(height: 20),
          Text(
            'Exceptions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Sites that ignore the default — made in the padlock panel.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 12),
          _WebPopupExceptions(),
          SizedBox(height: 28),
          Text(
            'Auto-clear',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Sweep the browser’s own footprint on a schedule — history, '
            'cookies, cached files, downloads. SALU’s memory is never part '
            'of it.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _WebAutoClearPicker(),
          SizedBox(height: 28),
          Text(
            'When to run',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Closing is the reliable moment.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _WebAutoClearTimingPicker(),
          SizedBox(height: 28),
          _WebEngineFooter(),
        ],
      ),
    );
  }
}

/// The Google leg of the address bar. Off, the dropdown still answers —
/// it just only knows the user's own pages (history + favourites).
class _WebSearchSuggestionsSwitch extends StatelessWidget {
  const _WebSearchSuggestionsSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.webSearchSuggestions,
      builder: (BuildContext context, bool on, Widget? _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              SettingsService.instance.setWebSearchSuggestions(!on),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? const Color(0x144C9EEB) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on ? const Color(0x404C9EEB) : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        on ? const Color(0x264C9EEB) : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color:
                          on ? AppColors.accent : AppColors.textSecondary,
                    ),
                    child: const Icon(Icons.public,
                        size: 20, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Search suggestions',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'While you type, Google offers — merged under your '
                        'own pages.',
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

/// What sites may open on their own. Block is the default and Block is
/// quiet: held-back pop-ups count into the address bar's badge instead of
/// rendering anywhere, and flipping the default never opens or closes
/// anything already held back.
class _WebPopupDefaultPicker extends StatelessWidget {
  const _WebPopupDefaultPicker();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebPopupDefault>(
      valueListenable: SettingsService.instance.webPopupDefault,
      builder: (BuildContext context, WebPopupDefault policy, Widget? _) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OptionTile(
                icon: Icons.block_outlined,
                label: 'Block',
                helper:
                    'Sites must ask — held-back pop-ups show in the address bar.',
                isDefault: true,
                selected: policy == WebPopupDefault.block,
                onTap: () => SettingsService.instance
                    .setWebPopupDefault(WebPopupDefault.block),
              ),
            ),
            _OptionTile(
              icon: Icons.open_in_new_outlined,
              label: 'Allow',
              helper: 'Sites may open new tabs on their own.',
              selected: policy == WebPopupDefault.allow,
              onTap: () => SettingsService.instance
                  .setWebPopupDefault(WebPopupDefault.allow),
            ),
          ],
        );
      },
    );
  }
}

/// Page colours — what `prefers-color-scheme` answers inside the browser.
/// Light is the default so pages match Edge; "Follow Windows" is the raw
/// WebView2 behaviour (dark app mode ⇒ dark sites). Applied to the engine
/// live through its own profile colour-scheme control — pages re-theme in
/// place when a choice is picked.
class _WebPageSchemePicker extends StatelessWidget {
  const _WebPageSchemePicker();

  static const List<
      ({
        WebPageScheme scheme,
        IconData icon,
        String label,
        String helper,
      })> _options =
      <({
        WebPageScheme scheme,
        IconData icon,
        String label,
        String helper,
      })>[
    (
      scheme: WebPageScheme.light,
      icon: Icons.light_mode_outlined,
      label: 'Light',
      helper: 'Pages look the way Edge shows them.',
    ),
    (
      scheme: WebPageScheme.dark,
      icon: Icons.dark_mode_outlined,
      label: 'Dark',
      helper: 'Sites that carry a dark theme use it.',
    ),
    (
      scheme: WebPageScheme.system,
      icon: Icons.brightness_auto_outlined,
      label: 'Follow Windows',
      helper: 'Whatever Windows app mode says — dark PC, dark sites.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebPageScheme>(
      valueListenable: SettingsService.instance.webPageScheme,
      builder: (BuildContext context, WebPageScheme current, Widget? _) {
        return Column(
          children: <Widget>[
            for (final ({WebPageScheme scheme, IconData icon, String label, String helper}) option in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OptionTile(
                  icon: option.icon,
                  label: option.label,
                  helper: option.helper,
                  isDefault: option.scheme == WebPageScheme.light,
                  selected: current == option.scheme,
                  onTap: () => SettingsService.instance
                      .setWebPageScheme(option.scheme),
                ),
              ),
            const _PageSchemeEngineNote(),
          ],
        );
      },
    );
  }
}

/// The honesty line under Page colours: while a colour push stands refused
/// by the engine (`WebDataControlService.pageSchemeFailed`), the picker
/// says so instead of pretending — with the two things that fix it.
/// Silent the rest of the time.
class _PageSchemeEngineNote extends StatelessWidget {
  const _PageSchemeEngineNote();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WebDataControlService.instance.pageSchemeFailed,
      builder: (BuildContext context, bool failed, Widget? _) {
        if (!failed) return const SizedBox.shrink();
        return const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.warning_amber_outlined,
                    size: 15, color: AppColors.statusDead),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Page colours couldn’t reach the web engine — pages follow '
                  'Windows instead. Update the WebView2 Runtime (Windows '
                  'Update) and make sure SALU itself is up to date.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The engine line at the foot of Settings → Web: which WebView2 Runtime
/// SALU's pages render with. The query already lives in the plugin
/// (`getWebViewVersion`, upstream) — SALU only surfaces it, so a refused
/// Page colours push points at something concrete.
class _WebEngineFooter extends StatelessWidget {
  const _WebEngineFooter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: WebDataControlService.instance.runtimeVersion(),
      builder: (BuildContext context, AsyncSnapshot<String?> snap) {
        final String? v = snap.data;
        final String label;
        if (snap.connectionState == ConnectionState.waiting) {
          label = 'Engine · WebView2 …';
        } else if (v == null || v.isEmpty) {
          label = 'Engine · WebView2 (not detected)';
        } else {
          label = 'Engine · WebView2 $v';
        }
        return Text(
          label,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary),
        );
      },
    );
  }
}

/// Settings → Web → Downloads: Chrome/Edge's own "Ask where to save each
/// file before downloading". **On by default** — every download opens the
/// native Windows Save As and not one byte is written until a place is
/// chosen; walking away from that dialog cancels the download outright,
/// and a cancelled download never reaches the shelf (it is not a failed
/// one, it is a refused one). Off, files go straight to the folder below
/// with no question at all. Either way the change reaches every live tab
/// at once (`WebDataControlService.applyDownloadPreferences`) — no
/// restart, and a download already travelling keeps the path it was given.
class _WebAskDownloadSwitch extends StatelessWidget {
  const _WebAskDownloadSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.webAskDownloadLocation,
      builder: (BuildContext context, bool on, Widget? _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(
              SettingsService.instance.setWebAskDownloadLocation(!on)),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? const Color(0x144C9EEB) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on ? const Color(0x404C9EEB) : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        on ? const Color(0x264C9EEB) : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color:
                          on ? AppColors.accent : AppColors.textSecondary,
                    ),
                    child: const Icon(Icons.save_alt,
                        size: 20, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Ask where to save each file',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Off, downloads go straight to the folder below.',
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

/// Settings → Web → Downloads: the folder downloads belong to — and, with
/// asking on, the folder the Save As question starts in. Empty is the
/// honest default ("the Windows Downloads folder", a relocated one
/// included), so the row says that in words rather than showing a path
/// SALU guessed, and it offers the reset only once a folder of the
/// viewer's own is in force.
class _WebDownloadFolderRow extends StatelessWidget {
  const _WebDownloadFolderRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: SettingsService.instance.webDownloadFolder,
      builder: (BuildContext context, String folder, Widget? _) {
        final String trimmed = folder.trim();
        final bool custom = trimmed.isNotEmpty;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                unawaited(WebDownloadService.pickDownloadFolder()),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Download location',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Tooltip(
                          message: custom
                              ? trimmed
                              : 'The Windows Downloads folder',
                          waitDuration: const Duration(milliseconds: 400),
                          child: Text(
                            custom ? trimmed : 'Windows Downloads folder',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (custom)
                    _HoverIconButton(
                      icon: Icons.restart_alt,
                      tooltip: 'Use the Windows folder',
                      onPressed: () => unawaited(
                          SettingsService.instance.setWebDownloadFolder('')),
                    ),
                  _HoverIconButton(
                    icon: Icons.folder_open,
                    tooltip: 'Change…',
                    onPressed: () =>
                        unawaited(WebDownloadService.pickDownloadFolder()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The per-site pop-up rules, made in the padlock panel (Chrome's Allowed
/// / Blocked lists). Removing one hands the site back to the default.
class _WebPopupExceptions extends StatelessWidget {
  const _WebPopupExceptions();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<WebPopupException>>(
      valueListenable: WebPopupService.instance.exceptions,
      builder: (BuildContext context, List<WebPopupException> rules,
          Widget? _) {
        if (rules.isEmpty) {
          return const Text(
            'No exceptions — every site follows the default.',
            style:
                TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          );
        }
        return Column(
          children: <Widget>[
            for (final WebPopupException rule in rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          rule.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: rule.allow
                              ? const Color(0x1F4C9EEB)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: rule.allow
                                ? const Color(0x404C9EEB)
                                : const Color(0xFF3A3A3C),
                          ),
                        ),
                        child: Text(
                          rule.allow ? 'Allow' : 'Block',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: rule.allow
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _HoverIconButton(
                        icon: Icons.close,
                        tooltip: 'Remove',
                        onPressed: () => WebPopupService.instance
                            .removeFor(rule.host),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// How often the sweep runs. Off is the default and Off is silent: switching
/// it never wipes anything, and switching back resumes the schedule — the
/// same safety rule the Resume mode follows.
class _WebAutoClearPicker extends StatelessWidget {
  const _WebAutoClearPicker();

  static const List<({WebAutoClearInterval interval, IconData icon, String label, String helper, bool isDefault})>
      _options = <({WebAutoClearInterval interval, IconData icon, String label, String helper, bool isDefault})>[
    (
      interval: WebAutoClearInterval.off,
      icon: Icons.block_outlined,
      label: 'Off',
      helper: 'The browser keeps what it collected until you clear it.',
      isDefault: true,
    ),
    (
      interval: WebAutoClearInterval.days7,
      icon: Icons.cleaning_services_outlined,
      label: 'Every 7 days',
      helper: 'A weekly sweep of the whole browser footprint.',
      isDefault: false,
    ),
    (
      interval: WebAutoClearInterval.days15,
      icon: Icons.cleaning_services_outlined,
      label: 'Every 15 days',
      helper: 'Two weeks between sweeps.',
      isDefault: false,
    ),
    (
      interval: WebAutoClearInterval.days30,
      icon: Icons.cleaning_services_outlined,
      label: 'Every 30 days',
      helper: 'A monthly sweep.',
      isDefault: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebAutoClearInterval>(
      valueListenable: SettingsService.instance.webAutoClearDays,
      builder: (BuildContext context, WebAutoClearInterval interval,
          Widget? _) {
        return Column(
          children: <Widget>[
            for (final ({
              WebAutoClearInterval interval,
              IconData icon,
              String label,
              String helper,
              bool isDefault
            }) option in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OptionTile(
                  icon: option.icon,
                  label: option.label,
                  helper: option.helper,
                  isDefault: option.isDefault,
                  selected: interval == option.interval,
                  onTap: () => SettingsService.instance
                      .setWebAutoClearDays(option.interval),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The two moments the sweep can run at — the app opening, the app closing,
/// or either. The close-time sweep is the reliable one (a locked profile
/// folder is released when the process ends), so its rows say so plainly.
class _WebAutoClearTimingPicker extends StatelessWidget {
  const _WebAutoClearTimingPicker();

  static const List<
      ({
        WebAutoClearTiming timing,
        IconData icon,
        String label,
        String helper,
      })> _options =
      <({
        WebAutoClearTiming timing,
        IconData icon,
        String label,
        String helper,
      })>[
    (
      timing: WebAutoClearTiming.onOpen,
      icon: Icons.login_outlined,
      label: 'On opening',
      helper: 'The sweep lands at startup, before the first page.',
    ),
    (
      timing: WebAutoClearTiming.onClose,
      icon: Icons.logout_outlined,
      label: 'On closing',
      helper: 'The most reliable moment — the browser is done with it.',
    ),
    (
      timing: WebAutoClearTiming.both,
      icon: Icons.swap_vert_outlined,
      label: 'Both',
      helper: 'Closing sweeps; opening sweeps if anything was missed.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebAutoClearTiming>(
      valueListenable: SettingsService.instance.webAutoClearTiming,
      builder: (BuildContext context, WebAutoClearTiming timing, Widget? _) {
        return Column(
          children: <Widget>[
            for (final ({WebAutoClearTiming timing, IconData icon, String label, String helper}) option in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OptionTile(
                  icon: option.icon,
                  label: option.label,
                  helper: option.helper,
                  selected: timing == option.timing,
                  onTap: () => SettingsService.instance
                      .setWebAutoClearTiming(option.timing),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── General tab ─────────────────────────────────────────────────────────────

class _GeneralTab extends StatelessWidget {
  const _GeneralTab({this.onOpenRemote});

  final VoidCallback? onOpenRemote;

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
          SizedBox(height: 28),
          Text(
            'Equalizer',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'What SALU may decide for itself about sound.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          _AutoEqSwitch(),
          SizedBox(height: 10),
          _MouseOverPreviewSwitch(),
          SizedBox(height: 10),
          _ClearEqMemoryRow(),
          SizedBox(height: 28),
          _RemoteSection(onOpenRemote: onOpenRemote),
        ],
      ),
    );
  }
}

/// App-wide PC-side remote controls. The listener itself lives in
/// RemoteService; these rows are deliberately in General so the off switch
/// remains reachable from both Player and Web mode.
class _RemoteSection extends StatelessWidget {
  const _RemoteSection({this.onOpenRemote});

  final VoidCallback? onOpenRemote;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Remote', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Control SALU from your phone over your Wi-Fi.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          const _RemoteControlSwitch(),
          const SizedBox(height: 10),
          const _RemoteFileSwitch(),
          const SizedBox(height: 10),
          _RemoteOpenPanelRow(onOpen: () {
            Navigator.of(context).pop();
            onOpenRemote?.call();
          }),
          _RemoteRememberedRow(onOpen: () {
            Navigator.of(context).pop();
            onOpenRemote?.call();
          }),
        ],
      );
}

class _RemoteControlSwitch extends StatelessWidget {
  const _RemoteControlSwitch();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: SettingsService.instance.remoteEnabled,
        builder: (BuildContext context, bool on, Widget? _) => _RemoteTile(
          title: 'Remote control',
          helper: 'Let the SALU Remote app control playback. Local network only.',
          on: on,
          mark: const QrMark(size: 20),
          onTap: () => SettingsService.instance.setRemoteEnabled(!on),
        ),
      );
}

class _RemoteFileSwitch extends StatelessWidget {
  const _RemoteFileSwitch();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: SettingsService.instance.remoteFileAccess,
        builder: (BuildContext context, bool on, Widget? _) => _RemoteTile(
          title: 'Let phones browse PC files',
          helper: 'Read-only. Folders and media names only.',
          on: on,
          mark: const FilmFrameMark(size: 20),
          onTap: () => SettingsService.instance.setRemoteFileAccess(!on),
        ),
      );
}

class _RemoteTile extends StatelessWidget {
  const _RemoteTile({required this.title, required this.helper, required this.on, required this.mark, required this.onTap});
  final String title;
  final String helper;
  final bool on;
  final Widget mark;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: on ? const Color(0x144C9EEB) : Colors.transparent, borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? const Color(0x404C9EEB) : Colors.transparent)),
          child: Row(children: <Widget>[
            Container(width: 40, height: 40, decoration: BoxDecoration(color: on ? const Color(0x264C9EEB) : AppColors.surface, borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: IconTheme.merge(data: IconThemeData(color: on ? AppColors.accent : AppColors.textSecondary), child: mark)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), const SizedBox(height: 3), Text(helper, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))])),
            _SaluSwitch(on: on),
          ]),
        ),
      );
}

class _RemoteOpenPanelRow extends StatelessWidget {
  const _RemoteOpenPanelRow({required this.onOpen});
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: SettingsService.instance.remoteEnabled,
        builder: (BuildContext context, bool enabled, Widget? _) => InkWell(
          onTap: enabled ? onOpen : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: <Widget>[
              Expanded(
                child: Text(
                  enabled ? 'Show pairing code…' : 'Turn remote control on to pair a phone.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: enabled ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: enabled ? AppColors.textSecondary : AppColors.divider,
              ),
            ]),
          ),
        ),
      );
}

class _RemoteRememberedRow extends StatelessWidget {
  const _RemoteRememberedRow({required this.onOpen});
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<RemoteDevice>>(
        valueListenable: RemoteService.instance.devices,
        builder: (BuildContext context, List<RemoteDevice> devices, Widget? _) =>
            InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: <Widget>[
              Expanded(
                child: Text(
                  'Remembered phones · ${devices.length}',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
            ]),
          ),
        ),
      );
}

/// Auto EQ (§5) — one switch, default Off, sitting with the Resume and
/// Folder auto-load options exactly as the spec asks. On, SALU picks a preset
/// at file load from the file's own facts and learns from what you keep.
/// Off, nothing is guessed — and switching it off leaves the current
/// settings exactly as they are (§5's safety rule).
class _AutoEqSwitch extends StatelessWidget {
  const _AutoEqSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.autoEq,
      builder: (BuildContext context, bool on, Widget? _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => SettingsService.instance.setAutoEq(!on),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? const Color(0x144C9EEB) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on ? const Color(0x404C9EEB) : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        on ? const Color(0x264C9EEB) : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: on ? AppColors.accent : AppColors.textSecondary,
                    ),
                    child: const EqualizerMark(size: 20),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Auto EQ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Picks a starting sound when a file loads, and learns '
                        'from what you keep.',
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

/// **Mouse over preview** — the Equalizer section's second switch (owner,
/// 2026-09-14). It decides whether a pointer that merely RESTS on a Tune
/// control previews the value under it (eq_imp.md §8's hover recipe) or only
/// lights the control up.
///
/// Default **Off**. Off, the panel moves on a press or a drag and on nothing
/// else, so a pointer crossing the window on its way somewhere can never
/// change the sound or the picture; the value already in force is untouched
/// either way. Same tile as Auto EQ: one switch, applied instantly.
class _MouseOverPreviewSwitch extends StatelessWidget {
  const _MouseOverPreviewSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.mouseOverPreview,
      builder: (BuildContext context, bool on, Widget? _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => SettingsService.instance.setMouseOverPreview(!on),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? const Color(0x144C9EEB) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on ? const Color(0x404C9EEB) : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        on ? const Color(0x264C9EEB) : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.mouse_outlined,
                    size: 20,
                    color: on ? AppColors.accent : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Mouse over preview',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Previews the value a resting pointer is on. Off, a '
                        'click or a drag is what moves it.',
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

/// The learning map's one control (§5's data policy): a row that names how
/// much SALU remembers and wipes it in a tap. No confirm dialog — the house
/// answer is the 5-second Undo toast on the deck, which restores the exact
/// snapshot. Disabled when there is nothing to clear.
class _ClearEqMemoryRow extends StatelessWidget {
  const _ClearEqMemoryRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      // Any notifier on the service wakes this row; the map itself is a plain
      // object, and its size changes only alongside real tune state writes.
      valueListenable: TuneService.instance.autoPick,
      builder: (BuildContext context, String? picked, Widget? child) {
        final TuneService tune = TuneService.instance;
        final int count = tune.memory.length;
        final bool enabled = count > 0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  final Map<String, EqMemoryEntry> previous =
                      tune.clearMemory();
                  OsdController.instance.show(OsdUndoCard(
                    label: 'EQ memory cleared',
                    onUndo: () => tune.restoreMemory(previous),
                  ));
                }
              : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Clear EQ memory',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  // The bound is on the record, not hidden in a file: the
                  // viewer can see the map's size, then empty it.
                  count == 0 ? 'empty' : '$count',
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 0.3,
                    color: enabled
                        ? AppColors.textSecondary
                        : AppColors.textSecondary.withAlpha(140),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
