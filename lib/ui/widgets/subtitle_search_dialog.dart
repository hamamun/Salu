import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/language_names.dart';
import '../../core/player_service.dart';
import '../../core/settings_service.dart';
import '../../core/subtitle_service.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';

/// The Search window (cc.md §6.5 · D14) — a centered glass modal over a
/// dimmed barrier, the query-search part of the Fetch design:
///
///   · one editable name field, pre-filled with the video's FULL file
///     name exactly as it is on disk (owner 2026-09-13 — nothing
///     cleaned, nothing guessed: the human judges)
///   · four marks below: **Search · Save · Save & Load · Close**
///   · results grouped: **Best matches** (top 3 in the preferred
///     language) then **All matches** (every language, the preferred
///     included) — each row a subtitle file: title + release sub-line +
///     the language's real name, single-tick pick
///   · Save → `Saved · <filename>` card (never applies); Save & Load →
///     applies now, NO card (the subs are the feedback); both close the
///     window. Nothing configured → tapping Search speaks the ONE
///     `cc not configured` card — no new dialog (§6.5 lock).
///
/// Opening it keeps the track panel alive behind (§6.2); Esc /
/// click-outside closes just this window (rule 3), exactly the Open-URL
/// dialog's motion (fade + 0.96→1.0 scale).
Future<void> showSubtitleSearchDialog(BuildContext context) async {
  ChromeLock.instance.acquire();
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierColor: const Color(0x8C000000),
      barrierDismissible: true,
      barrierLabel:
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) {
        final CurvedAnimation curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (BuildContext context, Animation<double> animation,
              Animation<double> secondaryAnimation) =>
          const SubtitleSearchDialog(),
    );
  } finally {
    ChromeLock.instance.release();
  }
}

/// The modal body — a StatefulWidget because it owns the search box,
/// the async search lifecycle, and the row pick.
class SubtitleSearchDialog extends StatefulWidget {
  const SubtitleSearchDialog({super.key});

  @override
  State<SubtitleSearchDialog> createState() =>
      _SubtitleSearchDialogState();
}

