import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/network_player.dart';
import '../../core/stream_manager.dart';
import '../../theme/app_theme.dart';
import '../widgets/osd_indicator.dart';

/// The left "Library" sidebar (Phase 6 · Step 1).
///
/// Slides in from the left edge (so it never collides with the right Quick
/// Settings panel) and lists the user's saved M3U streams and web bookmarks.
class LibraryPanel extends StatelessWidget {
  const LibraryPanel({
    super.key,
    required this.visible,
    required this.onClose,
    required this.onOpenBookmark,
  });

  final bool visible;
  final VoidCallback onClose;

  /// Opens a bookmark inside the built-in browser (Phase 6 · Step 4).
  final void Function(SavedBookmark bookmark) onOpenBookmark;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(-1, 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !visible,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 320,
              height: double.infinity,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.divider)),
              ),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    color: AppColors.glass,
                    child: ListenableBuilder(
                      listenable: StreamManager.instance,
                      builder: (BuildContext context, Widget? _) {
                        final StreamManager library = StreamManager.instance;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _Header(onClose: onClose),
                            const Divider(height: 1),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.only(bottom: 16),
                                children: <Widget>[
                                  _SectionHeader(
                                    title: 'Saved Streams',
                                    subtitle:
                                        '${library.streams.length}/${StreamManager.maxStreams}',
                                    icon: Icons.podcasts_rounded,
                                    onAdd: library.streamsFull
                                        ? null
                                        : () => _addStream(context),
                                  ),
                                  if (library.streams.isEmpty)
                                    const _EmptyRow(
                                        text: 'No streams saved yet'),
                                  for (int i = 0;
                                      i < library.streams.length;
                                      i++)
                                    _LibraryTile(
                                      icon: Icons.live_tv_rounded,
                                      title: library.streams[i].name,
                                      subtitle: library.streams[i].url,
                                      onTap: () =>
                                          _playStream(library.streams[i]),
                                      onDelete: () =>
                                          library.removeStream(i),
                                    ),
                                  const SizedBox(height: 10),
                                  _SectionHeader(
                                    title: 'Web Bookmarks',
                                    subtitle:
                                        '${library.bookmarks.length}/${StreamManager.maxBookmarks}',
                                    icon: Icons.bookmark_outline_rounded,
                                    onAdd: library.bookmarksFull
                                        ? null
                                        : () => _addBookmark(context),
                                  ),
                                  if (library.bookmarks.isEmpty)
                                    const _EmptyRow(
                                        text: 'No bookmarks saved yet'),
                                  for (int i = 0;
                                      i < library.bookmarks.length;
                                      i++)
                                    _LibraryTile(
                                      icon: Icons.public_rounded,
                                      title: library.bookmarks[i].name,
                                      subtitle: library.bookmarks[i].url,
                                      onTap: () =>
                                          onOpenBookmark(library.bookmarks[i]),
                                      onDelete: () =>
                                          library.removeBookmark(i),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playStream(SavedStream stream) async {
    OsdController.instance
        .show('Loading ${stream.name}…', icon: Icons.live_tv_rounded);
    final String message = await NetworkPlayer.instance
        .playStream(stream.url, name: stream.name);
    OsdController.instance.show(message, icon: Icons.live_tv_rounded);
  }

  Future<void> _addStream(BuildContext context) async {
    final _UrlEntry? entry = await _UrlDialog.show(
      context,
      title: 'Save a network stream',
      hint: 'https://example.com/playlist.m3u',
    );
    if (entry == null) return;
    final String? error =
        StreamManager.instance.addStream(entry.name, entry.url);
    OsdController.instance.show(error ?? 'Stream saved',
        icon: error == null ? Icons.check_rounded : Icons.error_outline_rounded);
  }

  Future<void> _addBookmark(BuildContext context) async {
    final _UrlEntry? entry = await _UrlDialog.show(
      context,
      title: 'Save a web bookmark',
      hint: 'https://example.com',
    );
    if (entry == null) return;
    final String? error =
        StreamManager.instance.addBookmark(entry.name, entry.url);
    OsdController.instance.show(error ?? 'Bookmark saved',
        icon: error == null ? Icons.check_rounded : Icons.error_outline_rounded);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            const Text(
              'Library',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Close library',
              icon: const Icon(Icons.close_rounded,
                  size: 20, color: AppColors.textPrimary),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const Spacer(),
          IconButton(
            tooltip: onAdd == null ? 'Limit reached' : 'Add',
            icon: Icon(Icons.add_rounded,
                size: 19,
                color: onAdd == null
                    ? AppColors.textSecondary
                    : AppColors.accent),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, color: AppColors.textPrimary),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppColors.textSecondary),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrlEntry {
  const _UrlEntry(this.name, this.url);

  final String name;
  final String url;
}

/// Small "paste a URL" dialog used by both library sections.
class _UrlDialog extends StatefulWidget {
  const _UrlDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  static Future<_UrlEntry?> show(
    BuildContext context, {
    required String title,
    required String hint,
  }) {
    return showDialog<_UrlEntry>(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) => _UrlDialog(title: title, hint: hint),
    );
  }

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title,
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                labelText: 'URL',
                hintText: widget.hint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  void _submit() {
    final String url = _url.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(_UrlEntry(_name.text.trim(), url));
  }
}
