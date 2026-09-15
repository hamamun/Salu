import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/audio_display_service.dart';
import '../../core/audio_tag_fields.dart';
import '../../theme/app_theme.dart';

/// Mode C (lrc.md L2–L6, L29–L33): album art at a FIXED anchor, then the
/// standard metadata fields below it — four rows, never more.
///
/// The invariant this whole widget exists to keep: **the art never moves.**
/// The earlier version centered `the art + every tag the file happened to
/// carry` as one column, so each extra tag lifted the art half a line — a
/// file with a lyrics blob parked in a tag visibly jumped. Here the art
/// size comes from the canvas alone and the text block is a reserved slot
/// whose height is constant whatever the file carries (L30).
///
/// No scrolling, no shrink-to-fit, no labels: a value too long for its row
/// ellipsizes (L31), a missing field is not drawn, and the rows are read by
/// type size alone — title / artist / album / context.
class AlbumArtView extends StatelessWidget {
  const AlbumArtView({super.key});

  // ── The art: canvas-derived only, never content-derived ──────────────

  /// The art takes this fraction of the canvas height — one constant, so
  /// the window is all that decides the size.
  static const double _artFractionOfHeight = 0.52;
  static const double _artMin = 140;
  static const double _artMax = 520;

  /// Room kept at the sides, so wide artwork still leaves the text rows
  /// their own measure.
  static const double _sidePad = 80;
  static const double _artToTextGap = 28;

  // ── The reserved text block ───────────────────────────────────────────
  //
  // Each row height is its font size × its `height` multiplier, so a slot
  // and the text inside it cannot drift apart when a style changes.

  static const double _titleSize = 23;
  static const double _titleLineHeight = 1.25;

  /// The title may run to two lines; its slot always holds two.
  static const double _titleLines = 2;
  static const double _artistSize = 16;
  static const double _albumSize = 14;
  static const double _contextSize = 13;
  static const double _rowLineHeight = 1.3;
  static const double _titleToArtistGap = 8;
  static const double _artistToAlbumGap = 4;
  static const double _albumToContextGap = 12;

  static double _line(double size, double multiplier) => size * multiplier;

  static double get _titleSlot =>
      _line(_titleSize, _titleLineHeight) * _titleLines;
  static double get _artistRow => _line(_artistSize, _rowLineHeight);
  static double get _albumRow => _line(_albumSize, _rowLineHeight);
  static double get _contextRow => _line(_contextSize, _rowLineHeight);

  /// The block's height — constant, because it is the sum of the SLOTS and
  /// not the sum of the rows that happen to be present. This is what pins
  /// the art: 4 slots reserved, any subset of them filled.
  static double get _textBlockHeight =>
      _titleSlot +
          _titleToArtistGap +
          _artistRow +
          _artistToAlbumGap +
          _albumRow +
          _albumToContextGap +
          _contextRow;

  static const TextStyle _titleStyle = TextStyle(
    fontSize: _titleSize,
    fontWeight: FontWeight.w600,
    height: _titleLineHeight,
    color: AppColors.textPrimary,
  );

  static const TextStyle _artistStyle = TextStyle(
    fontSize: _artistSize,
    fontWeight: FontWeight.w400,
    height: _rowLineHeight,
    color: AppColors.textSecondary,
  );

  static TextStyle get _albumStyle => _artistStyle.copyWith(
        fontSize: _albumSize,
        color: AppColors.textSecondary.withAlpha(170),
      );

  static TextStyle get _contextStyle => _artistStyle.copyWith(
        fontSize: _contextSize,
        color: AppColors.textSecondary.withAlpha(140),
      );

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
                // Both sizes below are functions of the CANVAS alone — no
                // term of them reads `info`, which is the whole point: the
                // art cannot be pushed around by what the tags turn out to
                // be (L30).
                final double art = _artSize(constraints);
                final double text = _textSize(constraints, art);
                return Center(
                  child: SizedBox(
                    height: art + _artToTextGap + text,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          height: art,
                          child: Center(
                            child: _Cover(
                              size: art,
                              bytes: audio.coverBytes.value,
                            ),
                          ),
                        ),
                        const SizedBox(height: _artToTextGap),
                        if (text > 0)
                          SizedBox(
                            height: text,
                            child: ClipRect(child: _rows(info)),
                          ),
                      ],
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

  /// Art edge length — from the canvas alone. The floor/ceiling keep it in
  /// the design's range, and the room it is left with keeps it from ever
  /// eating the text block. Nothing here reads the metadata.
  static double _artSize(BoxConstraints constraints) {
    final double height = constraints.maxHeight;
    final double width = constraints.maxWidth;
    final double room = height - _artToTextGap - _textBlockHeight;
    double size = math.min(
      height * _artFractionOfHeight,
      width - _sidePad * 2,
    );
    size = math.max(size, _artMin);
    // A window too short for the design floor gives the art whatever it has
    // (a shrunken square beats clipped text); a normal one never gets here.
    size = math.min(size, math.max(room, 64));
    return math.min(size, _artMax).toDouble();
  }

  /// The reserved text block, cut down only if the window is too short to
  /// hold all four rows — the rows that fall outside are clipped, never
  /// allowed to shove the art around.
  static double _textSize(BoxConstraints constraints, double art) {
    final double room = constraints.maxHeight - art - _artToTextGap;
    return math.max(0.0, math.min(_textBlockHeight, room)).toDouble();
  }

  /// The four rows, top-packed inside their reserved block. A missing field
  /// leaves no hole — and moves nothing outside the block, because the block
  /// itself is fixed.
  Widget _rows(AudioTrackInfo info) {
    final List<Widget> rows = <Widget>[
      // Bottom-aligned in its two-line slot: a one-line title sits directly
      // above the artist, and a two-line title only grows upward.
      SizedBox(
        height: _titleSlot,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _text(info.title, 2, _titleStyle),
        ),
      ),
    ];

    // L33 — a file with no standard metadata shows its name and nothing
    // else; the block keeps its full height so the art does not move.
    if (!info.minimal) {
      final String contextLine = info.contextParts.join(' · ');
      if (info.artist != null) {
        rows
          ..add(const SizedBox(height: _titleToArtistGap))
          ..add(_row(info.artist!, _artistRow, _artistStyle));
      }
      if (info.album != null) {
        rows
          ..add(const SizedBox(height: _artistToAlbumGap))
          ..add(_row(info.album!, _albumRow, _albumStyle));
      }
      if (contextLine.isNotEmpty) {
        rows
          ..add(const SizedBox(height: _albumToContextGap))
          ..add(_row(contextLine, _contextRow, _contextStyle));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _row(String value, double height, TextStyle style) {
    return SizedBox(height: height, child: _text(value, 1, style));
  }

  Widget _text(String value, int maxLines, TextStyle style) {
    return Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style,
    );
  }
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
/// never a broken or empty box. L33 puts it in the art slot for a file with
/// no metadata at all.
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
