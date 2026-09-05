import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/open_media_service.dart';
import '../../core/ui_lock.dart';
import '../../core/url_library_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/salu_icon_button.dart';

/// Opens SALU's Open-URL modal (see follow.md · §4, Level 2).
///
/// A centered glass window over a dimmed barrier — a focus task:
/// open → act → gone. SALU's shared motion (fade + 0.96→1.0 scale).
Future<void> showOpenUrlDialog(BuildContext context) async {
  await UrlLibraryService.instance.load();
  if (!context.mounted) return;
  ChromeLock.instance.acquire();
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
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
          Animation<double> secondaryAnimation) => const OpenUrlDialog(),
    );
  } finally {
    ChromeLock.instance.release();
  }
}

/// The modal body.
///
/// Anatomy (top to bottom):
///   · one input — paste a URL; Play plays it, Play & Save also keeps it
///   · the saved list (max 7): ≡ drag-handle · ● status dot · name, and
///     on hover only: hide / edit / delete actions fading in at the right
///   · a transient Undo toast after a delete (no confirmation dialogs)
///
/// Silent keyboard flow: Enter plays (input or highlighted row),
/// Esc closes, ↑/↓ walk the list. Nothing of this is written in the UI.
class OpenUrlDialog extends StatefulWidget {
  const OpenUrlDialog({super.key});

  @override
  State<OpenUrlDialog> createState() => _OpenUrlDialogState();
}

class _OpenUrlDialogState extends State<OpenUrlDialog> {
  final UrlLibraryService _library = UrlLibraryService.instance;
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  /// Holds keyboard focus while the highlight walks the list, so ↑/↓ and
  /// Enter keep flowing through the dialog's key handler.
  final FocusNode _listFocus = FocusNode();

  /// Keyboard highlight over the display list (−1 = the input row).
  int _cursor = -1;

  /// Index (into the service list) of the row being edited inline.
  int _editing = -1;

  /// Undo state after a delete.
  SavedUrl? _lastRemoved;
  int _lastRemovedIndex = -1;
  Timer? _undoTimer;

  @override
  void initState() {
    super.initState();
    _library.entries.addListener(_onLibraryChanged);
    _prefillFromClipboard();
  }

