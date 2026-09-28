import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/language_names.dart';
import '../../core/remote/remote_service.dart';
import '../../core/settings_service.dart';
import '../../core/tune/eq_memory.dart';
import '../../core/tune_service.dart';
import '../../core/updater/update_manifest.dart';
import '../../core/updater/updater_service.dart';
import '../../core/web/web_data_control.dart';
import '../../core/web/web_download_service.dart';
import '../../core/web/web_popup_service.dart';
import '../../theme/app_theme.dart';
import '../osd/osd_controller.dart';
import 'dot_grid_icon.dart';
import 'remote_firewall_dialog.dart';
import 'salu_icon_button.dart';
import 'shortcuts_tab.dart';
import 'update_dialog.dart';

/// SALU's settings window — a centered, SALU-styled dialog over a dimmed
/// backdrop, opened by the 6-dot button in the title bar and by the
/// browser's own ⋮ menu.
///
/// **The list is the design (owner ruling, 2026-09-28).** Every tab is one
/// quiet column: a small uppercase caption per group, then one-line rows —
/// label on the left, control on the right, a hairline between rows and a
/// soft wash under the pointer. SALU prints *names and values*, never
/// sentences (follow.md rules 1 and 6): the old per-section and per-row
/// helper lines are gone, and what a name cannot carry rides as a
/// hover-delay tooltip on the control itself.
///
/// Three things the list gained on 2026-09-28 and keeps everywhere:
/// **each pill set names its factory default** in one quiet line below it
/// (`Default · Borderless`) — a word, never a dot — and **each group
/// carries a reset mark on its caption while anything in it stands off
/// that default**, which applies instantly and leaves the house Undo
/// toast (follow.md rule 3). **The third is the master reset**: the
/// right-hand end of the tab strip wears the same mark while *any*
/// preference stands off its default, and one press puts the whole window
/// back — every preference, one Undo. Preferences only: the
/// OpenSubtitles account, EQ memory, paired phones and the per-site
/// pop-up rules are never part of it.
///
/// Current tabs: General · Subtitles · Web · Updates · Shortcuts. The tab
/// strip is untouched — it is the one place the window explains itself by
/// structure, and Shortcuts stays exactly as it is.
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

/// The window's tabs. Public because a caller picks the one to open
/// on ([SettingsDialog.initialTab]).
enum SettingsTab { general, subtitles, web, updates, shortcuts }

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      backgroundColor: Colors.transparent,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 620 × 620 holds the tallest tab (General, whose three pill
          // sets each carry their `Default · …` line) whole on any window
          // at 720 px or taller; below that the body still scrolls, it
          // just never draws a bar about it (`_QuietScroll`).
          final double width = math.min(620.0, constraints.maxWidth);
          final double height = math.min(620.0, constraints.maxHeight);
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
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
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
          _MarkButton(
            icon: Icons.close,
            tooltip: 'Close',
            size: 32,
            iconSize: 17,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// The tabs, and — at the strip's right end, the same place on every
  /// tab — the master reset (owner ruling, 2026-09-28). The strip is the
  /// one row that belongs to all tabs, which is exactly what that control
  /// governs; it is silent while every preference sits on its default.
  Widget _buildTabStrip() {
    // Five labels overflow very narrow dialogs — below that width the
    // tabs slide horizontally instead (shortcut.md §4.1 · accommodation).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                  // updater.md — the Updates tab: the component feed cadence and
                  // the "Check now" door into the updater modal.
                  _TabButton(
                    label: 'Updates',
                    selected: _tab == SettingsTab.updates,
                    onTap: () => setState(() => _tab = SettingsTab.updates),
                  ),
                  // shortcut.md §4.1 — the Shortcuts tab (the Living Map): the
                  // rightmost tab, a reference page rather than a setting.
                  _TabButton(
                    label: 'Shortcuts',
                    selected: _tab == SettingsTab.shortcuts,
                    onTap: () => setState(() => _tab = SettingsTab.shortcuts),
                  ),
                ],
              ),
            ),
          ),
          const _MasterResetButton(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_tab) {
      SettingsTab.general => _GeneralTab(onOpenRemote: widget.onOpenRemote),
      SettingsTab.subtitles => const _SubtitlesTab(),
      SettingsTab.web => const _WebTab(),
      SettingsTab.updates => const _UpdatesTab(),
      SettingsTab.shortcuts => const ShortcutsTab(),
    };
  }
}

// ── The shared row vocabulary (owner ruling, 2026-09-28) ───────────────────
//
// One caption, one row, one pill set, one action mark. Every tab draws
// from these four and nothing else, so the five tabs read as one surface
// and a future Video / Audio tab costs no new design.

/// The one text style for group captions — small, spaced, quiet.
const TextStyle _captionStyle = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.1,
  color: AppColors.textSecondary,
);

/// A setting's name. Never a sentence.
const TextStyle _labelStyle = TextStyle(
  fontSize: 13.5,
  color: AppColors.textPrimary,
);

/// A setting's current value or state (a path, a date, a count, a word).
const TextStyle _valueStyle = TextStyle(
  fontSize: 12.5,
  color: AppColors.textSecondary,
);

/// Selected pill tint + hairline (the group-by pill's recipe, reused).
const Color _pillFill = Color(0x1F4C9EEB);
const Color _pillLine = Color(0x404C9EEB);

/// The pointer's wash on an interactive row.
const Color _rowHover = Color(0x0DFFFFFF);

/// The quiet line under a pill set that names the factory default — a
/// word the viewer can read, not a dot they have to learn (owner,
/// 2026-09-28 · enhancement 5).
const TextStyle _defaultCaptionStyle = TextStyle(
  fontSize: 10,
  letterSpacing: 0.3,
  color: AppColors.textSecondary,
);

/// A group's reset wiring (enhancement 3, 2026-09-28).
///
/// [sources] are the notifiers the group's settings live on, so the mark
/// appears and disappears live; [isModified] asks whether anything in the
/// group currently stands off its factory default; [onReset] puts the
/// group back and leaves an Undo toast behind.
class _GroupReset {
  const _GroupReset({
    required this.sources,
    required this.isModified,
    required this.onReset,
  });

  final List<Listenable> sources;
  final bool Function() isModified;
  final VoidCallback onReset;
}

/// Every preference the settings window owns, in one object.
///
/// It is the master reset's whole vocabulary (owner ruling, 2026-09-28):
/// [snapshot] reads them all, [defaults] is the factory set, [apply]
/// writes a set back through the same setters the controls use, and
/// [isDefault] answers whether anything has been moved at all.
///
/// **Preferences only.** The OpenSubtitles account, EQ memory, paired
/// phones and the per-site pop-up rules are deliberately absent — none of
/// them is a default to fall back to, and none of them is ever cleared
/// from here.
class _Preferences {
  const _Preferences({
    required this.titleBarMode,
    required this.resumeMode,
    required this.folderAutoloadMode,
    required this.autoEq,
    required this.mouseOverPreview,
    required this.remoteEnabled,
    required this.remoteFileAccess,
    required this.subtitleLanguage,
    required this.subtitleAutoDownload,
    required this.webSearchSuggestions,
    required this.webPageScheme,
    required this.webAskDownloadLocation,
    required this.webDownloadFolder,
    required this.webPopupDefault,
    required this.webAutoClearDays,
    required this.webAutoClearTiming,
    required this.updateCheckFrequency,
  });

