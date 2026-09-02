import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/media_utils.dart';
import '../../../core/network_player.dart';
import '../../../core/player_service.dart';
import '../../../theme/app_theme.dart';

/// The Playlist tab (Phase 4 · Step 2): current queue, add/remove controls,
/// chapter markers, and loop/shuffle toggles.
class PlaylistTab extends StatefulWidget {
  const PlaylistTab({super.key});

  @override
  State<PlaylistTab> createState() => _PlaylistTabState();
}

class _PlaylistTabState extends State<PlaylistTab> {
  final PlayerService _player = PlayerService.instance;
  bool _showChapters = false;

  /// Active "Group By" value for IPTV playlists (null = show everything).
  String? _groupFilter;
  List<_Chapter> _chapters = <_Chapter>[];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: Row(
            children: <Widget>[
              _PlaylistModeButton(),
              const SizedBox(width: 4),
              _ShuffleButton(),
              const Spacer(),
              TextButton.icon(
                onPressed: _toggleChapters,
                icon: Icon(
                  _showChapters ? Icons.movie_outlined : Icons.format_list_bulleted,
                  size: 17,
                  color: AppColors.accent,
                ),
                label: Text(
                  _showChapters ? 'Queue' : 'Chapters',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.accent),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Phase 6 · Step 3: massive IPTV playlists get a "Group By" filter
        // and a Clear Playlist button.
        ListenableBuilder(
          listenable: NetworkPlayer.instance,
          builder: (BuildContext context, Widget? _) {
            final NetworkPlayer iptv = NetworkPlayer.instance;
            if (_showChapters || !iptv.isMassivePlaylist) {
              return const SizedBox.shrink();
            }
            return _IptvToolbar(iptv: iptv);
          },
        ),
        Expanded(
          child: _showChapters ? _buildChapters() : _buildQueue(),
        ),
        const Divider(height: 1),
        _BottomBar(onAdd: _addFiles),
      ],
    );
  }

  Widget _buildQueue() {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _player.playlist,
        NetworkPlayer.instance,
      ]),
      builder: (BuildContext context, Widget? child) {
        final Playlist? playlist = _player.playlist.value;
        final List<Media> medias = playlist?.medias ?? const <Media>[];
        if (medias.isEmpty) {
          return const _EmptyState(
            icon: Icons.queue_music_rounded,
            message: 'Nothing queued yet\nDrop files or press + to add',
          );
        }

        final NetworkPlayer iptv = NetworkPlayer.instance;
        final String? filter = _groupFilter;

        // Indices surviving the active "Group By" filter.
        final List<int> indices = <int>[];
        for (int i = 0; i < medias.length; i++) {
          if (filter == null || iptv.grouping == IptvGrouping.none) {
            indices.add(i);
            continue;
          }
          if (i < iptv.channels.length &&
              iptv.valueFor(iptv.channels[i]) == filter) {
            indices.add(i);
          }
        }

        if (indices.isEmpty) {
          return const _EmptyState(
            icon: Icons.filter_alt_off_outlined,
            message: 'No channels in this group',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: indices.length,
          itemBuilder: (BuildContext context, int position) {
            final int index = indices[position];
            final bool isCurrent = playlist!.index == index;
            final String? channelTitle = iptv.titleAt(index);
            return _QueueTile(
              title: channelTitle ?? MediaUtils.displayName(medias[index].uri),
              isCurrent: isCurrent,
              onTap: () => _player.jump(index),
            );
          },
        );
      },
    );
  }

  Widget _buildChapters() {
    if (_chapters.isEmpty) {
      return const _EmptyState(
        icon: Icons.movie_outlined,
        message: 'No chapters found in this file',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _chapters.length,
      itemBuilder: (BuildContext context, int index) {
        final _Chapter chapter = _chapters[index];
        return ListTile(
          dense: true,
          leading: Text(
            MediaUtils.formatDuration(chapter.time),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          title: Text(
            chapter.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
          ),
          onTap: () => _player.seek(chapter.time),
        );
      },
    );
  }

  Future<void> _toggleChapters() async {
    if (!_showChapters) {
      await _loadChapters();
    }
    setState(() => _showChapters = !_showChapters);
  }

  /// Reads embedded chapters straight from mpv (`chapter-list/N/*`).
  Future<void> _loadChapters() async {
    final PlayerService player = _player;
    final List<_Chapter> chapters = <_Chapter>[];
    try {
      final String? countStr = await player.getMpvProperty('chapters');
      final int count = int.tryParse(countStr ?? '') ?? 0;
      for (int i = 0; i < count && i < 200; i++) {
        final String? title = await player.getMpvProperty('chapter-list/$i/title');
        final String? time = await player.getMpvProperty('chapter-list/$i/time');
        final double seconds = double.tryParse(time ?? '') ?? 0;
        chapters.add(_Chapter(
          title: (title == null || title.isEmpty) ? 'Chapter ${i + 1}' : title,
          time: Duration(milliseconds: (seconds * 1000).round()),
        ));
      }
    } catch (error) {
      debugPrint('[SALU] chapter read failed: $error');
    }
    if (!mounted) return;
    setState(() => _chapters = chapters);
  }

  void _setGroupFilter(String? value) {
    setState(() => _groupFilter = value);
  }

  void _resetGroupFilter() {
    setState(() => _groupFilter = null);
  }

  Future<void> _addFiles() async {
    final List<XTypeGroup> groups = <XTypeGroup>[
      XTypeGroup(
        label: 'Media',
        extensions: <String>[
          ...MediaUtils.videoExtensions.map((String e) => e.substring(1)),
          ...MediaUtils.audioExtensions.map((String e) => e.substring(1)),
          ...MediaUtils.playlistExtensions.map((String e) => e.substring(1)),
        ],
      ),
    ];
    final List<XFile> files = await openFiles(acceptedTypeGroups: groups);
    final List<String> paths =
        files.map((XFile f) => f.path).where((String p) => p.isNotEmpty).toList();
    if (paths.isNotEmpty) {
      await _player.addAllToPlaylist(paths);
    }
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onAdd});

  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Remove current item',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.textSecondary),
            onPressed: () {
              final PlayerService player = PlayerService.instance;
              final Playlist? playlist = player.playlist.value;
              if (playlist != null && playlist.medias.isNotEmpty) {
                player.removeFromPlaylist(playlist.index);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.title,
    required this.isCurrent,
    required this.onTap,
  });

  final String title;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent ? AppColors.surfaceHighlight : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              if (isCurrent)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.equalizer_rounded,
                      size: 16, color: AppColors.accent),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isCurrent ? AppColors.accent : AppColors.textPrimary,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistModeButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaylistMode>(
      valueListenable: PlayerService.instance.playlistMode,
      builder: (BuildContext context, PlaylistMode mode, Widget? _) {
        final (IconData icon, String tooltip) = switch (mode) {
          PlaylistMode.none => (Icons.repeat_rounded, 'Loop: off'),
          PlaylistMode.single => (Icons.repeat_one_rounded, 'Loop: single'),
          PlaylistMode.loop => (Icons.repeat_rounded, 'Loop: playlist'),
        };
        return IconButton(
          tooltip: tooltip,
          icon: Icon(
            icon,
            size: 20,
            color: mode == PlaylistMode.none
                ? AppColors.textSecondary
                : AppColors.accent,
          ),
          onPressed: () {
            final PlayerService player = PlayerService.instance;
            switch (mode) {
              case PlaylistMode.none:
                player.setPlaylistMode(PlaylistMode.single);
              case PlaylistMode.single:
                player.setPlaylistMode(PlaylistMode.loop);
              case PlaylistMode.loop:
                player.setPlaylistMode(PlaylistMode.none);
            }
          },
        );
      },
    );
  }
}

