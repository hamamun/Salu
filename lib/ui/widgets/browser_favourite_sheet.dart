import 'package:flutter/material.dart';

import '../../core/web/web_favourites_service.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'web_marks.dart';

/// The slide-out favourite panel (web.md · favourite star lock): tapping
/// the star opens one door with two flows — outline star = SAVE (name +
/// folder), filled star = EDIT (Rename · Change folder · Remove). A
/// focus-task, so it behaves like SALU's modals: Enter confirms, Esc
/// cancels, nothing teaches.
class BrowserFavouriteSheet extends StatefulWidget {
  const BrowserFavouriteSheet({
    super.key,
    required this.entryIndex,
    required this.entry,
    required this.defaultName,
    required this.defaultUrl,
    required this.full,
    required this.onSave,
    required this.onUpdate,
    required this.onRemove,
    required this.onClose,
  });

  /// null → save flow; otherwise the index of the favourite being edited.
  final int? entryIndex;

  /// The entry being edited (null in the save flow).
  final WebFavourite? entry;

  /// Pre-filled name for a fresh save (page title, else host).
  final String defaultName;
  final String defaultUrl;

  /// Save flow while the 15 slots are taken — the door stays open, the
  /// button waits, one quiet line says why (no dialogs, no lectures).
  final bool full;

  final void Function(String name, String folder) onSave;
  final void Function(int index, String name, String folder) onUpdate;
  final ValueChanged<int> onRemove;
  final VoidCallback onClose;

  @override
  State<BrowserFavouriteSheet> createState() => _BrowserFavouriteSheetState();
}

class _BrowserFavouriteSheetState extends State<BrowserFavouriteSheet> {
  late final TextEditingController _name = TextEditingController(
      text: widget.entry?.name ?? widget.defaultName);
  late final TextEditingController _folder = TextEditingController(
      text: widget.entry?.folder ?? '');
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _folder.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _commit() {
    if (widget.full && widget.entryIndex == null) return;
    final String name = _name.text.trim();
    final String folder = _folder.text.trim();
    if (widget.entryIndex != null) {
      widget.onUpdate(widget.entryIndex!, name, folder);
    } else {
      widget.onSave(name, folder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.entryIndex != null;
    // Existing folders are one tap away (the hub's grouping depends on
    // consistent spelling); typing a new word makes a new one.
    final List<String> folders = WebFavouritesService.instance.folders;
    return Material(
      elevation: 0,
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceOutline),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const StarMark(size: 14, filled: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    editing ? 'Edit favourite' : 'Add favourite',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                SaluIconButton(
                  size: 24,
                  onTap: widget.onClose,
                  child: const CloseMark(size: 10),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.defaultUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            _Field(
              label: 'Name',
              controller: _name,
              focus: _nameFocus,
              onEnter: _commit,
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Folder',
              controller: _folder,
              hint: 'Unsorted',
              onEnter: _commit,
            ),
            if (folders.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String f in folders)
                    _FolderChip(
                      label: f,
                      selected: _folder.text.trim() == f,
                      onTap: () {
                        setState(() => _folder.text = f);
                      },
                    ),
                ],
              ),
            ],
            if (widget.full && !editing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: const Text(
                  '15 favourites is the limit — remove one to add this.',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: (widget.full && !editing) ? null : _commit,
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    child: Text(
                      editing ? 'Save' : 'Done',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                if (editing) ...<Widget>[
                  const SizedBox(width: 8),
                  SaluIconButton(
                    size: 30,
                    onTap: () => widget.onRemove(widget.entryIndex!),
                    tooltip: 'Remove',
                    child: const CloseMark(size: 12),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.focus,
    this.hint,
    this.onEnter,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode? focus;
  final String? hint;
  final VoidCallback? onEnter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 3),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.surfaceOutline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(
            controller: controller,
            focusNode: focus,
            onSubmitted: (_) => onEnter?.call(),
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textPrimary),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

class _FolderChip extends StatelessWidget {
  const _FolderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceHighlight : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.surfaceOutline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