  final TitleBarMode titleBarMode;
  final ResumeMode resumeMode;
  final FolderAutoloadMode folderAutoloadMode;
  final bool autoEq;
  final bool mouseOverPreview;
  final bool remoteEnabled;
  final bool remoteFileAccess;
  final String subtitleLanguage;
  final bool subtitleAutoDownload;
  final bool webSearchSuggestions;
  final WebPageScheme webPageScheme;
  final bool webAskDownloadLocation;
  final String webDownloadFolder;
  final WebPopupDefault webPopupDefault;
  final WebAutoClearInterval webAutoClearDays;
  final WebAutoClearTiming webAutoClearTiming;
  final UpdateCheckFrequency updateCheckFrequency;

  /// Every preference as it stands right now.
  static _Preferences snapshot() {
    final SettingsService s = SettingsService.instance;
    return _Preferences(
      titleBarMode: s.titleBarMode.value,
      resumeMode: s.resumeMode.value,
      folderAutoloadMode: s.folderAutoloadMode.value,
      autoEq: s.autoEq.value,
      mouseOverPreview: s.mouseOverPreview.value,
      remoteEnabled: s.remoteEnabled.value,
      remoteFileAccess: s.remoteFileAccess.value,
      subtitleLanguage: s.subtitleLanguage.value,
      subtitleAutoDownload: s.subtitleAutoDownload.value,
      webSearchSuggestions: s.webSearchSuggestions.value,
      webPageScheme: s.webPageScheme.value,
      webAskDownloadLocation: s.webAskDownloadLocation.value,
      webDownloadFolder: s.webDownloadFolder.value,
      webPopupDefault: s.webPopupDefault.value,
      webAutoClearDays: s.webAutoClearDays.value,
      webAutoClearTiming: s.webAutoClearTiming.value,
      updateCheckFrequency: s.updateCheckFrequency.value,
    );
  }

  /// The factory answer to every one of them — the same values each
  /// group's mark and each pill set's `Default · …` line names.
  static const _Preferences defaults = _Preferences(
    titleBarMode: TitleBarMode.borderless,
    resumeMode: ResumeMode.all,
    folderAutoloadMode: FolderAutoloadMode.allVideos,
    autoEq: false,
    mouseOverPreview: false,
    remoteEnabled: true,
    remoteFileAccess: true,
    subtitleLanguage: SettingsService.defaultSubtitleLanguage,
    subtitleAutoDownload: true,
    webSearchSuggestions: true,
    webPageScheme: WebPageScheme.light,
    webAskDownloadLocation: true,
    webDownloadFolder: '',
    webPopupDefault: WebPopupDefault.block,
    webAutoClearDays: WebAutoClearInterval.off,
    webAutoClearTiming: WebAutoClearTiming.onOpen,
    updateCheckFrequency: UpdateCheckFrequency.weekly,
  );

  /// The notifiers a live read depends on.
  static List<Listenable> listenables() {
    final SettingsService s = SettingsService.instance;
    return <Listenable>[
      s.titleBarMode,
      s.resumeMode,
      s.folderAutoloadMode,
      s.autoEq,
      s.mouseOverPreview,
      s.remoteEnabled,
      s.remoteFileAccess,
      s.subtitleLanguage,
      s.subtitleAutoDownload,
      s.webSearchSuggestions,
      s.webPageScheme,
      s.webAskDownloadLocation,
      s.webDownloadFolder,
      s.webPopupDefault,
      s.webAutoClearDays,
      s.webAutoClearTiming,
      s.updateCheckFrequency,
    ];
  }

  /// True while every preference stands on its factory value — the state
  /// in which no reset mark is drawn anywhere.
  bool get isDefault =>
      titleBarMode == defaults.titleBarMode &&
      resumeMode == defaults.resumeMode &&
      folderAutoloadMode == defaults.folderAutoloadMode &&
      autoEq == defaults.autoEq &&
      mouseOverPreview == defaults.mouseOverPreview &&
      remoteEnabled == defaults.remoteEnabled &&
      remoteFileAccess == defaults.remoteFileAccess &&
      subtitleLanguage == defaults.subtitleLanguage &&
      subtitleAutoDownload == defaults.subtitleAutoDownload &&
      webSearchSuggestions == defaults.webSearchSuggestions &&
      webPageScheme == defaults.webPageScheme &&
      webAskDownloadLocation == defaults.webAskDownloadLocation &&
      webDownloadFolder == defaults.webDownloadFolder &&
      webPopupDefault == defaults.webPopupDefault &&
      webAutoClearDays == defaults.webAutoClearDays &&
      webAutoClearTiming == defaults.webAutoClearTiming &&
      updateCheckFrequency == defaults.updateCheckFrequency;

  /// Writes this set into the settings service — every value through the
  /// same setter its own control uses, so side effects (the remote
  /// listener starting or stopping, say) happen exactly as on a tap.
  void apply() {
    final SettingsService s = SettingsService.instance;
    unawaited(s.setTitleBarMode(titleBarMode));
    unawaited(s.setResumeMode(resumeMode));
    unawaited(s.setFolderAutoloadMode(folderAutoloadMode));
    unawaited(s.setAutoEq(autoEq));
    unawaited(s.setMouseOverPreview(mouseOverPreview));
    unawaited(s.setRemoteEnabled(remoteEnabled));
    unawaited(s.setRemoteFileAccess(remoteFileAccess));
    unawaited(s.setSubtitleLanguage(subtitleLanguage));
    unawaited(s.setSubtitleAutoDownload(subtitleAutoDownload));
    unawaited(s.setWebSearchSuggestions(webSearchSuggestions));
    unawaited(s.setWebPageScheme(webPageScheme));
    unawaited(s.setWebAskDownloadLocation(webAskDownloadLocation));
    unawaited(s.setWebDownloadFolder(webDownloadFolder));
    unawaited(s.setWebPopupDefault(webPopupDefault));
    unawaited(s.setWebAutoClearDays(webAutoClearDays));
    unawaited(s.setWebAutoClearTiming(webAutoClearTiming));
    unawaited(s.setUpdateCheckFrequency(updateCheckFrequency));
  }
}

/// One group: a caption, then its rows with hairlines between them. The
/// caption carries the reset mark while the group stands off its defaults.
class _Group extends StatelessWidget {
  const _Group({required this.caption, required this.rows, this.reset});

  final String caption;
  final List<Widget> rows;

