import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/channel_logo_service.dart';

/// A channel row's logo slot (playlist_imp.md §10.4).
///
/// A small fixed box before the name — [size] × [size] (24 by default) —
/// so names never jump as images arrive. The artwork keeps its native
/// colours (follow.md §1.7's narrow exception) and is display-only: it
/// is not independently focusable or clickable, and a missing, invalid
/// or failed image leaves the slot quietly empty — no spinner, no error
/// mark, no retry, and never the failure toast (a logo failure is not a
/// channel failure).
///
/// Images decode at display size (`cacheWidth`/`cacheHeight` from the
/// device pixel ratio) and bind to the logo address, never a recycled
/// row index: parents key this widget by the address, and a changed
/// address refetches instead of flashing the previous row's image.
class ChannelLogo extends StatefulWidget {
  const ChannelLogo({super.key, required this.logoUrl, this.size = 24});

  /// Playlist-supplied image address (`null` = no logo for this row).
  /// Never rendered as text, never logged (§10.10e).
  final String? logoUrl;

  /// Square slot side length.
  final double size;

  @override
  State<ChannelLogo> createState() => _ChannelLogoState();
}

class _ChannelLogoState extends State<ChannelLogo> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _request(widget.logoUrl);
  }

  @override
  void didUpdateWidget(ChannelLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoUrl != widget.logoUrl) {
      _future = _request(widget.logoUrl);
    }
  }

  static Future<Uint8List?>? _request(String? logoUrl) =>
      logoUrl == null || logoUrl.isEmpty
          ? null
          : ChannelLogoService.instance.fetch(logoUrl);

  @override
  Widget build(BuildContext context) {
    final Future<Uint8List?>? future = _future;
    if (future == null) return SizedBox.square(dimension: widget.size);
    final int pixels =
        (widget.size * MediaQuery.of(context).devicePixelRatio)
            .round()
            .clamp(1, 256)
            .toInt();
    return SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<Uint8List?>(
        future: future,
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
          final Uint8List? bytes = snap.data;
          if (bytes == null || bytes.isEmpty) {
            return const SizedBox.shrink();
          }
          return Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            cacheWidth: pixels,
            cacheHeight: pixels,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder:
                (BuildContext context, Object _, StackTrace? __) =>
                    const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
