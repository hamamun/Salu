import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/shortcuts/shortcut_registry.dart';
import '../../core/web/web_tab.dart';
import '../../theme/app_theme.dart';
import 'alt_peek.dart';
import 'salu_icon_button.dart';

/// The browser menu — the ⋮ at the row's right edge (Chrome's ⋮ slot):
/// the standard shelf every browser carries: new tab, zoom, desktop
/// mode, find, history, downloads, clear, open-in-Edge, settings.
///
/// Page-bound rows (find, open-in-Edge) dim while no page is showing;
/// zoom and desktop mode stay live — a virgin tab remembers them for
/// boot. Downloads is a door, not a section: it opens the download
/// shelf, where the engine's own reports are already waiting — what is
/// travelling, what landed, and the file each one became.
class BrowserMenu extends StatelessWidget {
  const BrowserMenu({
    super.key,
    required this.tab,
    required this.onNewTab,
    required this.onFind,
    required this.onHistory,
    required this.onClearData,
    required this.onOpenInEdge,
    required this.onSettings,
    required this.onDownloads,
    required this.onClose,
  });

  final WebTab? tab;
  final VoidCallback onNewTab;
  final VoidCallback onFind;
  final VoidCallback onHistory;
  final VoidCallback onClearData;
  final VoidCallback onOpenInEdge;
  final VoidCallback onSettings;

  /// Opens the download shelf (the badge's own panel).
  final VoidCallback onDownloads;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final WebTab? tab = this.tab;
    final bool page = tab?.hasPage == true;
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode n, KeyEvent e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        elevation: 0,
        color: context.overlayTint(context.palette.surface),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.surfaceOutline),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _MenuRow(
                label: 'New tab',
                onTap: onNewTab,
                keys: _keys('web.newTab'),
              ),
              const _MenuDivider(),
              if (tab != null) ...<Widget>[
                _ZoomRow(tab: tab),
                _DesktopRow(tab: tab),
                const _MenuDivider(),
              ],
              _MenuRow(
                label: 'Find in page…',
                enabled: page,
                onTap: onFind,
                keys: _keys('web.find'),
              ),
              _MenuRow(
                label: 'History',
                onTap: onHistory,
                keys: _keys('web.history'),
              ),
              _MenuRow(
                label: 'Downloads',
                onTap: onDownloads,
                keys: _keys('web.downloads'),
              ),
              _MenuRow(
                label: 'Clear browsing data…',
                onTap: onClearData,
                keys: _keys('web.clearData'),
              ),
              _MenuRow(
                label: 'Open in Edge',
                enabled: page,
                onTap: onOpenInEdge,
              ),
              const _MenuDivider(),
              _MenuRow(
                label: 'Settings',
                onTap: onSettings,
                keys: _keys('web.settings'),
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Divider(height: 1, thickness: 1, color: context.palette.divider),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.label,
    this.enabled = true,
    this.onTap,
    this.keys,
  }) : trailing = null;

  final String label;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTap;

  /// The row's registered key(s) — the Alt-Peek's tooltip names it while
  /// Alt is held and the mouse is on the row (the menu IS the transient
  /// surface; rows with no key — Open in Edge — stay honestly silent).
  final List<ShortcutEntry>? keys;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

/// The row's registered keys — the Alt-Peek's tooltip names them.
List<ShortcutEntry>? _keys(String id) {
  final ShortcutEntry? e = SaluShortcuts.byId(id);
  return e == null ? null : <ShortcutEntry>[e];
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool live = widget.enabled && widget.onTap != null;
    final Widget row = MouseRegion(
      cursor: live ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: live ? widget.onTap : null,
        child: Container(
          height: 34,
          color: _hovered && live ? context.palette.surfaceHighlight : null,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: live
                        ? context.palette.textPrimary
                        : context.palette.textSecondary.withAlpha(140),
                  ),
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
    if (widget.keys == null) return row;
    return AltPeekAnchor(
      entries: widget.keys,
      side: PeekSide.below,
      child: row,
    );
  }
}

/// Zoom — Chrome's − / % / + cluster: the steps climb the engine's own
/// ladder, the percentage resets to 100%. Each of the three answers the
/// Alt-Peek with its own key (`Ctrl+-` · `Ctrl+0` · `Ctrl+=`).
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
              Expanded(
                child: Text(
                  'Zoom',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.textPrimary,
                  ),
                ),
              ),
              AltPeekAnchor(
                entries: _keys('web.zoomOut'),
                side: PeekSide.below,
                child: _ZoomBtn(label: '−', onTap: () => tab.zoomOut()),
              ),
              AltPeekAnchor(
                entries: _keys('web.zoomReset'),
                side: PeekSide.below,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tab.resetZoom(),
                  child: Container(
                    width: 52,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${(z * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.palette.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              AltPeekAnchor(
                entries: _keys('web.zoomIn'),
                side: PeekSide.below,
                child: _ZoomBtn(label: '+', onTap: () => tab.zoomIn()),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Zoom − / + — glyphs, not marks, but they keep the one SALU recipe:
/// light up + grow on hover, sink on press, nothing ever drawn behind
/// them (follow.md · §2; no hover box).
class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SaluIconButton(
      size: 28,
      tooltip: label == '−' ? 'Zoom out' : 'Zoom in',
      onTap: onTap,
      child: Builder(
        builder: (BuildContext context) => Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: IconTheme.of(context).color ?? context.palette.iconIdle,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Desktop mode',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.palette.textPrimary,
                        ),
                      ),
                      Text(
                        'Identify as Edge on Windows.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.textSecondary,
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
        color: on
            ? context.palette.accent
            : context.palette.resolve(
                const Color(0xFF3A3A3C),
                const Color(0xFFB8B8C0),
              ),
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