  /// Null on groups that hold no preference to restore — OpenSubtitles
  /// (signed-in material, not a default) and the per-site pop-up rules.
  final _GroupReset? reset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _captionRow(),
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 10,
              endIndent: 10,
              color: AppColors.divider,
            ),
          rows[i],
        ],
      ],
    );
  }

  /// The caption line — one fixed height whether or not the reset mark is
  /// up, so nothing in the list ever shifts under the pointer.
  Widget _captionRow() {
    final _GroupReset? reset = this.reset;
    final Widget label = Text(caption.toUpperCase(), style: _captionStyle);
    if (reset == null) {
      return Padding(
        padding: const EdgeInsets.only(left: 10),
        child: SizedBox(
          height: 20,
          child: Align(alignment: Alignment.centerLeft, child: label),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 2),
      child: SizedBox(
        height: 20,
        child: Row(
          children: <Widget>[
            label,
            const Spacer(),
            ListenableBuilder(
              listenable: Listenable.merge(reset.sources),
              builder: (BuildContext context, Widget? _) => reset.isModified()
                  ? _MarkButton(
                      icon: Icons.restart_alt,
                      tooltip: 'Reset $caption to defaults',
                      size: 18,
                      iconSize: 12,
                      onPressed: reset.onReset,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// One setting, one line: label · value · control.
///
/// The row is the whole hit target when it leads somewhere ([onTap]);
/// otherwise it is a plain line with a switch or a pill set at its end.
class _Row extends StatefulWidget {
  const _Row({
    required this.label,
    this.value,
    this.valueTooltip,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.tooltip,
    this.rowKey,
  });

  final String label;

  /// The current value or state, right of the label and quiet.
  final String? value;

  /// Names the real value when the shown one had to be shortened.
  final String? valueTooltip;
  final Widget? trailing;

  /// Makes the whole row the action. Null leaves it a read-only line.
  final VoidCallback? onTap;
  final bool enabled;

  /// A hover-delay name for the row itself (never a lesson).
  final String? tooltip;

  /// Anchor for a popup that hangs under this row.
  final Key? rowKey;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool live = widget.onTap != null && widget.enabled;
    Widget row = MouseRegion(
      key: widget.rowKey,
      cursor: live ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: live ? (_) => setState(() => _hovered = true) : null,
      onExit: live ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: live ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? _rowHover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle.copyWith(
                      color: widget.enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (widget.value != null) ...<Widget>[
                  const SizedBox(width: 12),
                  _ValueText(
                    text: widget.value!,
                    tooltip: widget.valueTooltip,
                  ),
                ],
                if (widget.trailing != null) ...<Widget>[
                  const SizedBox(width: 10),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      row = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 400),
        child: row,
      );
    }
    return row;
  }
}

/// A row's value text — right-aligned, ellipsized, capped so a long path
/// can never squeeze the label off the line.
class _ValueText extends StatelessWidget {
  const _ValueText({required this.text, this.tooltip});

  final String text;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget label = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: _valueStyle,
      ),
    );
    if (tooltip == null) return label;
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 400),
      child: label,
    );
  }
}

/// A pill set — the one control for "pick one of three or four". One
/// hairline capsule, one tinted pill for the answer in force, instant
/// apply on click.
class _PillPicker<T> extends StatelessWidget {
  const _PillPicker({
    required this.options,
    required this.value,
    required this.onSelect,
    this.defaultValue,
  });

  /// `hint`, when given, is the pill's hover-delay tooltip.
  final List<({T value, String label, String? hint})> options;
  final T value;
  final ValueChanged<T> onSelect;

  /// The factory default. When given, the set wears one quiet line under
  /// it — `Default · Borderless` — so the answer needs no legend.
  final T? defaultValue;

  @override
  Widget build(BuildContext context) {
    final Widget capsule = _capsule();
    final T? fallback = defaultValue;
    if (fallback == null) return capsule;
    String? fallbackLabel;
    for (final ({T value, String label, String? hint}) option in options) {
      if (option.value == fallback) {
        fallbackLabel = option.label;
        break;
      }
    }
    if (fallbackLabel == null) return capsule;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        capsule,
        const SizedBox(height: 2),
        Text('Default · $fallbackLabel', style: _defaultCaptionStyle),
      ],
    );
  }

  Widget _capsule() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.surfaceOutline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final option in options)
            _Pill(
              label: option.label,
              hint: option.hint,
              selected: option.value == value,
              onTap: () => onSelect(option.value),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    Widget pill = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? _pillFill
                : (_hovered ? _rowHover : Colors.transparent),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 0.2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? AppColors.accent
                  : (_hovered ? AppColors.textPrimary : AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
    if (widget.hint != null) {
      pill = Tooltip(
        message: widget.hint!,
        waitDuration: const Duration(milliseconds: 400),
        child: pill,
      );
    }
    return pill;
  }
}

/// The one action mark the list uses (clear, reset, open, remove, check).
///
/// It is [SaluIconButton] — the app's single icon recipe — at the
/// dialog's smaller hit sizes: the mark itself lights and scales, nothing
/// is ever drawn behind it, and a hover-delay tooltip names it (follow.md
/// rules 4 and 6). The old wash-under-a-box button is gone.
class _MarkButton extends StatelessWidget {
  const _MarkButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 26,
    this.iconSize = 15,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SaluIconButton(
      size: size,
      tooltip: tooltip,
      onTap: onPressed,
      child: Icon(icon, size: iconSize),
    );
  }
}

/// The master reset — the tab strip's right-hand mark (owner ruling,
/// 2026-09-28).
///
/// It is the same control as a group's mark, one level up: silent while
/// every preference sits on its factory value, and one press puts the
/// whole window back with the house Undo toast behind it (follow.md
/// rule 3 — instant, never a confirm dialog). Its slot in the strip is
/// reserved even when it is hidden, so the tabs never shift.
class _MasterResetButton extends StatelessWidget {
  const _MasterResetButton();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(_Preferences.listenables()),
      builder: (BuildContext context, Widget? _) {
        if (_Preferences.snapshot().isDefault) {
          return const SizedBox(width: 26, height: 26);
        }
        return _MarkButton(
          icon: Icons.restart_alt,
          tooltip: 'Reset all settings',
          onPressed: _Defaults.everything,
        );
      },
    );
  }
}

/// The one chevron a row leads with when it opens something.
class _RowChevron extends StatelessWidget {
  const _RowChevron({this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right,
      size: 16,
      color: enabled ? AppColors.textSecondary : AppColors.divider,
    );
  }
}

/// The tabs' scrolling host. SALU never draws a scrollbar in a dialog:
/// the compact metrics are sized so the fallback is never seen, and if a
/// tiny window does force it, it stays silent (owner ruling 2026-09-28).
class _QuietScroll extends StatelessWidget {
  const _QuietScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: child,
    );
  }
}