  @override
  void dispose() {
    _library.entries.removeListener(_onLibraryChanged);
    _undoTimer?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _onLibraryChanged() => setState(() {});

  /// Clipboard auto-fill: a URL-looking clipboard pre-fills the input,
  /// fully selected — paste → Enter → playing.
  Future<void> _prefillFromClipboard() async {
    try {
      final ClipboardData? data =
          await Clipboard.getData(Clipboard.kTextPlain);
      final String text = data?.text?.trim() ?? '';
      if (!mounted || text.isEmpty) return;
      if (UrlLibraryService.looksLikeUrl(text) && _input.text.isEmpty) {
        _input.text = text;
        _input.selection =
            TextSelection(baseOffset: 0, extentOffset: text.length);
      }
    } catch (_) {
      // Clipboard unavailable — the input simply starts empty.
    } finally {
      if (mounted) _inputFocus.requestFocus();
    }
  }

  // ── Display order: visible rows first, hidden rows sink below ───────

  List<SavedUrl> get _all => _library.entries.value;

  /// Display list as indices into the service list.
  List<int> get _displayIndices {
    final List<SavedUrl> all = _all;
    final List<int> visible = <int>[];
    final List<int> hidden = <int>[];
    for (int i = 0; i < all.length; i++) {
      (all[i].hidden ? hidden : visible).add(i);
    }
    return <int>[...visible, ...hidden];
  }

  // ── Actions ──────────────────────────────────────────────────────────

  bool get _inputPlayable =>
      UrlLibraryService.looksLikeUrl(_input.text.trim());

  void _play(String url) {
    Navigator.of(context).pop();
    unawaited(OpenMediaService.playUrl(url));
  }

  void _playInput({bool save = false}) {
    final String url = _input.text.trim();
    if (!UrlLibraryService.looksLikeUrl(url)) return;
    if (save) _library.add(url);
    _play(url);
  }

  void _delete(int serviceIndex) {
    final SavedUrl? removed = _library.removeAt(serviceIndex);
    if (removed == null) return;
    setState(() {
      _lastRemoved = removed;
      _lastRemovedIndex = serviceIndex;
      _editing = -1;
      _cursor = -1;
    });
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _lastRemoved = null);
    });
  }

  void _undoDelete() {
    final SavedUrl? removed = _lastRemoved;
    if (removed == null) return;
    _undoTimer?.cancel();
    _library.insertAt(_lastRemovedIndex, removed);
    setState(() => _lastRemoved = null);
  }

  // `newDisplay` already accounts for the removal of the dragged item at
  // `oldDisplay` (onReorderItem semantics — no manual index shift needed).
  void _onReorder(int oldDisplay, int newDisplay) {
    final List<int> order = _displayIndices;
    if (oldDisplay < 0 || oldDisplay >= order.length) return;
    final int target = newDisplay.clamp(0, order.length - 1).toInt();
    _library.move(order[oldDisplay], order[target]);
    setState(() => _cursor = -1);
  }

  // ── Silent keyboard flow ─────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_editing >= 0) return KeyEventResult.ignored;
    final int count = _displayIndices.length;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && count > 0) {
      setState(() => _cursor = math.min(_cursor + 1, count - 1));
      if (_cursor >= 0) _listFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _cursor = math.max(_cursor - 1, -1));
      if (_cursor < 0) _inputFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _cursor >= 0) {
      final List<int> order = _displayIndices;
      if (_cursor < order.length) _play(_all[order[_cursor]].url);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
      backgroundColor: Colors.transparent,
      child: Focus(
        focusNode: _listFocus,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = math.min(520.0, constraints.maxWidth);
            return Container(
              width: width,
              constraints: BoxConstraints(
                maxHeight: math.min(560.0, constraints.maxHeight),
              ),
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
                  _buildInputRow(),
                  if (_all.isNotEmpty) ...<Widget>[
                    const Divider(
                        height: 1, thickness: 1, color: AppColors.divider),
                    Flexible(child: _buildList()),
                  ],
                  if (_lastRemoved != null) _buildUndoToast(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── The single input + Play / Play & Save ───────────────────────────

  Widget _buildInputRow() {
    final bool playable = _inputPlayable;
    final bool canSave = playable && !_library.isFull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _input,
            focusNode: _inputFocus,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _playInput(),
            onTap: () => setState(() => _cursor = -1),
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            cursorColor: AppColors.textPrimary,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Paste a URL to play',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.surfaceOutline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF4A4A4E)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _ActionButton(
                label: 'Play & Save',
                enabled: canSave,
                // 7/7: Save dims; plain Play always works.
                tooltip: playable && _library.isFull ? 'List full' : null,
                onTap: () => _playInput(save: true),
              ),
              const SizedBox(width: 10),
              _ActionButton(
                label: 'Play',
                emphasized: true,
                enabled: playable,
                onTap: _playInput,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Saved list ───────────────────────────────────────────────────────

  Widget _buildList() {
    final List<int> order = _displayIndices;
    return ReorderableListView.builder(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: order.length,
      onReorderItem: _onReorder,
      proxyDecorator:
          (Widget child, int index, Animation<double> animation) {
        return Material(color: Colors.transparent, child: child);
      },
      itemBuilder: (BuildContext context, int displayIndex) {
        final int serviceIndex = order[displayIndex];
        final SavedUrl entry = _all[serviceIndex];
        return _UrlRow(
          key: ValueKey<String>('url_${entry.url}'),
          entry: entry,
          displayIndex: displayIndex,
          highlighted: _cursor == displayIndex,
          editing: _editing == serviceIndex,
          onPlay: () => _play(entry.url),
          onToggleHidden: () {
            _library.toggleHidden(serviceIndex);
            setState(() => _cursor = -1);
          },
          onEdit: () => setState(() => _editing = serviceIndex),
          onEditDone: (String name, String url) {
            _library.update(serviceIndex, name: name, url: url);
            setState(() => _editing = -1);
          },
          onEditCancel: () => setState(() => _editing = -1),
          onDelete: () => _delete(serviceIndex),
        );
      },
    );
  }

  // ── Undo toast (no confirmation dialogs — ever) ──────────────────────

  Widget _buildUndoToast() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _lastRemoved?.name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: _undoDelete,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('Undo', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── A saved-URL row ──────────────────────────────────────────────────────

class _UrlRow extends StatefulWidget {
  const _UrlRow({
    super.key,
    required this.entry,
    required this.displayIndex,
    required this.highlighted,
    required this.editing,
    required this.onPlay,
    required this.onToggleHidden,
    required this.onEdit,
    required this.onEditDone,
    required this.onEditCancel,
    required this.onDelete,
  });

  final SavedUrl entry;
  final int displayIndex;
  final bool highlighted;
  final bool editing;
  final VoidCallback onPlay;
  final VoidCallback onToggleHidden;
  final VoidCallback onEdit;
  final void Function(String name, String url) onEditDone;
  final VoidCallback onEditCancel;
  final VoidCallback onDelete;

  @override
  State<_UrlRow> createState() => _UrlRowState();
}

class _UrlRowState extends State<_UrlRow> {
  bool _hovered = false;

  Color get _dotColor => switch (widget.entry.health) {
        UrlHealth.alive => AppColors.statusAlive,
        UrlHealth.dead => AppColors.statusDead,
        UrlHealth.unknown => AppColors.statusUnknown,
      };

  @override
  Widget build(BuildContext context) {
    if (widget.editing) {
      return _InlineEditor(
        entry: widget.entry,
        onDone: widget.onEditDone,
        onCancel: widget.onEditCancel,
      );
    }

    final bool asleep = widget.entry.hidden;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.only(left: 6, right: 4),
          decoration: BoxDecoration(
            color: (_hovered || widget.highlighted)
                ? AppColors.surfaceHighlight
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Opacity(
            // Hidden rows sink to the bottom, visually asleep (40%) —
            // still clickable.
            opacity: asleep ? 0.4 : 1.0,
            child: Row(
              children: <Widget>[
                // ≡ drag handle — the only way to reorder.
                ReorderableDragStartListener(
                  index: widget.displayIndex,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                // ● status dot — last play attempt (green/red/gray).
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dotColor,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // Hover-only actions: hide · edit · delete.
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: IgnorePointer(
                    ignoring: !_hovered,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SaluIconButton(
                          size: 28,
                          tooltip: asleep ? 'Show' : 'Hide',
                          onTap: widget.onToggleHidden,
                          child: Icon(
                            asleep
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 16,
                          ),
                        ),
                        SaluIconButton(
                          size: 28,
                          tooltip: 'Edit',
                          onTap: widget.onEdit,
                          child: const Icon(
                            Icons.edit_outlined,
                            size: 16,
                          ),
                        ),
                        SaluIconButton(
                          size: 28,
                          tooltip: 'Delete',
                          onTap: widget.onDelete,
                          child: const Icon(
                            Icons.delete_outline,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Inline editor — the row itself becomes name + URL fields ────────────

class _InlineEditor extends StatefulWidget {
  const _InlineEditor({
    required this.entry,
    required this.onDone,
    required this.onCancel,
  });

  final SavedUrl entry;
  final void Function(String name, String url) onDone;
  final VoidCallback onCancel;

  @override
  State<_InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<_InlineEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.entry.name);
  late final TextEditingController _url =
      TextEditingController(text: widget.entry.url);
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _commit() => widget.onDone(_name.text, _url.text);

  InputDecoration _decoration() {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.surfaceOutline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF4A4A4E)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 140,
              child: TextField(
                controller: _name,
                focusNode: _nameFocus,
                onSubmitted: (_) => _commit(),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                cursorColor: AppColors.textPrimary,
                decoration: _decoration(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _url,
                onSubmitted: (_) => _commit(),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                cursorColor: AppColors.textPrimary,
                decoration: _decoration(),
              ),
            ),
            const SizedBox(width: 4),
            SaluIconButton(
              size: 30,
              tooltip: 'Done',
              onTap: _commit,
              child: const Icon(Icons.check, size: 17),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Flat text action button (Play / Play & Save) ─────────────────────────

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.enabled,
    this.emphasized = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool emphasized;
  final String? tooltip;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool on = widget.enabled;
    final Color text = !on
        ? AppColors.textSecondary.withAlpha(115) // Dimmed, never blocked-looking.
        : (_hovered ? AppColors.textPrimary : AppColors.iconIdle);
    final Color fill = widget.emphasized
        ? (on
            ? (_hovered ? AppColors.surfaceHighlight : AppColors.surface)
            : AppColors.surface.withAlpha(128))
        : Colors.transparent;

    Widget button = MouseRegion(
      cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: on ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(9),
              border: widget.emphasized
                  ? Border.all(color: AppColors.surfaceOutline)
                  : null,
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight:
                    widget.emphasized ? FontWeight.w600 : FontWeight.w500,
                color: text,
              ),
            ),
          ),
        ),
      ),
    );

    final String? tooltip = widget.tooltip;
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: button,
      );
    }
    return button;
  }
}
