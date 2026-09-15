import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/audio_display_service.dart';
import '../../theme/app_theme.dart';

/// Mode C (lrc.md L2–L6): album art plus every non-empty metadata field.
/// Missing fields are omitted; the title falls back to the file name.
class AlbumArtView extends StatelessWidget {
  const AlbumArtView({super.key});

  @override
  Widget build(BuildContext context) {
    final AudioDisplayService audio = AudioDisplayService.instance;
    return ColoredBox(
      color: AppColors.videoBackdrop,
      child: SizedBox.expand(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            audio.info,
            audio.coverBytes,
          ]),
          builder: (BuildContext context, Widget? _) {
            final AudioTrackInfo? info = audio.info.value;
            if (info == null) return const SizedBox.expand();
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double art = math
                    .min(
                      constraints.maxHeight * 0.58,
                      constraints.maxWidth - 80,
                    )
                    .clamp(140.0, 520.0)
                    .toDouble();
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _Cover(size: art, bytes: audio.coverBytes.value),
                        const SizedBox(height: 28),
                        Text(
                          info.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (info.artist != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            info.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                          if (info.album != null) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              info.album!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary.withAlpha(170),
                              ),
                            ),
                          ],
                          ...info.additional.entries.map<Widget>(
                            (MapEntry<String, String> entry) => Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Text(
                                '${_metadataLabel(entry.key)}: ${entry.value}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary.withAlpha(190),
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
          },
        ),
      ),
    );
  }
}

String _metadataLabel(String key) {
  return key
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'(?<=[a-z])(?=[A-Z])'), ' ')
      .split(' ')
      .where((String part) => part.isNotEmpty)
      .map((String part) =>
          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

class _Cover extends StatelessWidget {
  const _Cover({required this.size, required this.bytes});

  final double size;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(18);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: AppColors.surfaceOutline, width: 1),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? const _Placeholder()
          : Image.memory(
              bytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) {
                return const _Placeholder();
              },
            ),
    );
  }
}

/// L5 — missing-art placeholder: the SALU logo on the dark backdrop,
/// never a broken or empty box.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.videoBackdrop,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.46,
          heightFactor: 0.46,
          child: Image.asset(
            'assets/images/salu_logo.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stack) {
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }
}