/// The body of every tab: one quiet column with the shared gutter.
class _TabBody extends StatelessWidget {
  const _TabBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _QuietScroll(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// The air between two groups.
const SizedBox _groupGap = SizedBox(height: 10);

// ── Factory defaults (enhancement 3, owner 2026-09-28) ─────────────────────

/// The factory defaults in one place, and the reset that puts a group back
/// on them. A reset applies **instantly** and leaves the house Undo toast
/// behind — never a confirm dialog (follow.md rule 3).
///
/// Only real preferences are listed. Stored data and credentials are not
/// settings: EQ memory keeps its own row and its own undo (§5), and the
/// OpenSubtitles fields are signed-in material, not a default to restore.
class _Defaults {
  _Defaults._();

  static SettingsService get _s => SettingsService.instance;

  static void _undo(String label, VoidCallback restore) {
    OsdController.instance.show(OsdUndoCard(label: label, onUndo: restore));
  }

  /// The master reset — the tab strip's mark (owner ruling, 2026-09-28).
  /// One press puts every preference back and one Undo returns the whole
  /// set exactly as it stood; data and credentials are never in scope.
  static void everything() {
    final _Preferences before = _Preferences.snapshot();
    if (before.isDefault) return;
    _Preferences.defaults.apply();
    _undo('Settings reset', before.apply);
  }

  static void topBar() {
    final SettingsService s = _s;
    final TitleBarMode previous = s.titleBarMode.value;
    if (previous == TitleBarMode.borderless) return;
    unawaited(s.setTitleBarMode(TitleBarMode.borderless));
    _undo('Top bar reset', () => unawaited(s.setTitleBarMode(previous)));
  }

  static void playback() {
    final SettingsService s = _s;
    final ResumeMode resume = s.resumeMode.value;
    final FolderAutoloadMode load = s.folderAutoloadMode.value;
    if (resume == ResumeMode.all && load == FolderAutoloadMode.allVideos) {
      return;
    }
    unawaited(s.setResumeMode(ResumeMode.all));
    unawaited(s.setFolderAutoloadMode(FolderAutoloadMode.allVideos));
    _undo('Playback reset', () {
      unawaited(s.setResumeMode(resume));
      unawaited(s.setFolderAutoloadMode(load));
    });
  }

  static void equalizer() {
    final SettingsService s = _s;
    final bool eq = s.autoEq.value;
    final bool preview = s.mouseOverPreview.value;
    if (!eq && !preview) return;
    unawaited(s.setAutoEq(false));
    unawaited(s.setMouseOverPreview(false));
    _undo('Equalizer reset', () {
      unawaited(s.setAutoEq(eq));
      unawaited(s.setMouseOverPreview(preview));
    });
  }

  static void remote() {
    final SettingsService s = _s;
    final bool control = s.remoteEnabled.value;
    final bool files = s.remoteFileAccess.value;
    if (control && files) return;
    unawaited(s.setRemoteEnabled(true));
    unawaited(s.setRemoteFileAccess(true));
    _undo('Remote reset', () {
      unawaited(s.setRemoteEnabled(control));
      unawaited(s.setRemoteFileAccess(files));
    });
  }

  static void language() {
    final SettingsService s = _s;
    final String previous = s.subtitleLanguage.value;
    if (previous == SettingsService.defaultSubtitleLanguage) return;
    unawaited(s.setSubtitleLanguage(SettingsService.defaultSubtitleLanguage));
    _undo('Language reset', () => unawaited(s.setSubtitleLanguage(previous)));
  }

  static void autoDownload() {
    final SettingsService s = _s;
    final bool previous = s.subtitleAutoDownload.value;
    if (previous) return;
    unawaited(s.setSubtitleAutoDownload(true));
    _undo('Auto-download reset',
        () => unawaited(s.setSubtitleAutoDownload(previous)));
  }

  static void addressBar() {
    final SettingsService s = _s;
    final bool previous = s.webSearchSuggestions.value;
    if (previous) return;
    unawaited(s.setWebSearchSuggestions(true));
    _undo('Address bar reset',
        () => unawaited(s.setWebSearchSuggestions(previous)));
  }

  static void pageColours() {
    final SettingsService s = _s;
    final WebPageScheme previous = s.webPageScheme.value;
    if (previous == WebPageScheme.light) return;
    unawaited(s.setWebPageScheme(WebPageScheme.light));
    _undo('Page colours reset', () => unawaited(s.setWebPageScheme(previous)));
  }

  static void downloads() {
    final SettingsService s = _s;
    final bool ask = s.webAskDownloadLocation.value;
    final String folder = s.webDownloadFolder.value;
    if (ask && folder.trim().isEmpty) return;
    unawaited(s.setWebAskDownloadLocation(true));
    unawaited(s.setWebDownloadFolder(''));
    _undo('Downloads reset', () {
      unawaited(s.setWebAskDownloadLocation(ask));
      unawaited(s.setWebDownloadFolder(folder));
    });
  }

  static void popups() {
    final SettingsService s = _s;
    final WebPopupDefault previous = s.webPopupDefault.value;
    if (previous == WebPopupDefault.block) return;
    unawaited(s.setWebPopupDefault(WebPopupDefault.block));
    _undo('Pop-ups reset', () => unawaited(s.setWebPopupDefault(previous)));
  }

  static void autoClear() {
    final SettingsService s = _s;
    final WebAutoClearInterval previous = s.webAutoClearDays.value;
    if (previous == WebAutoClearInterval.off) return;
    unawaited(s.setWebAutoClearDays(WebAutoClearInterval.off));
    _undo('Auto-clear reset',
        () => unawaited(s.setWebAutoClearDays(previous)));
  }

  static void autoClearTiming() {
    final SettingsService s = _s;
    final WebAutoClearTiming previous = s.webAutoClearTiming.value;
    if (previous == WebAutoClearTiming.onOpen) return;
    unawaited(s.setWebAutoClearTiming(WebAutoClearTiming.onOpen));
    _undo('Sweep timing reset',
        () => unawaited(s.setWebAutoClearTiming(previous)));
  }

  static void updates() {
    final SettingsService s = _s;
    final UpdateCheckFrequency previous = s.updateCheckFrequency.value;
    if (previous == UpdateCheckFrequency.weekly) return;
    unawaited(s.setUpdateCheckFrequency(UpdateCheckFrequency.weekly));
    _undo('Updates reset',
        () => unawaited(s.setUpdateCheckFrequency(previous)));
  }
}

// ── General tab ────────────────────────────────────────────────────────────

class _GeneralTab extends StatelessWidget {
  const _GeneralTab({this.onOpenRemote});

  final VoidCallback? onOpenRemote;

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;
    return _TabBody(
      children: <Widget>[
        _Group(
          caption: 'Top bar',
          reset: _GroupReset(
            sources: <Listenable>[settings.titleBarMode],
            isModified: () =>
                settings.titleBarMode.value != TitleBarMode.borderless,
            onReset: _Defaults.topBar,
          ),
          rows: const <Widget>[_TitleBarModeRow()],
        ),
        _groupGap,
        _Group(
          caption: 'Playback',
          reset: _GroupReset(
            sources: <Listenable>[
              settings.resumeMode,
              settings.folderAutoloadMode,
            ],
            isModified: () =>
                settings.resumeMode.value != ResumeMode.all ||
                settings.folderAutoloadMode.value !=
                    FolderAutoloadMode.allVideos,
            onReset: _Defaults.playback,
          ),
          rows: const <Widget>[_ResumeModeRow(), _FolderAutoloadRow()],
        ),
        _groupGap,
        _Group(
          caption: 'Equalizer',
          reset: _GroupReset(
            sources: <Listenable>[
              settings.autoEq,
              settings.mouseOverPreview,
            ],
            isModified: () =>
                settings.autoEq.value || settings.mouseOverPreview.value,
            onReset: _Defaults.equalizer,
          ),
          rows: const <Widget>[
            _AutoEqRow(),
            _MouseOverPreviewRow(),
            _ClearEqMemoryRow(),
          ],
        ),
        _groupGap,
        _RemoteGroup(onOpenRemote: onOpenRemote),
      ],
    );
  }
}

/// The "Top bar" group — how the invisible chrome behaves.
class _TitleBarModeRow extends StatelessWidget {
  const _TitleBarModeRow();

  static const List<({TitleBarMode value, String label, String? hint})>
      _options = <({TitleBarMode value, String label, String? hint})>[
    (
      value: TitleBarMode.borderless,
      label: 'Borderless',
      hint: 'Hides 3 s after the pointer stops.',
    ),
    (
      value: TitleBarMode.pinWhenPlaybackOff,
      label: 'Pin (playback off)',
      hint: 'Stays visible while nothing is playing.',
    ),
    (
      value: TitleBarMode.locked,
      label: 'Locked',
      hint: 'Always visible.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TitleBarMode>(
      valueListenable: SettingsService.instance.titleBarMode,
      builder: (BuildContext context, TitleBarMode mode, Widget? _) => _Row(
        label: 'Behaviour',
        trailing: _PillPicker<TitleBarMode>(
          options: _options,
          value: mode,
          defaultValue: TitleBarMode.borderless,
          onSelect: (TitleBarMode picked) =>
              SettingsService.instance.setTitleBarMode(picked),
        ),
      ),
    );
  }
}

/// The "Resume" row — which files continue from where you stopped.
class _ResumeModeRow extends StatelessWidget {
  const _ResumeModeRow();

