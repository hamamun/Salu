import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/web/web_address.dart';
import '../../core/web/web_tab.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';
import 'web_marks.dart';

/// The site panel — the padlock's answer (Chrome's "View site
/// information"): who this page claims to be, whether the line is private,
/// and what the site may do about pop-ups. The Allow/Block rows write a
/// permanent rule; "just for this visit" keeps the decision to the
/// session (the ad-boom answer for disposable domains).
class BrowserSitePanel extends StatelessWidget {
  const BrowserSitePanel({
    super.key,
    required this.pageUrl,
    required this.secure,
    required this.popupsAllowed,
    required this.blockedCount,
    required this.onPopupsChanged,
    required this.onVisitAllow,
    required this.onShowBlocked,
    required this.onClose,
  });

  final String pageUrl;
  final bool secure;

  /// The site's effective state right now (visit memory, rule, default —
  /// `WebPopupService.resolve` already folded them).
  final bool popupsAllowed;

  final int blockedCount;
  final ValueChanged<bool> onPopupsChanged;
  final VoidCallback onVisitAllow;
  final VoidCallback onShowBlocked;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final String host = WebAddress.hostOf(pageUrl);
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode n, KeyEvent e) {
        if (e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        elevation: 0,
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceOutline),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  PadlockMark(size: 15, open: !secure),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  SaluIconButton(
                    size: 24,
                    onTap: onClose,
                    child: const CloseMark(size: 10),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 23),
                child: Text(
                  secure
                      ? 'Connection is secure'
                      : 'Connection is not secure',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                    height: 1, thickness: 1, color: AppColors.divider),
              ),
              const Text(
                'POP-UPS',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              _ChoiceRow(
                label: 'Allow',
                helper: 'This site may open new tabs.',
                selected: popupsAllowed,
                onTap: () => onPopupsChanged(true),
              ),
              const SizedBox(height: 4),
              _ChoiceRow(
                label: 'Block',
                helper: 'Held-back pop-ups show in the address bar.',
                selected: !popupsAllowed,
                onTap: () => onPopupsChanged(false),
              ),
              if (!popupsAllowed) ...<Widget>[
                const SizedBox(height: 2),
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onVisitAllow,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Allow just for this visit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (blockedCount > 0) ...<Widget>[
                const SizedBox(height: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onShowBlocked,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppColors.surfaceOutline),
                    ),
                    child: Row(
                      children: <Widget>[
                        const PopupMark(size: 13),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$blockedCount blocked on this page',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const Text(
                          'View',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.helper,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String helper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: selected ? 4 : 1.5,
                  color: selected
                      ? AppColors.accent
                      : const Color(0xFF7A7A7A),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    helper,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The held-back list — the badge's answer (Chrome's "Pop-up blocked"
/// bubble): every pop-up this page asked for, each one openable, plus the
/// one-tap permanent allow for the site.
class BlockedPopupList extends StatelessWidget {
  const BlockedPopupList({
    super.key,
    required this.items,
    required this.host,
    required this.canOpen,
    required this.onOpen,
    required this.onAllowSite,
    required this.onClose,
  });

  final List<BlockedPopup> items;
  final String host;

  /// False at the tab cap — opening needs a free tab, so the rows go
  /// quiet instead of hijacking the page you are looking at.
  final bool canOpen;
  final ValueChanged<String> onOpen;
  final VoidCallback onAllowSite;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode n, KeyEvent e) {
        if (e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        elevation: 0,
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 380,
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceOutline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
                child: Row(
                  children: <Widget>[
                    const PopupMark(size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pop-ups blocked · ${items.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    SaluIconButton(
                      size: 24,
                      onTap: onClose,
                      child: const CloseMark(size: 10),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: <Widget>[
                    for (final BlockedPopup item in items)
                      _BlockedRow(
                        item: item,
                        canOpen: canOpen,
                        onOpen: () => onOpen(item.url),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAllowSite,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0x144C9EEB),
                          borderRadius: BorderRadius.circular(9),
                          border:
                              Border.all(color: const Color(0x404C9EEB)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Always allow on $host',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                    if (!canOpen)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Close a tab to open links.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  const _BlockedRow({
    required this.item,
    required this.canOpen,
    required this.onOpen,
  });

  final BlockedPopup item;
  final bool canOpen;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  WebAddress.hostOf(item.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  item.url,
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
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canOpen ? onOpen : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 4),
              child: Text(
                'Open',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: canOpen
                      ? AppColors.accent
                      : AppColors.textSecondary.withAlpha(140),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
