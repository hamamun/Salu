import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../theme/app_theme.dart';

/// IINA-style About window (Phase 9 · Step 2/3).
///
/// A dedicated, calm panel: the SALU mark up top, the app version, the live
/// `mpv` engine build pulled from the running media_kit instance, credits for
/// the open-source libraries SALU stands on, and clean links to them all.
///
/// The section widget is reused in two places — this floating modal (opened
/// from Settings → About's button) and the Settings → About page itself.
class AboutModal extends StatelessWidget {
  const AboutModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) => const AboutModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SizedBox(
          height: 620,
          child: Stack(
            children: <Widget>[
              const Positioned.fill(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(30, 26, 30, 26),
                  child: AboutSection(),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 19, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The actual About content, embeddable in any scrollable host.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static const List<(String, String, String)> _links =
      <(String, String, String)>[
    (AppInfo.repositoryUrl, 'GitHub repository', 'Source, issues and releases'),
    (AppInfo.mpvUrl, 'mpv', 'The playback engine behind libmpv-2.dll'),
    (AppInfo.mediaKitUrl, 'media_kit', 'Flutter bindings for libmpv / libplacebo'),
    (AppInfo.ytDlpUrl, 'yt-dlp', 'Web & IPTV stream resolver'),
    (AppInfo.opensubtitlesUrl, 'OpenSubtitles', 'The subtitle database behind Phase 7'),
    (AppInfo.flutterUrl, 'Flutter', 'Everything is a widget'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset(
            'assets/images/salu_logo.png',
            width: 108,
            height: 108,
            filterQuality: FilterQuality.high,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
              return const Icon(Icons.play_circle_outline,
                  size: 96, color: AppColors.textSecondary);
            },
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'SALU',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 8,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${AppInfo.fullVersion}  ·  build ${AppInfo.buildNumber}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        const Text(
          AppInfo.tagline,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 20),
        const _EngineCard(),
        const SizedBox(height: 22),
        const _CreditsHeader(),
        const SizedBox(height: 8),
        for (final (String url, String name, String what) in _links)
          _LinkTile(url: url, name: name, what: what),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 10),
        const Text(
          'With thanks to the IINA project for the interface language SALU '
          'speaks, and to every open-source maintainer whose work made this '
          'player possible.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// Live mpv version card — the string is read from the actual running engine
/// (Phase 9 · Step 2), so it always matches the shipped libmpv build.
class _EngineCard extends StatelessWidget {
  const _EngineCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: const <Widget>[
          const _EngineRow(
            label: 'Media engine',
            valueBuilder: AppInfo.mpvEngineVersion,
            fallback: 'libmpv (media_kit)',
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Interface',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
              Text('Flutter · Windows',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EngineRow extends StatelessWidget {
  const _EngineRow({required this.label, required this.valueBuilder, required this.fallback});

  final String label;
  final Future<String?> Function() valueBuilder;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textSecondary)),
        FutureBuilder<String?>(
          future: valueBuilder(),
          builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
            final String? value = snapshot.data;
            return Text(
              (value == null || value.isEmpty) ? fallback : 'mpv $value',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            );
          },
        ),
      ],
    );
  }
}

class _CreditsHeader extends StatelessWidget {
  const _CreditsHeader();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Credits & Links',
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.url, required this.name, required this.what});

  final String url;
  final String name;
  final String what;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => AppInfo.openExternal(url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        what,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new_rounded,
                    size: 14, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
