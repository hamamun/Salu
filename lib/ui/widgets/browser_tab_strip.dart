import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/web/web_address.dart';
import '../../core/web/web_tab.dart';
import '../../theme/app_theme.dart';
import '../screens/browser_screen.dart' show kWebStripHeight;
import 'salu_icon_button.dart';
import 'web_marks.dart';

/// The tab strip — directly below the title bar (web.md), chromeless like
/// everything in SALU. The active tab lights its own floor; the rest stay
/// quiet.
///
/// Every locked detail lives here: the `+` sits immediately right of the
/// last tab (grows with the list, capped by the parent's `maxTabs`); each
/// tab carries its close × on its RIGHT side; inactive tabs are lazy —
/// they hold no web engine at all until clicked (`WebTab.activate`), so ten
/// open tabs cost what one costs. The ♥ hub button is the caller's [hub]
/// slot, placed to the LEFT of the tab row (web.md).
///
/// Middle-click or right-click closes a tab — browser idioms, unlabeled.
class BrowserTabStrip extends StatelessWidget {
  const BrowserTabStrip({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onNewTab,
    required this.maxTabs,
    this.hub,
  });

  final List<WebTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onNewTab;
  final int maxTabs;

  /// The favourites-hub heart button, left of the tab row.
  final Widget? hub;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kWebStripHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          if (hub != null) ...<Widget>[hub!, const SizedBox(width: 2)],
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (int i = 0; i < tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: _TabChip(
                      tab: tabs[i],
                      active: i == activeIndex,
                      onTap: () => onSelect(i),
                      onClose: () => onClose(i),
                    ),
                  ),
                // The “+” grows with the list and stops answering at the
                // cap — the limit is felt, not explained.
                _PlusTab(
                  enabled: tabs.length < maxTabs,
                  onTap: onNewTab,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final WebTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        // Middle-click closes the tab — a browser idiom the strip never
        // labels (web.md). It rides a [Listener] because the middle button
        // never reaches the tap recognizers [GestureDetector] owns.
        behavior: HitTestBehavior.opaque,
        onPointerDown: (PointerDownEvent e) {
          if (e.buttons & kMiddleMouseButton != 0) onClose();
        },
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTap: onClose,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(maxWidth: 208, minWidth: 118),
            padding: const EdgeInsets.only(left: 10, right: 6),
            decoration: BoxDecoration(
              color: active ? AppColors.surfaceHighlight : AppColors.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: active ? AppColors.accent : AppColors.surfaceOutline,
              ),
            ),
            child: Row(
              children: <Widget>[
                _TabBadge(tab: tab, active: active),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: tab.title,
                    builder: (BuildContext context, String? _, Widget? __) {
                      return Text(
                        tab.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: active
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      );
                    },
                  ),
                ),
                // The close × sits on the RIGHT side of the tab (web.md).
                SaluIconButton(
                  size: 22,
                  onTap: onClose,
                  child: const CloseMark(size: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tab's left badge: while its page travels, a slim ring; then the
/// site's favicon; else the title's first letter — no box behind it
/// (follow.md).
class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.tab, required this.active});

  final WebTab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: ValueListenableBuilder<String?>(
        valueListenable: tab.url,
        builder: (BuildContext context, String? url, Widget? _) {
          return ValueListenableBuilder<bool>(
            valueListenable: tab.loading,
            builder: (BuildContext context, bool loading, Widget? _) {
              if (active && loading) {
                return const Padding(
                  padding: EdgeInsets.all(1.5),
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: AppColors.textPrimary,
                  ),
                );
              }
              final Widget letter = _Letter(tab: tab, active: active);
              if (!tab.started || url == null || !url.startsWith('http')) {
                return letter;
              }
              return Image.network(
                'https://www.google.com/s2/favicons'
                '?domain=${WebAddress.hostOf(url)}&sz=32',
                width: 14,
                height: 14,
                gaplessPlayback: true,
                errorBuilder:
                    (BuildContext c, Object e, StackTrace? st) => letter,
              );
            },
          );
        },
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({required this.tab, required this.active});

  final WebTab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final String label = tab.displayTitle;
    final String ch = label.isEmpty ? '?' : label[0].toUpperCase();
    return Center(
      child: Text(
        ch,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          height: 1.0,
          color:
              active ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _PlusTab extends StatelessWidget {
  const _PlusTab({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      child: Center(
        child: SaluIconButton(
          size: 26,
          enabled: enabled,
          onTap: onTap,
          tooltip: 'New tab',
          child: CustomPaint(
            size: const Size.square(13),
            painter: _PlusPainter(
                enabled ? AppColors.textPrimary : AppColors.iconIdle),
          ),
        ),
      ),
    );
  }
}

class _PlusPainter extends CustomPainter {
  const _PlusPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final double a = size.width * 0.16, b = size.width * 0.84;
    final double m = size.width * 0.5;
    canvas.drawLine(Offset(m, a), Offset(m, b), paint);
    canvas.drawLine(Offset(a, m), Offset(b, m), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.ink != ink;
}