  static const List<({ResumeMode value, String label, String? hint})>
      _options = <({ResumeMode value, String label, String? hint})>[
    (
      value: ResumeMode.all,
      label: 'All files',
      hint: 'Video and audio pick up where they stopped.',
    ),
    (
      value: ResumeMode.videoOnly,
      label: 'Video only',
      hint: 'Audio starts from the beginning.',
    ),
    (
      value: ResumeMode.audioOnly,
      label: 'Audio only',
      hint: 'Video starts from the beginning.',
    ),
    (
      value: ResumeMode.off,
      label: 'Off',
      hint: 'Everything starts from the beginning.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ResumeMode>(
      valueListenable: SettingsService.instance.resumeMode,
      builder: (BuildContext context, ResumeMode mode, Widget? _) => _Row(
        label: 'Resume',
        trailing: _PillPicker<ResumeMode>(
          options: _options,
          value: mode,
          defaultValue: ResumeMode.all,
          onSelect: (ResumeMode picked) =>
              SettingsService.instance.setResumeMode(picked),
        ),
      ),
    );
  }
}

/// The "Folder auto-load" row (autoload_imp.md §5) — what happens when
/// exactly one local media file is loaded. Applies from the next load;
/// the live queue is never retrofitted.
class _FolderAutoloadRow extends StatelessWidget {
  const _FolderAutoloadRow();

  static const List<({FolderAutoloadMode value, String label, String? hint})>
      _options = <({FolderAutoloadMode value, String label, String? hint})>[
    (
      value: FolderAutoloadMode.allVideos,
      label: 'All videos',
      hint: 'The whole folder is queued, starting at the file you opened.',
    ),
    (
      value: FolderAutoloadMode.sameSeries,
      label: 'Same series',
      hint: 'Only files named like the picked one.',
    ),
    (
      value: FolderAutoloadMode.off,
      label: 'Off',
      hint: 'Only the picked file is loaded.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FolderAutoloadMode>(
      valueListenable: SettingsService.instance.folderAutoloadMode,
      builder: (BuildContext context, FolderAutoloadMode mode, Widget? _) =>
          _Row(
        label: 'Auto-load folder',
        trailing: _PillPicker<FolderAutoloadMode>(
          options: _options,
          value: mode,
          defaultValue: FolderAutoloadMode.allVideos,
          onSelect: (FolderAutoloadMode picked) =>
              SettingsService.instance.setFolderAutoloadMode(picked),
        ),
      ),
    );
  }
}

/// Auto EQ (§5) — one switch, default Off. On, SALU picks a preset at
/// file load from the file's own facts and learns from what you keep.
/// Off, nothing is guessed — and switching it off leaves the current
/// settings exactly as they are (§5's safety rule).
class _AutoEqRow extends StatelessWidget {
  const _AutoEqRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.autoEq,
      builder: (BuildContext context, bool on, Widget? _) => _Row(
        label: 'Auto EQ',
        tooltip: 'Picks a starting sound when a file loads, and learns from '
            'what you keep.',
        onTap: () => SettingsService.instance.setAutoEq(!on),
        trailing: _SaluSwitch(on: on),
      ),
    );
  }
}

/// **Mouse over preview** — the Equalizer group's second switch (owner,
/// 2026-09-14). It decides whether a pointer that merely RESTS on a Tune
/// control previews the value under it (eq_imp.md §8's hover recipe) or
/// only lights the control up.
///
/// Default **Off**. Off, the panel moves on a press or a drag and on
/// nothing else, so a pointer crossing the window on its way somewhere
/// can never change the sound or the picture; the value already in force
/// is untouched either way.
class _MouseOverPreviewRow extends StatelessWidget {
  const _MouseOverPreviewRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.mouseOverPreview,
      builder: (BuildContext context, bool on, Widget? _) => _Row(
        label: 'Mouse over preview',
        tooltip: 'Previews the value a resting pointer is on. Off, a click '
            'or a drag is what moves it.',
        onTap: () => SettingsService.instance.setMouseOverPreview(!on),
        trailing: _SaluSwitch(on: on),
      ),
    );
  }
}

/// The learning map's one control (§5's data policy): a row that names how
/// much SALU remembers and wipes it in a tap. No confirm dialog — the
/// house answer is the 5-second Undo toast on the deck, which restores the
/// exact snapshot. The mark is quiet when there is nothing to clear.
class _ClearEqMemoryRow extends StatelessWidget {
  const _ClearEqMemoryRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      // Any notifier on the service wakes this row; the map itself is a
      // plain object, and its size changes only alongside real tune state
      // writes.
      valueListenable: TuneService.instance.autoPick,
      builder: (BuildContext context, String? picked, Widget? _) {
        final TuneService tune = TuneService.instance;
        final int count = tune.memory.length;
        final bool enabled = count > 0;
        return _Row(
          label: 'EQ memory',
          value: enabled ? '$count saved' : 'Empty',
          enabled: enabled,
          trailing: _MarkButton(
            icon: Icons.delete_outline,
            tooltip: enabled ? 'Clear EQ memory' : 'Nothing to clear',
            onPressed: () {
              if (!enabled) return;
              final Map<String, EqMemoryEntry> previous = tune.clearMemory();
              OsdController.instance.show(OsdUndoCard(
                label: 'EQ memory cleared',
                onUndo: () => tune.restoreMemory(previous),
              ));
            },
          ),
        );
      },
    );
  }
}

/// App-wide PC-side remote controls. The listener itself lives in
/// RemoteService; these rows are deliberately in General so the off switch
/// remains reachable from both Player and Web mode.
class _RemoteGroup extends StatelessWidget {
  const _RemoteGroup({this.onOpenRemote});

  final VoidCallback? onOpenRemote;

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;
    return _Group(
      caption: 'Remote',
      reset: _GroupReset(
        sources: <Listenable>[
          settings.remoteEnabled,
          settings.remoteFileAccess,
        ],
        isModified: () =>
            !settings.remoteEnabled.value || !settings.remoteFileAccess.value,
        onReset: _Defaults.remote,
      ),
      rows: <Widget>[
        const _RemoteControlRow(),
        const _RemoteFileRow(),
        _RemotePairingRow(onOpen: () {
          Navigator.of(context).pop();
          onOpenRemote?.call();
        }),
        _RemotePhonesRow(onOpen: () {
          Navigator.of(context).pop();
          onOpenRemote?.call();
        }),
      ],
    );
  }
}

class _RemoteControlRow extends StatelessWidget {
  const _RemoteControlRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.remoteEnabled,
      builder: (BuildContext context, bool on, Widget? _) => _Row(
        label: 'Remote control',
        tooltip: 'Local network only.',
        onTap: () {
          SettingsService.instance.setRemoteEnabled(!on);
          // Remote.md §8.3 (amended 2026-09-21): the firewall ask belongs
          // to this moment. A blocked phone-call never reaches the PC, so
          // SALU could never know to ask later — the toggle is the
          // trigger.
          if (!on) unawaited(maybePromptRemoteFirewall(context));
        },
        trailing: _SaluSwitch(on: on),
      ),
    );
  }
}

class _RemoteFileRow extends StatelessWidget {
  const _RemoteFileRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.remoteFileAccess,
      builder: (BuildContext context, bool on, Widget? _) => _Row(
        label: 'Phone file access',
        tooltip: 'Read-only. Folders and media names only.',
        onTap: () => SettingsService.instance.setRemoteFileAccess(!on),
        trailing: _SaluSwitch(on: on),
      ),
    );
  }
}

class _RemotePairingRow extends StatelessWidget {
  const _RemotePairingRow({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.remoteEnabled,
      builder: (BuildContext context, bool enabled, Widget? _) => _Row(
        label: 'Pairing code',
        tooltip: enabled ? null : 'Turn remote control on to pair a phone.',
        enabled: enabled,
        onTap: enabled ? onOpen : null,
        trailing: _RowChevron(enabled: enabled),
      ),
    );
  }
}

