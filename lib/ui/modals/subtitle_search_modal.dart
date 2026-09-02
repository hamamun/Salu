import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/app_prefs.dart';
import '../../core/language_utils.dart';
import '../../core/media_utils.dart';
import '../../core/player_service.dart';
import '../../core/smart_queue_service.dart';
import '../../core/subtitles_api.dart';
import '../../theme/app_theme.dart';
import '../widgets/osd_indicator.dart';

/// The floating subtitle search modal (Phase 4 draft, wired to the
/// OpenSubtitles API in Phase 7 · Step 4).
///
/// Opens on the playing video's file name, hashes the file, and asks
/// api.opensubtitles.com for matches. Exact file-hash hits get a dedicated
/// "Top 3 Best Matches" block; everything else lands in "All Results".
/// Clicking any row downloads the subtitle **next to the video** under the
/// video's own base name (movie.mp4 → movie.srt), loads it into mpv right
/// away, and flashes an OSD message — and because it becomes a sidecar file,
/// it never needs to be downloaded again.
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
  late final TextEditingController _query;

  /// Absolute path of the local video being searched (null → not possible).
  String? _videoPath;

  bool _searching = false;
  String? _error;
  int? _downloadingFileId;
  SubtitleSearchOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    final String? uri = PlayerService.instance.currentMediaUri;
    final String? path = uri == null ? null : SmartQueueService.toLocalPath(uri);
    _videoPath = (path != null && File(path).existsSync()) ? path : null;

    _query = TextEditingController(
      text: _videoPath == null ? '' : MediaUtils.displayName(_videoPath!),
    );

    // Auto-run the search when the modal makes sense for the current media.
    if (_videoPath != null && SubtitlesApi.instance.hasApiKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _search() async {
    final String? path = _videoPath;
    if (path == null) {
      setState(() => _error =
          'Play a local video file first — SALU searches by its name and file hash.');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _outcome = null;
    });
    final SubtitleSearchOutcome outcome =
        await SubtitlesApi.instance.searchForVideo(path, queryOverride: _query.text);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _outcome = outcome;
      if (outcome.hasError) _error = outcome.error;
    });
  }

  Future<void> _download(SubtitleResult match) async {
    final String? path = _videoPath;
    if (path == null || _downloadingFileId != null) return;
    setState(() => _downloadingFileId = match.fileId);
    final SubtitleDownloadOutcome result =
        await SubtitlesApi.instance.downloadToVideoFolder(match, path);
    if (!mounted) return;
    setState(() => _downloadingFileId = null);

    if (result.success && result.path != null) {
      Navigator.of(context).pop();
      // Feed mpv immediately…
      await PlayerService.instance.loadExternalSubtitle(result.path!);
      // …and celebrate. The file now sits beside the video as a sidecar, so
      // future plays load it with zero downloads.
      OsdController.instance.show(
        'Subtitle Downloaded: ${LanguageUtils.displayName(result.language ?? '')}',
        icon: Icons.subtitles_rounded,
      );
    } else {
      setState(() => _error = result.message);
    }
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

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final String mediaName = _videoPath == null
        ? (PlayerService.instance.currentTitle.value ?? 'No media loaded')
        : MediaUtils.displayName(_videoPath!);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SizedBox(
          // 540 px keeps the modal inside SALU's minimum window height
          // (800×600) even with the dialog's default insets.
          height: 540,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(mediaName),
                const SizedBox(height: 6),
                _buildMetaRow(),
                const SizedBox(height: 14),
                _buildSearchRow(),
                const SizedBox(height: 6),
                _buildLanguageRow(),
                const SizedBox(height: 12),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String mediaName) {
    return Row(
      children: <Widget>[
        const Icon(Icons.public_rounded, size: 20, color: AppColors.accent),
        const SizedBox(width: 10),
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
    );
  }

  Widget _buildSearchRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _query,
            onSubmitted: (_) => _search(),
            style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search query (defaults to the file name)',
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 18, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.background,
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.divider),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.accent),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _searching ? null : _search,
          icon: const Icon(Icons.bolt_rounded, size: 17),
          label: const Text('Search'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow() {
    final String? path = _videoPath;
    final String mediaName = path != null
        ? MediaUtils.displayName(path)
        : (PlayerService.instance.currentTitle.value ?? 'nothing');
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Now playing: $mediaName${path == null ? '  ·  hash search unavailable for streams' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
        TextButton.icon(
          onPressed: _loadLocal,
          icon: const Icon(Icons.folder_open_outlined, size: 16),
          label: const Text('Load local…'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// The default language doubles as the user's preference — changing it in
  /// the modal keeps Settings → Subtitles in sync (Phase 7 · Step 5 uses it
  /// for the silent auto-download too).
  Widget _buildLanguageRow() {
    final String current = AppPrefs.instance.defaultSubtitleLanguage;
    final List<String> codes = <String>{
      'all',
      ...LanguageUtils.commonCodes,
      if (current.isNotEmpty && current != 'all') current,
    }.toList()
      ..sort((String a, String b) {
        if (a == 'all') return -1;
        if (b == 'all') return 1;
        return LanguageUtils.displayName(a).compareTo(LanguageUtils.displayName(b));
      });

    return Row(
      children: <Widget>[
        const Text(
          'Preferred language',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: codes.contains(current) ? current : 'all',
          isDense: true,
          dropdownColor: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          underline: const SizedBox.shrink(),
          style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
          items: <DropdownMenuItem<String>>[
            for (final String code in codes)
              DropdownMenuItem<String>(
                value: code,
                child: Text(
                  code == 'all'
                      ? 'All languages'
                      : '${LanguageUtils.flagEmoji(code)}  ${LanguageUtils.displayName(code)}',
                ),
              ),
          ],
          onChanged: (String? value) {
            if (value == null || value == current) return;
            AppPrefs.instance.defaultSubtitleLanguage = value;
            // Re-run the search straight away when results are on screen.
            if (_outcome != null) unawaited(_search());
          },
          menuMaxHeight: 320,
        ),
        const Spacer(),
        if (current != 'all')
          const Text(
            'Also used by auto-download',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppColors.accent),
            ),
            SizedBox(height: 14),
            Text(
              'Hashing the file and querying OpenSubtitles…',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final SubtitleSearchOutcome? outcome = _outcome;
    if (outcome == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _error == null ? Icons.cloud_download_outlined : Icons.error_outline_rounded,
              size: 36,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _error ??
                    'Search OpenSubtitles for subtitles that match this exact file.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.45),
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _loadLocal,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('Load Local Subtitle Instead'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.divider),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ],
        ),
      );
    }

    final List<Widget> tiles = <Widget>[];
    if (outcome.bestMatches.isNotEmpty) {
      tiles.add(
        const _SectionHeader(
          'TOP MATCHES',
          badge: 'exact file hash',
        ),
      );
      tiles.addAll(outcome.bestMatches.map(_buildResultTile));
    }
    if (outcome.results.isNotEmpty) {
      tiles.add(const _SectionHeader('ALL RESULTS'));
      tiles.addAll(outcome.results.map(_buildResultTile));
    }
    if (tiles.isEmpty) {
      tiles.add(
        const Center(
          child: Text(
            'No subtitles found for this query.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.only(bottom: 8), children: tiles);
  }

  Widget _buildResultTile(SubtitleResult match) {
    return _SubtitleResultTile(
      match: match,
      busy: _downloadingFileId == match.fileId,
      disabled: _videoPath == null ||
          (_downloadingFileId != null && _downloadingFileId != match.fileId),
      onDownload: () => _download(match),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {this.badge});

  final String text;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
          if (badge != null) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(46),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accent.withAlpha(110)),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.accent),
              ),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

/// One result row: flag chip, release, stats, download affordance.
class _SubtitleResultTile extends StatelessWidget {
  const _SubtitleResultTile({
    required this.match,
    required this.busy,
    required this.disabled,
    required this.onDownload,
  });

  final SubtitleResult match;
  final bool busy;
  final bool disabled;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: busy ? AppColors.surfaceHighlight : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: (busy || disabled) ? null : onDownload,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: match.hashMatch ? AppColors.accent.withAlpha(120) : AppColors.divider,
              ),
            ),
            child: Row(
              children: <Widget>[
                _FlagChip(code: match.language),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        match.release.isEmpty
                            ? '${match.languageName} subtitle'
                            : match.release,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        <String>[
                          match.languageName,
                          if (match.downloadCount > 0)
                            '${match.downloadCount} downloads',
                          if (match.ratings > 0)
                            '★ ${match.ratings.toStringAsFixed(1)}',
                          if (match.aiTranslated) 'AI-translated',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent),
                  )
                else
                  Icon(
                    disabled
                        ? Icons.download_outlined
                        : Icons.download_rounded,
                    size: 18,
                    color: disabled
                        ? AppColors.textSecondary.withAlpha(90)
                        : AppColors.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tidy country chip — Windows emoji fonts render flags as bare letters,
/// so SALU draws its own two-letter badge instead.
class _FlagChip extends StatelessWidget {
  const _FlagChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final String country = LanguageUtils.countryCode(code).toUpperCase();
    final bool twoLetters = country.length == 2 &&
        country.codeUnitAt(0) >= 65 &&
        country.codeUnitAt(0) <= 90;
    return Container(
      width: 34,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: twoLetters
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF3D5A80), Color(0xFF293D55)],
              )
            : null,
        color: twoLetters ? null : AppColors.surfaceHighlight,
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        twoLetters ? country : '🌐',
        style: TextStyle(
          fontSize: twoLetters ? 10.5 : 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: twoLetters ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}
