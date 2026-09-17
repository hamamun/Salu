import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/web/web_tab.dart';
import '../../theme/app_theme.dart';

/// The browser menu — the ⋮ at the row's right edge (Chrome's ⋮ slot):
/// the standard shelf every browser carries: new tab, zoom, desktop
/// mode, find, history, downloads, clear, open-in-Edge, settings.
///
/// Page-bound rows (find, open-in-Edge) dim while no page is showing;
/// zoom and desktop mode stay live — a virgin tab remembers them for
/// boot. Downloads unfolds inline: files save silently to the Downloads
/// folder (no progress events reach this plugin), so the section names
/// the folder and opens it.
class BrowserMenu extends StatefulWidget {
  const BrowserMenu({
    super.key,
    required this.tab,
    required this.onNewTab,
    required this.onFind,
    required this.onHistory,
    required this.onClearData,
    required this.onOpenInEdge,
    required this.onSettings,
    required this.onDownloadsFolder,
    required this.onClose,
  });

  final WebTab? tab;
  final VoidCallback onNewTab;
  final VoidCallback onFind;
  final VoidCallback onHistory;
  final VoidCallback onClearData;
  final VoidCallback onOpenInEdge;
  final VoidCallback onSettings;
  final VoidCallback onDownloadsFolder;
  final VoidCallback onClose;

  @override
  State<BrowserMenu> createState() => _BrowserMenuState();
}

class _BrowserMenuState extends State<BrowserMenu> {
  bool _downloadsOpen = false;

  @override
  Widget build(BuildContext context) {
    final WebTab? tab = widget.tab;
    final bool page = tab?.hasPage == true;
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode n, KeyEvent e) {
        if (e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        elevation: 0,
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceOutline),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _MenuRow(
                label: 'New tab',
                hint: 'Ctrl+T',
                onTap: widget.onNewTab,
              ),
              const _MenuDivider(),
              if (tab != null) ...<Widget>[
                _ZoomRow(tab: tab),
                _DesktopRow(tab: tab),
                const _MenuDivider(),
              ],
              _MenuRow(
                label: 'Find in page…',
                hint: 'Ctrl+F',
                enabled: page,
                onTap: widget.onFind,
              ),
              _MenuRow(
                label: 'History',
                onTap: widget.onHistory,
              ),
              _MenuRow(
                label: 'Downloads',
                trailing: Icon(
                  _downloadsOpen
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                onTap: () =>
                    setState(() => _downloadsOpen = !_downloadsOpen),
              ),
              if (_downloadsOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(9),
                      border:
                          Border.all(color: AppColors.surfaceOutline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text(
                          'Files save to the Downloads folder.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onDownloadsFolder,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0x144C9EEB),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0x404C9EEB)),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'Show in folder',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              _MenuRow(
                label: 'Clear browsing data…',
                onTap: widget.onClearData,
              ),
              _MenuRow(
                label: 'Open in Edge',
                enabled: page,
                onTap: widget.onOpenInEdge,
              ),
              const _MenuDivider(),
              _MenuRow(
                label: 'Settings',
                onTap: widget.onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Divider(height: 1, thickness: 1, color: AppColors.divider),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.label,
    this.hint,
    this.trailing,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final String? hint;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool live = widget.enabled && widget.onTap != null;
    return MouseRegion(
      cursor: live ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: live ? widget.onTap : null,
        child: Container(
          height: 34,
          color: _hovered && live ? AppColors.surfaceHighlight : null,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: live
                        ? AppColors.textPrimary
                        : AppColors.textSecondary.withAlpha(140),
                  ),
                ),
              ),
              if (widget.hint != null)
                Text(
                  widget.hint!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: live
                        ? AppColors.textSecondary
                        : AppColors.textSecondary.withAlpha(140),
                  ),
                ),
              if (widget.trailing != null) ...<Widget>[
                const SizedBox(width: 6),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Zoom — Chrome's − / % / + cluster: the steps climb the engine's own
/// ladder, the percentage resets to 100%.
class _ZoomRow extends StatelessWidget {
  const _ZoomRow({required this.tab});

  final WebTab tab;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: tab.zoom,
      builder: (BuildContext context, double z, Widget? _) {
        return Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Zoom',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _ZoomBtn(label: '−', onTap: () => tab.zoomOut()),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tab.resetZoom(),
                child: Container(
                  width: 52,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${(z * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              _ZoomBtn(label: '+', onTap: () => tab.zoomIn()),
            ],
          ),
        );
      },
    );
  }
}

class _ZoomBtn extends StatefulWidget {
  const _ZoomBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_ZoomBtn> createState() => _ZoomBtnState();
}

class _ZoomBtnState extends State<_ZoomBtn> {
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceHighlight : null,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop mode — one switch: the tab identifies as Edge-on-Windows for
/// sites that serve WebView2 a broken mobile page.
class _DesktopRow extends StatelessWidget {
  const _DesktopRow({required this.tab});

  final WebTab tab;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: tab.desktopMode,
      builder: (BuildContext context, bool on, Widget? _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => tab.setDesktopMode(!on),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 7),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Desktop mode',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Identify as Edge on Windows.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _MenuSwitch(on: on),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The menu's switch — the settings `_SaluSwitch` geometry at menu
/// scale: a 34×20 pill, knob right when on.
class _MenuSwitch extends StatelessWidget {
  const _MenuSwitch({required this.on});

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
