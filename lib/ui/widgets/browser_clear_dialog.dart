import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/web/web_data_control.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';
import 'web_marks.dart';

/// The Clear dialog — Chrome/Edge-shaped, SALU-skinned (web.md · Clear data —
/// LOCKED): exactly four items, all of it browser-owned data —
/// Browsing history · Cookies & site data · Cached images & files ·
/// Downloads.
///
/// Features:
/// 1. SALU-style dialog presentation: centered window over dimmed backdrop,
///    crisp borders, Segoe typography, rounded geometry (16px), subtle shadow.
/// 2. Chrome/Edge data size indicators: each item displays its current footprint
///    (e.g., "14 items", "1.2 MB", "18.4 MB", "None") dynamically calculated
///    from the history store and the WebView2 profile cache/storage folders.
/// 3. Immediate and honest feedback: after clearing, reopened dialog shows
///    sizes reduced and cleaned.
/// 4. One button clears; dialog is the confirmation, exactly once.
///
/// SALU's own data (resume memory, saved streams) is a different store and
/// is never mentioned here, because it is never touched (web.md lock).
Future<void> showWebClearDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierColor: const Color(0x99000000),
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
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
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) =>
        const _WebClearDialog(),
  );
}

class _WebClearDialog extends StatefulWidget {
  const _WebClearDialog();

  @override
  State<_WebClearDialog> createState() => _WebClearDialogState();
}

class _WebClearDialogState extends State<_WebClearDialog> {
  bool _history = true;
  bool _cookies = true;
  bool _cache = true;
  bool _downloads = false;
  bool _busy = false;

  WebDataFootprint _footprint = const WebDataFootprint();
  bool _measuring = true;

  @override
  void initState() {
    super.initState();
    _loadFootprint();
  }

  Future<void> _loadFootprint() async {
    final WebDataFootprint fp = await WebDataControlService.measureFootprint();
    if (!mounted) return;
    setState(() {
      _footprint = fp;
      _measuring = false;
    });
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);

    await WebDataControlService.instance.clear(WebDataClearFlags(
      history: _history,
      cookies: _cookies,
      cache: _cache,
      downloads: _downloads,
    ));