class _RemotePhonesRow extends StatelessWidget {
  const _RemotePhonesRow({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RemoteDevice>>(
      valueListenable: RemoteService.instance.devices,
      builder: (BuildContext context, List<RemoteDevice> devices, Widget? _) =>
          _Row(
        label: 'Remembered phones',
        value: '${devices.length}',
        onTap: onOpen,
        trailing: const _RowChevron(),
      ),
    );
  }
}

// ── Updates tab (updater.md) ──────────────────────────────────────────────

/// The component & engine updater's settings (updater.md §7): the check
/// cadence (Off / Daily / Weekly / Monthly — Weekly is the factory
/// default), the check-now door, and where the last round stands.
class _UpdatesTab extends StatelessWidget {
  const _UpdatesTab();

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;
    return _TabBody(
      children: <Widget>[
        _Group(
          caption: 'Updates',
          reset: _GroupReset(
            sources: <Listenable>[settings.updateCheckFrequency],
            isModified: () =>
                settings.updateCheckFrequency.value !=
                UpdateCheckFrequency.weekly,
            onReset: _Defaults.updates,
          ),
          rows: const <Widget>[
            _UpdateFrequencyRow(),
            _CheckNowRow(),
            _LastCheckedRow(),
          ],
        ),
      ],
    );
  }
}

/// Automatic update check frequency — one pill set, Weekly default.
class _UpdateFrequencyRow extends StatelessWidget {
  const _UpdateFrequencyRow();

  static const List<
      ({UpdateCheckFrequency value, String label, String? hint})> _options = <
      ({UpdateCheckFrequency value, String label, String? hint})>[
    (
      value: UpdateCheckFrequency.off,
      label: 'Off',
      hint: 'Only checks when you ask.',
    ),
    (
      value: UpdateCheckFrequency.daily,
      label: 'Daily',
      hint: 'Checks once every 24 hours.',
    ),
    (
      value: UpdateCheckFrequency.weekly,
      label: 'Weekly',
      hint: 'Checks once every 7 days.',
    ),
    (
      value: UpdateCheckFrequency.monthly,
      label: 'Monthly',
      hint: 'Checks once every 30 days.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateCheckFrequency>(
      valueListenable: SettingsService.instance.updateCheckFrequency,
      builder: (BuildContext context, UpdateCheckFrequency mode, Widget? _) =>
          _Row(
        label: 'Check for updates',
        trailing: _PillPicker<UpdateCheckFrequency>(
          options: _options,
          value: mode,
          defaultValue: UpdateCheckFrequency.weekly,
          onSelect: (UpdateCheckFrequency picked) => SettingsService.instance
              .setUpdateCheckFrequency(picked),
        ),
      ),
    );
  }
}

/// The "Check now" door (updater.md §7) — the modal, and where the
/// component set stands right now beside it.
class _CheckNowRow extends StatelessWidget {
  const _CheckNowRow();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        UpdaterService.instance.updateAvailable,
        SettingsService.instance.lastUpdateCheckTime,
      ]),
      builder: (BuildContext context, Widget? _) {
        final UpdaterService updater = UpdaterService.instance;
        final String status = updater.stagedReady
            ? 'Update ready'
            : (updater.updateAvailable.value
                ? 'Update available'
                : (SettingsService.instance.lastUpdateCheckTime.value > 0
                    ? 'Up to date'
                    : ''));
        final bool loud = status == 'Update ready' || status == 'Update available';
        return _Row(
          label: 'Check now',
          onTap: () => showUpdateDialog(context),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (status.isNotEmpty)
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 0.2,
                    color: loud ? AppColors.accent : AppColors.textSecondary,
                  ),
                ),
              const SizedBox(width: 8),
              _MarkButton(
                icon: Icons.refresh,
                tooltip: 'Check now',
                onPressed: () => showUpdateDialog(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Last checked: …" (updater.md §7's timestamp, stored in
/// `shared_preferences`) — moves only when a check round succeeds.
class _LastCheckedRow extends StatelessWidget {
  const _LastCheckedRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SettingsService.instance.lastUpdateCheckTime,
      builder: (BuildContext context, int stamp, Widget? _) {
        final String when = stamp > 0
            ? formatLastChecked(
                DateTime.now(), DateTime.fromMillisecondsSinceEpoch(stamp))
            : 'Never';
        return _Row(label: 'Last checked', value: when);
      },
    );
  }
}

// ── Web tab (web.md) ───────────────────────────────────────────────────────

/// The browser's settings, and only the browser's: the address bar's
/// Google leg (web.md · "controlled by a Settings 'Search suggestions'
/// toggle"), the page colour push, downloads, the pop-up default +
/// per-site exceptions (web.md · pop-ups lock, 2026-09-17 cut), and the
/// auto-clear schedule (web.md · Auto-clear — LOCKED: off by default,
/// every 7/15/30 days, at opening / closing / both). Everything else the
/// browser does is a lock, not a setting.
class _WebTab extends StatelessWidget {
  const _WebTab();

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;
    return _TabBody(
      children: <Widget>[
        _Group(
          caption: 'Address bar',
          reset: _GroupReset(
            sources: <Listenable>[settings.webSearchSuggestions],
            isModified: () => !settings.webSearchSuggestions.value,
            onReset: _Defaults.addressBar,
          ),
          rows: const <Widget>[_WebSearchSuggestionsRow()],
        ),
        _groupGap,
        _Group(
          caption: 'Page colours',
          reset: _GroupReset(
            sources: <Listenable>[settings.webPageScheme],
            isModified: () =>
                settings.webPageScheme.value != WebPageScheme.light,
            onReset: _Defaults.pageColours,
          ),
          rows: const <Widget>[_WebPageSchemeRow()],
        ),
        const SizedBox(height: 6),
        const _PageSchemeEngineNote(),
        _groupGap,
        _Group(
          caption: 'Downloads',
          reset: _GroupReset(
            sources: <Listenable>[
              settings.webAskDownloadLocation,
              settings.webDownloadFolder,
            ],
            isModified: () =>
                !settings.webAskDownloadLocation.value ||
                settings.webDownloadFolder.value.trim().isNotEmpty,
            onReset: _Defaults.downloads,
          ),
          rows: const <Widget>[
            _WebAskDownloadRow(),
            _WebDownloadFolderRow(),
          ],
        ),
        _groupGap,
        _Group(
          caption: 'Pop-ups',
          reset: _GroupReset(
            sources: <Listenable>[settings.webPopupDefault],
            isModified: () =>
                settings.webPopupDefault.value != WebPopupDefault.block,
            onReset: _Defaults.popups,
          ),
          rows: const <Widget>[_WebPopupDefaultRow()],
        ),
        const SizedBox(height: 10),
        const _WebPopupExceptions(),
        _groupGap,
        _Group(
          caption: 'Auto-clear',
          reset: _GroupReset(
            sources: <Listenable>[settings.webAutoClearDays],
            isModified: () =>
                settings.webAutoClearDays.value != WebAutoClearInterval.off,
            onReset: _Defaults.autoClear,
          ),
          rows: const <Widget>[_WebAutoClearRow()],
        ),
        const SizedBox(height: 10),
        const _WebAutoClearTimingRow(),
        const SizedBox(height: 14),
        const _WebEngineFooter(),
      ],
    );
  }
}

/// The Google leg of the address bar. Off, the dropdown still answers —
/// it just only knows the user's own pages (history + favourites).
class _WebSearchSuggestionsRow extends StatelessWidget {
  const _WebSearchSuggestionsRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.webSearchSuggestions,
      builder: (BuildContext context, bool on, Widget? _) => _Row(
        label: 'Search suggestions',
        tooltip: 'While you type, Google offers — merged under your own pages.',
        onTap: () => SettingsService.instance.setWebSearchSuggestions(!on),
        trailing: _SaluSwitch(on: on),
      ),
    );
  }
}