class _SubtitleSearchDialogState extends State<SubtitleSearchDialog> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  final ScrollController _results = ScrollController();

  bool _searching = false;

  /// `true` after at least one completed run — the results area is the
  /// centered spinner while waiting, this list otherwise.
  List<SubtitleResult>? _rows;
  SubtitleResult? _picked;

  /// Presentism brightline: dirty text after a pick stays searchable —
  /// but the pick is dead (saving a stale row for a new query would be
  /// a lie).
  String get _trimmedQuery => _query.text.trim();

  @override
  void initState() {
    super.initState();
    _query.text = _fullNameFor(PlayerService.instance.currentPath.value);
    _queryFocus.requestFocus();
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _results.dispose();
    super.dispose();
  }

  // ── The four actions ────────────────────────────────────────────────

  Future<void> _runSearch() async {
    if (_searching) return;
    final String q = _trimmedQuery;
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _picked = null;
      _rows = null;
    });
    // search() already returns an empty list for every nothing-to-show
    // case (not configured / paused / no hits) — non-nullable by design.
    final List<SubtitleResult> rows =
        await SubtitleService.instance.search(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _rows = rows;
    });
  }

  Future<void> _save({required bool andLoad}) async {
    final SubtitleResult? picked = _picked;
    final String? video = PlayerService.instance.currentPath.value;
    if (picked == null || video == null) return;
    // The Save trains are engine-owned; the window only waits to close.
    if (andLoad) {
      await SubtitleService.instance.saveAndLoad(picked, video);
    } else {
      await SubtitleService.instance.save(picked, video);
    }
    if (!mounted) return;
    // Close on ANY outcome (§6.5: Save & Load always closes; the mock's
    // Save does too) — a failed save already spoke its engine card or
    // stayed silent per §3.5; the window's job is done either way.
    Navigator.of(context).maybePop();
  }

  void _close() => Navigator.of(context).maybePop();

  // ── The name in the box (§6.5 · owner revision 2026-09-13: the file's
  //    own full name, untouched) ──────────────────────────────────────

  /// §6.5 — owner revision 2026-09-13: the box shows the video's **full
  /// file name exactly as it sits on disk**, extension included, nothing
  /// stripped and nothing guessed.
  ///
  /// SALU used to "clean" the name (drop the extension, turn dots into
  /// spaces, delete everything from the first release tag onwards). That
  /// cleaning was the problem: it threw the real release name — the
  /// thing OpenSubtitles indexes best — away with the junk, and a file
  /// whose title began with a tag on the list lost its title entirely.
  /// D9's whole philosophy is that a human judges, so the human gets the
  /// true name and edits it if they want to.
  static String _fullNameFor(String? path) {
    if (path == null || path.isEmpty) return '';
    return path.split(RegExp(r'[/\\]')).last;
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 470,
              constraints: const BoxConstraints(maxHeight: 428),
              decoration: BoxDecoration(
                color: const Color(0xFA252526),
                border: Border.all(color: AppColors.surfaceOutline),
                borderRadius: BorderRadius.circular(13),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 80,
                    offset: Offset(0, 30),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _nameField(),
                  _marksRow(),
                  Expanded(child: _resultsArea()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The editable movie name — pre-filled, NOT decorated with a label
  /// (rule 1 names everything by shape; the tooltip names the marks).
  Widget _nameField() {
    return TextField(
      controller: _query,
      focusNode: _queryFocus,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        height: 1.4,
      ),
      cursorColor: AppColors.textPrimary,
      cursorWidth: 1,
      onSubmitted: (_) => unawaited(_runSearch()),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0x52FFFFFF)),
        ),
      ),
    );
  }

  /// The four marks: Search · Save · Save & Load · Close (right edge).
  /// Save / Save & Load dim until a row is picked (SaluIconButton's
  /// own inert state — nothing boxed, nothing hidden).
  Widget _marksRow() {
    final bool canSearch = !_searching && _trimmedQuery.isNotEmpty;
    final bool canSave = !_searching && _picked != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
      child: Row(
        children: <Widget>[
          SaluIconButton(
            tooltip: 'Search',
            size: 30,
            enabled: canSearch,
            onTap: canSearch ? () => unawaited(_runSearch()) : () {},
            child: const MagnifierMark(size: 18),
          ),
          const SizedBox(width: 22),
          SaluIconButton(
            tooltip: 'Save',
            size: 30,
            enabled: canSave,
            onTap: canSave ? () => unawaited(_save(andLoad: false)) : () {},
            child: const SaveMark(size: 19),
          ),
          const SizedBox(width: 22),
          SaluIconButton(
            tooltip: 'Save & Load',
            size: 34,
            enabled: canSave,
            onTap: canSave ? () => unawaited(_save(andLoad: true)) : () {},
            child: const SaveLoadMark(size: 24),
          ),
          const Spacer(),
          SaluIconButton(
            tooltip: 'Close',
            size: 30,
            onTap: _close,
            child: Transform.rotate(
              angle: 0.7853982, // π/4 — the plus turns into an ×
              child: const PlusMark(size: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// The results zone: (1) idle — nothing; (2) waiting — the soft
  /// spinner; (3) hits — `Best matches` + `All matches`, pick rows.
  Widget _resultsArea() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      );
    }
    final List<SubtitleResult>? rows = _rows;
    if (rows == null) {
      // Nothing run yet — no labels, no empty-state UI (rule 1).
      return const SizedBox.shrink();
    }
    if (rows.isEmpty) {
      // Zero hits: no dialog words (§6.5/D10) — an empty result list is
      // itself the answer; the marks stay search-again-able.
      return const SizedBox(height: 26);
    }

    final String pref = LanguageNames.normalize(
        SettingsService.instance.subtitleLanguage.value);
    final List<SubtitleResult> best = rows
        .where((SubtitleResult r) => LanguageNames.normalize(r.language) == pref)
        .take(3)
        .toList();
    final List<SubtitleResult> rest = rows
        .where((SubtitleResult r) => !best.contains(r))
        .toList();

    final List<Widget> children = <Widget>[];
    if (best.isNotEmpty) {
      children
        ..add(_GroupLabel(
            'Best matches · ${LanguageNames.nameOf(pref) ?? pref}'))
        ..addAll(best.map(_resultRow))
        ..add(const SizedBox(height: 2));
    }
    children
      ..add(const _GroupLabel('All matches'))
      ..addAll(rest.map(_resultRow));

    return Scrollbar(
      controller: _results,
      thumbVisibility: false,
      child: ListView(
        controller: _results,
        padding: const EdgeInsets.only(top: 6, right: 4),
        children: children,
      ),
    );
  }

  Widget _resultRow(SubtitleResult r) {
    final bool picked = identical(_picked, r);
    return _ResultRow(
      result: r,
      picked: picked,
      onTap: () => setState(() => _picked = r),
    );
  }
}

/// The group header — the panel's part-label typography (10 px,
/// w600, +0.1em, uppercase).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 3),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// One 40 px, two-line pick row: title + `release · downloads` sub,
/// the language name at the right, a tick when picked.
class _ResultRow extends StatefulWidget {
  const _ResultRow(
      {required this.result, required this.picked, required this.onTap});

  final SubtitleResult result;
  final bool picked;
  final VoidCallback onTap;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final SubtitleResult r = widget.result;
    final String langName = LanguageNames.nameOf(r.language) ?? r.language;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceHighlight : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _hover || widget.picked
                            ? AppColors.textPrimary
                            : AppColors.iconIdle,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (r.subLine.isNotEmpty)
                      Text(
                        r.subLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                langName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.picked
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              if (widget.picked)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: IconTheme(
                    data: IconThemeData(color: AppColors.textPrimary),
                    child: TickMark(size: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
