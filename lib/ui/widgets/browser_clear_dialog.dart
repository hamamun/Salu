import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/web/web_data_control.dart';
import '../../theme/app_theme.dart';
import '../osd/osd_controller.dart';
import 'salu_marks.dart';

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
    final WebDataFootprint fp =
        await WebDataControlService.instance.measureFootprint();
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

    if (mounted) {
      Navigator.of(context).pop();
      OsdController.instance.show(
        const OsdUndoCard(label: 'Browsing data cleared'),
      );
    }
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
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: AppColors.accent,
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
                        icon: Icons.history_rounded,
                        value: _history,
                        onChanged: (bool v) => setState(() => _history = v),
                      ),
                      const SizedBox(height: 6),
                      _ItemRow(
                        title: 'Cookies & site data',
                        subtitle: 'Signs you out of most websites',
                        sizeText: _measuring ? '…' : _footprint.cookiesLabel,
                        icon: Icons.cookie_outlined,
                        value: _cookies,
                        onChanged: (bool v) => setState(() => _cookies = v),
                      ),
                      const SizedBox(height: 6),
                      _ItemRow(
                        title: 'Cached images & files',
                        subtitle: 'Frees up disk space; some sites may load slower next visit',
                        sizeText: _measuring ? '…' : _footprint.cacheLabel,
                        icon: Icons.cached_rounded,
                        value: _cache,
                        onChanged: (bool v) => setState(() => _cache = v),
                      ),
                      const SizedBox(height: 6),
                      _ItemRow(
                        title: 'Downloads history',
                        subtitle: 'Clears the list of downloaded files (files stay on PC)',
                        sizeText: 'Records only',
                        icon: Icons.download_done_rounded,
                        value: _downloads,
                        onChanged: (bool v) => setState(() => _downloads = v),
                      ),
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
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0x1F4C9EEB),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.cleaning_services_rounded,
              size: 17,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
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
          _CloseIconButton(
            onPressed: () => Navigator.of(context).pop(),
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: (_busy || !anySelected) ? null : _clear,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0x334C9EEB),
              disabledForegroundColor: Colors.white38,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Clear data',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    required this.title,
    required this.subtitle,
    required this.sizeText,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final String sizeText;
  final IconData icon;
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
              // Leading category icon
              Icon(
                widget.icon,
                size: 18,
                color: widget.value ? AppColors.accent : AppColors.textSecondary,
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
              // Footprint badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.sizeText == 'None'
                        ? AppColors.surfaceOutline
                        : const Color(0x334C9EEB),
                  ),
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
          ? const Icon(
              Icons.check_rounded,
              size: 14,
              color: Colors.white,
            )
          : null,
    );
  }
}

class _CloseIconButton extends StatefulWidget {
  const _CloseIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CloseIconButton> createState() => _CloseIconButtonState();
}

class _CloseIconButtonState extends State<_CloseIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceHighlight : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.close,
            size: 17,
            color: _hovered ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
