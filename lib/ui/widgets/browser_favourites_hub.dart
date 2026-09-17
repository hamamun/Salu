import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/web/web_address.dart';
import '../../core/web/web_favourites_service.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'web_marks.dart';

/// The favourites hub — the ♥ left of the tab bar opens this slide-down
/// list (web.md · favourites hub). Entries live at ≤15; the list groups
/// them by folder, searches name / URL / folder, and carries a row's whole
/// life: tap opens, right-click edits (the same sheet the star opens),
/// the trailing ✕ removes instantly with a 5-second Undo handed to the
/// screen — no confirmation dialog anywhere (follow.md).
class BrowserFavouritesHub extends StatefulWidget {
  const BrowserFavouritesHub({
    super.key,
    required this.onOpen,
    required this.onEdit,
    required this.onRemove,
    required this.onClose,
  });

  final ValueChanged<WebFavourite> onOpen;

  /// Global index into `WebFavouritesService.favourites`.
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;
  final VoidCallback onClose;

  @override
  State<BrowserFavouritesHub> createState() => _BrowserFavouritesHubState();
}

class _BrowserFavouritesHubState extends State<BrowserFavouritesHub> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The hub opens to be searched — focus lands in the field at once.
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
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WebFavouritesService.instance.favourites,
      builder: (BuildContext context, Widget? _) {
        final List<WebFavourite> all =
            WebFavouritesService.instance.favourites.value;
        final String q = _search.text.trim().toLowerCase();
        // Global indexes survive filtering — edit/remove speak the real
        // list's positions, not the visible ones.
        final List<(int, WebFavourite)> shown = <(int, WebFavourite)>[];
        for (int i = 0; i < all.length; i++) {
          final WebFavourite f = all[i];
          if (q.isEmpty ||
              f.name.toLowerCase().contains(q) ||
              f.url.toLowerCase().contains(q) ||
              f.folder.toLowerCase().contains(q)) {
            shown.add((i, f));
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
              width: 320,
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceOutline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
                    child: Row(
                      children: <Widget>[
                        const HeartMark(size: 15, filled: true),
                        const SizedBox(width: 8),
                        Text(
                          all.isEmpty
                              ? 'No favourites yet'
                              : 'Favourites · ${all.length} of '
                                  '${WebFavouritesService.maxEntries}',
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
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
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
                            hintText: 'Search favourites',
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
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _rows(List<(int, WebFavourite)> shown, String q) {
    if (shown.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            q.isEmpty
                ? 'Pages you star land here — up to ${WebFavouritesService.maxEntries}.'
                : 'No match.',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ];
    }
    final List<Widget> out = <Widget>[];
    String? lastGroup;
    for (final (int index, WebFavourite f) in shown) {
      final String group = f.folder;
      if (group != lastGroup) {
        lastGroup = group;
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 3),
          child: Row(
            children: <Widget>[
              if (group.isEmpty)
                const StarMark(size: 11)
              else
                const FolderMark(size: 12),
              const SizedBox(width: 6),
              Text(
                group.isEmpty ? 'Unsorted' : group,
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ));
      }
      out.add(_HubRow(
        favourite: f,
        onOpen: () => widget.onOpen(f),
        onEdit: () => widget.onEdit(index),
        onRemove: () => widget.onRemove(index),
      ));
    }
    return out;
  }
}

class _HubRow extends StatelessWidget {
  const _HubRow({
    required this.favourite,
    required this.onOpen,
    required this.onEdit,
    required this.onRemove,
  });

  final WebFavourite favourite;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        onSecondaryTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: <Widget>[
              const StarMark(size: 13, filled: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      favourite.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      WebAddress.hostOf(favourite.url),
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
              const SizedBox(width: 6),
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
