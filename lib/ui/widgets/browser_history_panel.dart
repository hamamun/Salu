import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/web/web_address.dart';
import '../../core/web/web_history_service.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';
import 'web_marks.dart';

/// The history panel — the ⋮ menu's "History": every visited page, newest
/// first, grouped Today / Yesterday / Earlier, searchable. A tap opens
/// the page in the active tab; the trailing × drops one row; the footer
/// clears the whole store (no undo — browser data never grows one).
class BrowserHistoryPanel extends StatefulWidget {
  const BrowserHistoryPanel({
    super.key,
    required this.onOpen,
    required this.onRemove,
    required this.onClearAll,
    required this.onClose,
  });

  final ValueChanged<WebHistoryEntry> onOpen;

  /// Global index into `WebHistoryService.entries`.
  final ValueChanged<int> onRemove;
  final VoidCallback onClearAll;
  final VoidCallback onClose;

  @override
  State<BrowserHistoryPanel> createState() => _BrowserHistoryPanelState();
}

class _BrowserHistoryPanelState extends State<BrowserHistoryPanel> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static String _dayLabel(int ms) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(d.year, d.month, d.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return 'Earlier';
  }

  static String _clock(int ms) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    final String h = d.hour.toString().padLeft(2, '0');
    final String m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WebHistoryService.instance.entries,
      builder: (BuildContext context, Widget? _) {
        final List<WebHistoryEntry> all =
            WebHistoryService.instance.entries.value;
        final String q = _search.text.trim().toLowerCase();
        // Global indexes survive filtering — remove speaks the real
        // list's positions, not the visible ones.
        final List<(int, WebHistoryEntry)> shown = <(int, WebHistoryEntry)>[];
        for (int i = 0; i < all.length; i++) {
          final WebHistoryEntry e = all[i];
          if (q.isEmpty ||
              e.displayTitle.toLowerCase().contains(q) ||
              e.url.toLowerCase().contains(q)) {
            shown.add((i, e));
          }
        }
        return Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Material(
            elevation: 0,
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 360,
              constraints: const BoxConstraints(maxHeight: 440),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceOutline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 4),
                    child: Row(
                      children: <Widget>[
                        const ClockMark(size: 14),
                        const SizedBox(width: 8),
                        Text(
                          all.isEmpty
                              ? 'No history yet'
                              : 'History · ${all.length}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                        const Spacer(),
                        SaluIconButton(
                          size: 24,
                          onTap: widget.onClose,
                          child: const CloseMark(size: 10),
                        ),
                      ],
                    ),
                  ),
                  if (all.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppColors.surfaceOutline),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary),
                          cursorColor: AppColors.accent,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Search history',
                            hintStyle: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: _rows(shown, q),
                    ),
                  ),
                  if (all.isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(14, 4, 14, 12),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onClearAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: AppColors.surfaceOutline),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Clear all history',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _rows(List<(int, WebHistoryEntry)> shown, String q) {
    if (shown.isEmpty) {
      return <Widget>[
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            q.isEmpty
                ? 'Pages you visit land here — newest first.'
                : 'No match.',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ];
    }
    final List<Widget> out = <Widget>[];
    String? lastGroup;
    for (final (int index, WebHistoryEntry e) in shown) {
      // While searching, groups would chop one match-list into slivers —
      // the flat list reads better.
      final String group = q.isEmpty ? _dayLabel(e.visitedMs) : '';
      if (group != lastGroup) {
        lastGroup = group;
        if (group.isNotEmpty) {
          out.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 3),
            child: Text(
              group,
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ));
        }
      }
      out.add(_HistoryRow(
        entry: e,
        clock: _clock(e.visitedMs),
        onOpen: () => widget.onOpen(e),
        onRemove: () => widget.onRemove(index),
      ));
    }
    return out;
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.clock,
    required this.onOpen,
    required this.onRemove,
  });

  final WebHistoryEntry entry;
  final String clock;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${WebAddress.hostOf(entry.url)} · $clock',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SaluIconButton(
                size: 22,
                onTap: onRemove,
                tooltip: 'Remove',
                child: const CloseMark(size: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