/// Page colours — what `prefers-color-scheme` answers inside the browser.
/// Light is the default so pages match Edge; "Follow Windows" is the raw
/// WebView2 behaviour (dark app mode ⇒ dark sites). Applied to the engine
/// live through its own profile colour-scheme control — pages re-theme in
/// place when a choice is picked.
class _WebPageSchemeRow extends StatelessWidget {
  const _WebPageSchemeRow();

  static const List<({WebPageScheme value, String label, String? hint})>
      _options = <({WebPageScheme value, String label, String? hint})>[
    (
      value: WebPageScheme.light,
      label: 'Light',
      hint: 'Pages look the way Edge shows them.',
    ),
    (
      value: WebPageScheme.dark,
      label: 'Dark',
      hint: 'Sites that carry a dark theme use it.',
    ),
    (
      value: WebPageScheme.system,
      label: 'Follow Windows',
      hint: 'Whatever Windows app mode says — dark PC, dark sites.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebPageScheme>(
      valueListenable: SettingsService.instance.webPageScheme,
      builder: (BuildContext context, WebPageScheme current, Widget? _) =>
          _Row(
        label: 'Sites see',
        trailing: _PillPicker<WebPageScheme>(
          options: _options,
          value: current,
          defaultValue: WebPageScheme.light,
          onSelect: (WebPageScheme picked) =>
              SettingsService.instance.setWebPageScheme(picked),
        ),
      ),
    );
  }
}

