import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/media_utils.dart';
import '../../core/web/web_address.dart';
import '../../core/web/web_data_control.dart';
import '../../core/web/web_download_service.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';
import 'web_marks.dart';

/// The download shelf — the badge's answer (Chrome's download bubble):
/// every file this browser has pulled, newest first, each one still
/// travelling with its live progress, each landed one a single mark away
/// from playing inside SALU.
///
/// This is the half of a download that WebView2 never draws itself — the
/// engine hands the download to the host (`put_Handled`) and expects the
/// host to say something about it. Rows are keyed on the engine's own
/// result path, so two files with the same name from the same page stay
/// two rows.
class BrowserDownloadsPanel extends StatelessWidget {
  const BrowserDownloadsPanel({
    super.key,
    required this.onPlay,
    required this.onReveal,
    required this.onRemove,
    required this.onOpenFolder,
    required this.onClearFinished,
    required this.onClose,
  });

  /// Play the file in SALU (media rows only) — the one thing a browser
  /// that is not also a player cannot offer.
  final ValueChanged<WebDownloadItem> onPlay;

  /// Opens the file's own folder with this very file selected.
  final ValueChanged<WebDownloadItem> onReveal;

  /// Drops one row (the file stays on the PC).
  final ValueChanged<String> onRemove;

  /// The footer: the download folder itself (Settings → Web →
  /// Downloads), log empty or not.
  final VoidCallback onOpenFolder;
  final VoidCallback onClearFinished;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WebDownloadService.instance.items,
      builder: (BuildContext context, Widget? _) {
        final List<WebDownloadItem> all =
            WebDownloadService.instance.items.value;
        final int live = all
            .where((WebDownloadItem i) => i.isRunning)
            .length;
        final bool hasFinished =
            all.any((WebDownloadItem i) => !i.isRunning);
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
              constraints: const BoxConstraints(maxHeight: 440),
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
                        const DownloadMark(size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            all.isEmpty
                                ? 'No downloads yet'
                                : (live > 0
                                    ? 'Downloads · $live downloading'
                                    : 'Downloads · ${all.length}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        // Clear the landed rows, keep the ones still
                        // travelling — the bin is the family's Delete.
                        if (hasFinished)
                          SaluIconButton(
                            size: 24,
                            onTap: onClearFinished,
                            tooltip: 'Clear finished',
                            child: const TrashMark(size: 13),
                          ),
                        SaluIconButton(
                          size: 24,
                          onTap: onClose,
                          tooltip: 'Close',
                          child: const CloseMark(size: 10),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: all.isEmpty
                        ? const SizedBox.shrink()
                        : ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: <Widget>[
                              for (final WebDownloadItem item in all)
                                _DownloadRow(
                                  item: item,
                                  onPlay: () => onPlay(item),
                                  onReveal: () => onReveal(item),
                                  onRemove: () => onRemove(item.key),
                                ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onOpenFolder,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0x144C9EEB),
                          borderRadius: BorderRadius.circular(9),
                          border:
                              Border.all(color: const Color(0x404C9EEB)),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconTheme.merge(
                              data:
                                  const IconThemeData(color: AppColors.accent),
                              child: const FolderMark(size: 13),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Open download folder',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.item,
    required this.onPlay,
    required this.onReveal,
    required this.onRemove,
  });

  final WebDownloadItem item;
  final VoidCallback onPlay;
  final VoidCallback onReveal;
  final VoidCallback onRemove;

  /// The row's second line — data, never a lesson: what has landed, of
  /// what, from where.
  String get _detail {
    final String host = item.url.isEmpty ? '' : WebAddress.hostOf(item.url);
    if (item.isRunning) {
      final double? f = item.progress;
      final String size = f == null
          ? WebDataControlService.formatBytes(item.received)
          : '${WebDataControlService.formatBytes(item.received)} of '
              '${WebDataControlService.formatBytes(item.total)}'
              ' · ${(f * 100).round()}%';
      return host.isEmpty ? size : '$size · $host';
    }
    final String size = WebDataControlService.formatBytes(
      item.total > 0 ? item.total : item.received,
    );
    if (item.isFailed) {
      return host.isEmpty ? 'Interrupted' : 'Interrupted · $host';
    }
    return host.isEmpty ? size : '$size · $host';
  }

  @override
  Widget build(BuildContext context) {
    final bool playable = !item.isRunning &&
        !item.isFailed &&
        MediaUtils.isMedia(item.path.isEmpty ? item.fileName : item.path);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            item.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // The family's Done tick: landed, and the ring is
                        // gone with it.
                        if (item.isCompleted) ...<Widget>[
                          const SizedBox(width: 6),
                          const TickMark(size: 11),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: item.isFailed
                            ? AppColors.statusDead
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // A travelling row carries no actions: the engine exposes
              // no cancel through this plugin, and a mark that cannot
              // stop anything would only be a lie.
              if (playable)
                SaluIconButton(
                  size: 24,
                  onTap: onPlay,
                  tooltip: 'Play',
                  child: const PlayMark(size: 12),
                ),
              // Reveal belongs to a file that is actually there: an
              // interrupted row's partial download is not worth showing.
              if (item.isCompleted)
                SaluIconButton(
                  size: 24,
                  onTap: onReveal,
                  tooltip: 'Show in folder',
                  child: const FolderMark(size: 13),
                ),
              // Any finished row can go — including an interrupted one,
              // which is the only way to clear a download the engine
              // never reported an end for.
              if (!item.isRunning)
                SaluIconButton(
                  size: 22,
                  onTap: onRemove,
                  tooltip: 'Remove',
                  child: const CloseMark(size: 10),
                ),
            ],
          ),
          if (item.isRunning) ...<Widget>[
            const SizedBox(height: 5),
            _ProgressRule(progress: item.progress),
          ],
        ],
      ),
    );
  }
}

/// The hairline under a travelling row: the bar family's own track and
/// fill (follow.md · §2 — bars breathe, icons glow), and a quiet
/// indeterminate shimmer when the server never gave a size.
class _ProgressRule extends StatelessWidget {
  const _ProgressRule({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final double? f = progress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: f == null
            ? const ColoredBox(color: AppColors.barTrack)
            : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints cons) {
                  return Stack(
                    children: <Widget>[
                      const Positioned.fill(
                        child: ColoredBox(color: AppColors.barTrack),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: cons.maxWidth * f.clamp(0.0, 1.0),
                        child: const ColoredBox(color: AppColors.barFill),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