    // The dialog itself is the confirmation (web.md · Clear data — LOCKED):
    // it closes, and a reopened dialog shows the reduced, cleaned footprint.
    // No Undo toast — the folder purge and per-view clears have no honest
    // undo to offer.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = math.min(480.0, constraints.maxWidth);
          return Container(
            width: width,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceOutline),
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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.divider,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.surfaceOutline),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: IconTheme(
                                data: IconThemeData(
                                    color: AppColors.textSecondary),
                                child: ShieldMark(size: 14),
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'SALU browser footprint only. Saved streams, bookmarks, '
                                'and resume progress are always protected.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ItemRow(
                        title: 'Browsing history',
                        subtitle: 'Clears visits from history and omnibox suggestions',
                        sizeText: _measuring ? '…' : _footprint.historyLabel,
                        mark: const ClockMark(size: 15),
                        value: _history,
                        onChanged: (bool v) => setState(() => _history = v),
                      ),
                      const SizedBox(height: 6),
                      _ItemRow(
                        title: 'Cookies & site data',
                        subtitle: 'Signs you out of most websites',
                        sizeText: _measuring ? '…' : _footprint.cookiesLabel,
                        mark: const CookieMark(size: 15),
                        value: _cookies,
                        onChanged: (bool v) => setState(() => _cookies = v),
                      ),
                      const SizedBox(height: 6),
                      _ItemRow(
                        title: 'Cached images & files',
                        subtitle: 'Frees up disk space; some sites may load slower next visit',
                        sizeText: _measuring ? '…' : _footprint.cacheLabel,
                        mark: const ReloadMark(size: 15),
                        value: _cache,
                        onChanged: (bool v) => setState(() => _cache = v),
                      ),
                      const SizedBox(height: 6),
                      _ItemRow(
                        title: 'Downloads history',
                        subtitle: 'Clears the list of downloaded files (files stay on PC)',
                        sizeText: 'Records only',
                        mark: const DownloadMark(size: 15),
                        value: _downloads,
                        onChanged: (bool v) => setState(() => _downloads = v),
                      ),
                      if (_footprint.profilePurgePending) ...<Widget>[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: AppColors.surfaceOutline),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: IconTheme(
                                  data: IconThemeData(
                                      color: AppColors.textSecondary),
                                  child: HourglassMark(size: 13),
                                ),
                              ),
                              SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Already cleaned. Files locked by the running '
                                  'browser are queued and will be wiped the next '
                                  'time SALU starts.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.35,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.divider,
                ),
                _buildActions(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: <Widget>[
          // The family's own mark leads the header, exactly like the
          // History / Favourites / Site panels — no chip, no stock icon.
          const BroomMark(size: 16),
          const SizedBox(width: 10),
          const Text(
            'Clear browsing data',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          SaluIconButton(
            size: 28,
            onTap: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            child: const CloseMark(size: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final bool anySelected = _history || _cookies || _cache || _downloads;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          _DialogAction(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          _DialogAction(
            label: 'Clear data',
            primary: true,
            enabled: !_busy && anySelected,
            busy: _busy,
            onTap: _clear,
          ),
        ],
      ),
    );
  }
}

/// The dialog's labelled action — the same outlined pill the History panel
/// uses for "Clear all history", so the family's one text-shaped control
/// looks the same everywhere: `surfaceOutline` border, 9px radius, Segoe
/// 12.5px semibold, hover fills with `surfaceHighlight` and the label lights
/// to white (~120 ms), press sinks to 0.97× — no Material ripple, ink or
/// elevation. Primary is carried by the label (white vs. secondary) and a
/// brighter outline, never by a filled block behind it (follow.md · §6).
/// Disabled simply dims and stops answering the cursor.
class _DialogAction extends StatefulWidget {
  const _DialogAction({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  /// Shows a small monochrome spinner in place of the label.
  final bool busy;

  @override
  State<_DialogAction> createState() => _DialogActionState();
}

class _DialogActionState extends State<_DialogAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool on = widget.enabled;
    final bool lit = on && _hovered;
    final Color rest =
        widget.primary ? AppColors.textPrimary : AppColors.textSecondary;
    final Color ink = !on
        ? AppColors.textSecondary.withAlpha(110)
        : (lit ? Colors.white : rest);
    final Color outline = !on
        ? AppColors.surfaceOutline.withAlpha(140)
        : (widget.primary || lit
            ? AppColors.divider
            : AppColors.surfaceOutline);

    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _pressed = true) : null,
        onTapUp: on ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: on ? () => setState(() => _pressed = false) : null,
        onTap: on ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 32,
            constraints: const BoxConstraints(minWidth: 84),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: lit ? AppColors.surfaceHighlight : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: outline),
            ),
            alignment: Alignment.center,
            child: widget.busy
                ? SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: ink,
                    ),
                  )
                : AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: ink,
                    ),
                    child: Text(widget.label),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    required this.title,
    required this.subtitle,
    required this.sizeText,
    required this.mark,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final String sizeText;

  /// The category's SALU mark (monochrome — never a stock icon, never a
  /// coloured chip; follow.md · rules 4 + 6).
  final Widget mark;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceHighlight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // Checkbox mark
              _SaluCheckbox(checked: widget.value),
              const SizedBox(width: 12),
              // Leading category mark — monochrome, SALU-drawn; it lights
              // with the row's checked state, it is never coloured.
              IconTheme(
                data: IconThemeData(
                  color: widget.value
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                child: widget.mark,
              ),
              const SizedBox(width: 12),
              // Titles
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Footprint badge — quiet and monochrome like everything else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.surfaceOutline),
                ),
                child: Text(
                  widget.sizeText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: widget.sizeText == 'None'
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaluCheckbox extends StatelessWidget {
  const _SaluCheckbox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 19,
      height: 19,
      decoration: BoxDecoration(
        color: checked ? AppColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? AppColors.accent : const Color(0xFF5A5A5E),
          width: 1.6,
        ),
      ),
      alignment: Alignment.center,
      child: checked
          ? const IconTheme(
              data: IconThemeData(color: Colors.white),
              child: TickMark(size: 12),
            )
          : null,
    );
  }
}