/// The honesty line under Page colours: while a colour push stands refused
/// by the engine (`WebDataControlService.pageSchemeFailed`), the row says
/// so instead of pretending. Silent the rest of the time — and it states
/// the state only; the WebView2 version at the foot of the tab names the
/// thing to update.
class _PageSchemeEngineNote extends StatelessWidget {
  const _PageSchemeEngineNote();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WebDataControlService.instance.pageSchemeFailed,
      builder: (BuildContext context, bool failed, Widget? _) {
        if (!failed) return const SizedBox.shrink();
        return const Padding(
          padding: EdgeInsets.only(left: 10, right: 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.warning_amber_outlined,
                  size: 14, color: AppColors.statusDead),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Page colours could not reach the web engine — pages '
                  'follow Windows.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
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

/// Settings → Web → Downloads: Chrome/Edge's own "Ask where to save each
/// file before downloading". **On by default** — every download opens the
/// native Windows Save As and not one byte is written until a place is
/// chosen; walking away from that dialog cancels the download outright,
/// and a cancelled download never reaches the shelf (it is not a failed
/// one, it is a refused one). Off, files go straight to the folder below
/// with no question at all. Either way the change reaches every live tab
/// at once (`WebDataControlService.applyDownloadPreferences`) — no
/// restart, and a download already travelling keeps the path it was given.
class _WebAskDownloadRow extends StatelessWidget {
  const _WebAskDownloadRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.webAskDownloadLocation,
      builder: (BuildContext context, bool on, Widget? _) => _Row(
        label: 'Ask where to save',
        tooltip: 'Off, downloads go straight to the folder below.',
        onTap: () =>
            unawaited(SettingsService.instance.setWebAskDownloadLocation(!on)),
        trailing: _SaluSwitch(on: on),
      ),
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
        return _Row(
          label: 'Location',
          value: custom ? trimmed : 'Windows Downloads',
          valueTooltip: custom ? trimmed : 'The Windows Downloads folder',
          onTap: () => unawaited(WebDownloadService.pickDownloadFolder()),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (custom)
                _MarkButton(
                  icon: Icons.restart_alt,
                  tooltip: 'Use the Windows folder',
                  onPressed: () => unawaited(
                      SettingsService.instance.setWebDownloadFolder('')),
                ),
              _MarkButton(
                icon: Icons.folder_open,
                tooltip: 'Change…',
                onPressed: () =>
                    unawaited(WebDownloadService.pickDownloadFolder()),
              ),
            ],
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
class _WebPopupDefaultRow extends StatelessWidget {
  const _WebPopupDefaultRow();

  static const List<
      ({WebPopupDefault value, String label, String? hint})> _options = <
      ({WebPopupDefault value, String label, String? hint})>[
    (
      value: WebPopupDefault.block,
      label: 'Block',
      hint: 'Sites must ask — held-back pop-ups show in the address bar.',
    ),
    (
      value: WebPopupDefault.allow,
      label: 'Allow',
      hint: 'Sites may open new tabs on their own.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebPopupDefault>(
      valueListenable: SettingsService.instance.webPopupDefault,
      builder: (BuildContext context, WebPopupDefault policy, Widget? _) =>
          _Row(
        label: 'When a site opens one',
        trailing: _PillPicker<WebPopupDefault>(
          options: _options,
          value: policy,
          defaultValue: WebPopupDefault.block,
          onSelect: (WebPopupDefault picked) =>
              SettingsService.instance.setWebPopupDefault(picked),
        ),
      ),
    );
  }
}

/// The per-site pop-up rules, made in the padlock panel (Chrome's Allowed
/// / Blocked lists). Removing one hands the site back to the default.
/// With no rules at all the whole group — caption included — is gone: an
/// empty list is not a state SALU narrates (follow.md rule 1).
class _WebPopupExceptions extends StatelessWidget {
  const _WebPopupExceptions();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<WebPopupException>>(
      valueListenable: WebPopupService.instance.exceptions,
      builder:
          (BuildContext context, List<WebPopupException> rules, Widget? _) {
        if (rules.isEmpty) return const SizedBox.shrink();
        return _Group(
          caption: 'Exceptions',
          rows: <Widget>[
            for (final WebPopupException rule in rules)
              _Row(
                label: rule.host,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _RuleTag(allow: rule.allow),
                    const SizedBox(width: 4),
                    _MarkButton(
                      icon: Icons.close,
                      tooltip: 'Remove',
                      onPressed: () =>
                          WebPopupService.instance.removeFor(rule.host),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The Allow / Block tag a per-site rule wears — a value, not an action.
class _RuleTag extends StatelessWidget {
  const _RuleTag({required this.allow});

  final bool allow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
      decoration: BoxDecoration(
        color: allow ? _pillFill : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: allow ? _pillLine : AppColors.divider),
      ),
      child: Text(
        allow ? 'Allow' : 'Block',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: allow ? AppColors.accent : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// How often the sweep runs. Off is the default and Off is silent:
/// switching it never wipes anything, and switching back resumes the
/// schedule — the same safety rule the Resume mode follows.
class _WebAutoClearRow extends StatelessWidget {
  const _WebAutoClearRow();

  static const List<
      ({WebAutoClearInterval value, String label, String? hint})> _options = <
      ({WebAutoClearInterval value, String label, String? hint})>[
    (
      value: WebAutoClearInterval.off,
      label: 'Off',
      hint: 'The browser keeps what it collected until you clear it.',
    ),
    (
      value: WebAutoClearInterval.days7,
      label: '7 days',
      hint: 'A weekly sweep of the whole browser footprint.',
    ),
    (
      value: WebAutoClearInterval.days15,
      label: '15 days',
      hint: 'Two weeks between sweeps.',
    ),
    (
      value: WebAutoClearInterval.days30,
      label: '30 days',
      hint: 'A monthly sweep.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebAutoClearInterval>(
      valueListenable: SettingsService.instance.webAutoClearDays,
      builder: (BuildContext context, WebAutoClearInterval interval,
              Widget? _) =>
          _Row(
        label: 'Clear data',
        tooltip: 'History, cookies, cached files, downloads. SALU’s own '
            'memory is never part of it.',
        trailing: _PillPicker<WebAutoClearInterval>(
          options: _options,
          value: interval,
          defaultValue: WebAutoClearInterval.off,
          onSelect: (WebAutoClearInterval picked) =>
              SettingsService.instance.setWebAutoClearDays(picked),
        ),
      ),
    );
  }
}

/// The two moments the sweep can run at — the app opening, the app
/// closing, or either. The close-time sweep is the reliable one (a locked
/// profile folder is released when the process ends). With the schedule
/// Off the row is not drawn at all: nothing to time.
class _WebAutoClearTimingRow extends StatelessWidget {
  const _WebAutoClearTimingRow();

  static const List<
      ({WebAutoClearTiming value, String label, String? hint})> _options = <
      ({WebAutoClearTiming value, String label, String? hint})>[
    (
      value: WebAutoClearTiming.onOpen,
      label: 'Opening',
      hint: 'The sweep lands at startup, before the first page.',
    ),
    (
      value: WebAutoClearTiming.onClose,
      label: 'Closing',
      hint: 'The most reliable moment — the browser is done with it.',
    ),
    (
      value: WebAutoClearTiming.both,
      label: 'Both',
      hint: 'Closing sweeps; opening sweeps if anything was missed.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebAutoClearInterval>(
      valueListenable: SettingsService.instance.webAutoClearDays,
      builder: (BuildContext context, WebAutoClearInterval interval,
          Widget? _) {
        if (interval == WebAutoClearInterval.off) {
          return const SizedBox.shrink();
        }
        final SettingsService settings = SettingsService.instance;
        return ValueListenableBuilder<WebAutoClearTiming>(
          valueListenable: settings.webAutoClearTiming,
          builder: (BuildContext context, WebAutoClearTiming timing, Widget? _) =>
              _Group(
            caption: 'When to run',
            reset: _GroupReset(
              sources: <Listenable>[settings.webAutoClearTiming],
              isModified: () =>
                  settings.webAutoClearTiming.value !=
                  WebAutoClearTiming.onOpen,
              onReset: _Defaults.autoClearTiming,
            ),
            rows: <Widget>[
              _Row(
                label: 'Sweep',
                trailing: _PillPicker<WebAutoClearTiming>(
                  options: _options,
                  value: timing,
                  defaultValue: WebAutoClearTiming.onOpen,
                  onSelect: (WebAutoClearTiming picked) => SettingsService
                      .instance
                      .setWebAutoClearTiming(picked),
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
        return Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text(label, style: _valueStyle),
        );
      },
    );
  }
}

// ── Subtitles tab (cc.md §2 · D2 · D5 · D13) ─────────────────────────────

/// Three groups: **OpenSubtitles** (API key with eye + clear; the
/// username + password pair — all three persisted, the password scrambled
/// per D13 amended 2026-09-13), **Language** (the preferred-language
/// row — label + current value + chevron), **Auto-download** (a switch
/// row in the same line).
class _SubtitlesTab extends StatelessWidget {
  const _SubtitlesTab();

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;
    return _TabBody(
      children: <Widget>[
        // §2.1 — account + search fields. No reset mark: signed-in
        // material is not a factory default (owner ruling, 2026-09-28).
        const _Group(
          caption: 'OpenSubtitles',
          rows: <Widget>[_CredentialFields()],
        ),
        _groupGap,
        // §2.2 — the preferred language (single selector).
        _Group(
          caption: 'Language',
          reset: _GroupReset(
            sources: <Listenable>[settings.subtitleLanguage],
            isModified: () =>
                settings.subtitleLanguage.value !=
                SettingsService.defaultSubtitleLanguage,
            onReset: _Defaults.language,
          ),
          rows: const <Widget>[_LanguageSelector()],
        ),
        _groupGap,
        // §2.3 — the auto-download toggle.
        _Group(
          caption: 'Auto-download',
          reset: _GroupReset(
            sources: <Listenable>[settings.subtitleAutoDownload],
            isModified: () => !settings.subtitleAutoDownload.value,
            onReset: _Defaults.autoDownload,
          ),
          rows: const <Widget>[_AutoDownloadRow()],
        ),
      ],
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
    return Padding(
      // The fields are the one group that is not one-line rows: title
      // over field, at the group's own gutter.
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SecretField(
            controller: _apiKey,
            title: 'API key',
            obscured: _keyObscured,
            onToggleObscure: () =>
                setState(() => _keyObscured = !_keyObscured),
            onChanged: (String v) =>
                SettingsService.instance.setSubtitleApiKey(v),
          ),
          const SizedBox(height: 10),
          _PlainField(
            controller: _username,
            title: 'Username',
            onChanged: (String v) =>
                SettingsService.instance.setSubtitleUsername(v),
          ),
          const SizedBox(height: 10),
          _SecretField(
            controller: _password,
            title: 'Password',
            obscured: _passObscured,
            onToggleObscure: () =>
                setState(() => _passObscured = !_passObscured),
            onChanged: (String v) =>
                SettingsService.instance.setSubtitlePassword(v),
          ),
        ],
      ),
    );
  }
}

/// One titled secret field with the eye toggle and clear ×.
class _SecretField extends StatelessWidget {
  const _SecretField({
    required this.controller,
    required this.title,
    required this.obscured,
    required this.onToggleObscure,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String title;
  final bool obscured;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: _fieldTitleStyle),
        const SizedBox(height: 5),
        _FieldShell(
          controller: controller,
          obscureText: obscured,
          onChanged: onChanged,
          trailing: <Widget>[
            _MarkButton(
              icon: obscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              tooltip: obscured ? 'Show' : 'Hide',
              size: 22,
              iconSize: 14,
              onPressed: onToggleObscure,
            ),
            // §2.1: the × exists only while the field holds something.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (BuildContext context, TextEditingValue v, Widget? _) {
                if (v.text.isEmpty) return const SizedBox.shrink();
                return _MarkButton(
                  icon: Icons.close,
                  tooltip: 'Clear',
                  size: 22,
                  iconSize: 14,
                  onPressed: () {
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
/// minus the eye/clear row (the username's shape).
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
        Text(title, style: _fieldTitleStyle),
        const SizedBox(height: 5),
        _FieldShell(controller: controller, onChanged: onChanged),
      ],
    );
  }
}

/// A field's name — smaller than a row label; the field below carries the
/// value.
const TextStyle _fieldTitleStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: AppColors.textSecondary,
  letterSpacing: 0.2,
);

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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              style: const TextStyle(
                fontSize: 13,
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
            const SizedBox(width: 6),
            ...trailing,
          ],
        ],
      ),
    );
  }
}

/// §2.2 — the preferred-language row. Tapping opens the anchored pill
/// with the curated list (English → Bahasa, more later per cc.md), tick
/// on the current one.
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
        return _Row(
          label: 'Preferred language',
          value: name,
          rowKey: _anchorKey,
          onTap: _toggle,
          trailing: const _RowChevron(),
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
          height: 30,
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

/// §2.3 — the Auto-download switch row.
class _AutoDownloadRow extends StatelessWidget {
  const _AutoDownloadRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.instance.subtitleAutoDownload,
      builder: (BuildContext context, bool on, Widget? _) => _Row(
        label: 'Auto-download',
        tooltip: 'Fetches the best match when a video has no subtitles.',
        onTap: () => SettingsService.instance.setSubtitleAutoDownload(!on),
        trailing: _SaluSwitch(on: on),
      ),
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

// ── Shared dialog building block ───────────────────────────────────────────

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