class _ShuffleButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PlayerService.instance.shuffle,
      builder: (BuildContext context, bool shuffle, Widget? _) {
        return IconButton(
          tooltip: shuffle ? 'Shuffle: on' : 'Shuffle: off',
          icon: Icon(
            Icons.shuffle_rounded,
            size: 20,
            color: shuffle ? AppColors.accent : AppColors.textSecondary,
          ),
          onPressed: () => PlayerService.instance.setShuffle(!shuffle),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chapter {
  const _Chapter({required this.title, required this.time});

  final String title;
  final Duration time;
}

/// "Group By" filter + Clear Playlist controls shown for massive IPTV lists.
class _IptvToolbar extends StatelessWidget {
  const _IptvToolbar({required this.iptv});

  final NetworkPlayer iptv;

  @override
  Widget build(BuildContext context) {
    final _PlaylistTabState? state =
        context.findAncestorStateOfType<_PlaylistTabState>();
    return Container(
      color: AppColors.surfaceHighlight.withAlpha(90),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${iptv.channels.length} channels',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  iptv.clear();
                  PlayerService.instance.player.stop();
                  state?._resetGroupFilter();
                },
                icon: const Icon(Icons.playlist_remove_rounded, size: 17),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const Text(
                'Group by',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<IptvGrouping>(
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  value: iptv.grouping,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textPrimary),
                  items: <DropdownMenuItem<IptvGrouping>>[
                    for (final IptvGrouping g in IptvGrouping.values)
                      DropdownMenuItem<IptvGrouping>(
                        value: g,
                        child: Text(g.label),
                      ),
                  ],
                  onChanged: (IptvGrouping? value) {
                    if (value == null) return;
                    iptv.grouping = value;
                    state?._resetGroupFilter();
                  },
                ),
              ),
            ],
          ),
          if (iptv.grouping != IptvGrouping.none)
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final String value in <String>[
                    'All',
                    ...iptv.groupValues,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(value,
                            style: const TextStyle(fontSize: 11.5)),
                        onPressed: () => state?._setGroupFilter(
                            value == 'All' ? null : value),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
