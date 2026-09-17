import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'web_marks.dart';

/// Find-in-page — the ⋮ menu's "Find in page…" (Chrome's `Ctrl+F` bar):
/// type, and every match lights up; Enter walks forward, Shift+Enter
/// walks back, Esc closes. The screen owns the query + the count (it
/// runs the script and survives navigations); this bar is only the face.
class BrowserFindBar extends StatelessWidget {
  const BrowserFindBar({
    super.key,
    required this.query,
    required this.queryFocus,
    required this.total,
    required this.index,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  final TextEditingController query;
  final FocusNode queryFocus;
  final ValueListenable<int> total;
  final ValueListenable<int> index;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        onPrev();
      } else {
        onNext();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      child: Material(
        elevation: 0,
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 360,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.surfaceOutline),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: query,
                  focusNode: queryFocus,
                  onChanged: onQueryChanged,
                  // Shift is still physically down when Enter submits,
                  // so the direction reads true here.
                  onSubmitted: (_) => HardwareKeyboard
                          .instance.isShiftPressed
                      ? onPrev()
                      : onNext(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Find in page',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _Count(query: query, total: total, index: index),
              const SizedBox(width: 2),
              SaluIconButton(
                size: 26,
                onTap: onPrev,
                tooltip: 'Previous',
                child: const Icon(Icons.keyboard_arrow_up, size: 18),
              ),
              SaluIconButton(
                size: 26,
                onTap: onNext,
                tooltip: 'Next',
                child: const Icon(Icons.keyboard_arrow_down, size: 18),
              ),
              SaluIconButton(
                size: 26,
                onTap: onClose,
                tooltip: 'Close',
                child: const CloseMark(size: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.query,
    required this.total,
    required this.index,
  });

  final TextEditingController query;
  final ValueListenable<int> total;
  final ValueListenable<int> index;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[query, total, index]),
      builder: (BuildContext context, Widget? _) {
        if (query.text.isEmpty) return const SizedBox(width: 8);
        final int t = total.value;
        final int i = index.value;
        return SizedBox(
          width: 52,
          child: Text(
            t == 0 ? '0/0' : '$i/$t',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: t == 0
                  ? const Color(0xFFE07070)
                  : AppColors.textSecondary,
            ),
          ),
        );
      },
    );
  }
}
