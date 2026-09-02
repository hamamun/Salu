import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/media_utils.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/osd_indicator.dart';

/// The floating subtitle search modal (Phase 4 · Step 5, drafted).
///
/// "Load Local Subtitle" works now; the live OpenSubtitles results list is
/// wired up in Phase 7 (the layout and API-key plumbing already exist).
class SubtitleSearchModal extends StatefulWidget {
  const SubtitleSearchModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) => const SubtitleSearchModal(),
    );
  }

  @override
  State<SubtitleSearchModal> createState() => _SubtitleSearchModalState();
}

class _SubtitleSearchModalState extends State<SubtitleSearchModal> {
  @override
  Widget build(BuildContext context) {
    final String? uri = PlayerService.instance.currentMediaUri;
    final String mediaName =
        uri == null ? 'No media loaded' : MediaUtils.displayName(uri);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text(
                    'Find Subtitles',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Now playing: $mediaName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _loadLocal,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Load Local Subtitle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Online search (OpenSubtitles)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: TextEditingController(text: mediaName),
                enabled: false,
                style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search query',
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.background,
                  disabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _PlaceholderResults(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadLocal() async {
    final List<XFile> files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'Subtitles',
          extensions: <String>['srt', 'ass', 'ssa', 'sub', 'vtt'],
        ),
      ],
    );
    if (files.isEmpty) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    await PlayerService.instance.loadExternalSubtitle(files.first.path);
    OsdController.instance.show('Subtitle loaded', icon: Icons.subtitles_rounded);
  }
}

class _PlaceholderResults extends StatelessWidget {
  const _PlaceholderResults();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.cloud_off_outlined, size: 34, color: AppColors.textSecondary),
          SizedBox(height: 10),
          Text(
            'Search results arrive in Phase 7',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            'Hash-based "Top 3 Best Matches" + all results, '
            'with language flags, will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
