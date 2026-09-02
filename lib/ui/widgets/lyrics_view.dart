import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/lyrics_parser.dart';
import '../../core/player_service.dart';
import '../../theme/app_theme.dart';

/// The scrolling, synced lyrics panel (Phase 7 · Step 2).
///
/// Injected next to the album art in Music Mode whenever a `.lrc` sidecar
/// exists for the current track. A [ScrollController] is driven by the mpv
/// position stream so the line being sung stays perfectly centred; the active
/// line glows bright white while its neighbours fade to gray. Clicking any
/// line seeks the audio straight to its timestamp (interactive sync).
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, this.width = 430, this.height = 470});

  final double width;
  final double height;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const double _lineHeight = 46;
  static const Duration _autoScrollResume = Duration(seconds: 6);
  static const Duration _followDuration = Duration(milliseconds: 420);

  final ScrollController _scroll = ScrollController();
  final PlayerService _player = PlayerService.instance;

  int _activeIndex = -1;
  bool _userPinned = false;
  Timer? _resumeTimer;

  LyricsDocument? get _doc => LyricsController.instance.document;

  @override
  void initState() {
    super.initState();
    LyricsController.instance.addListener(_onLyricsSwapped);
    _player.position.addListener(_onPositionChanged);
    _onPositionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _follow(animated: false);
    });
  }

  @override
  void dispose() {
    LyricsController.instance.removeListener(_onLyricsSwapped);
    _player.position.removeListener(_onPositionChanged);
    _resumeTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// A different `.lrc` was loaded (or unloaded) — reset the viewport.
  void _onLyricsSwapped() {
    if (!mounted) return;
    setState(() {
      _activeIndex = _doc == null ? -1 : _doc!.activeIndexAt(_player.position.value);
      _userPinned = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _follow(animated: false);
    });
  }

  void _onPositionChanged() {
    final LyricsDocument? doc = _doc;
    if (doc == null) return;
    final int index = doc.activeIndexAt(_player.position.value);
    if (index == _activeIndex) return;
    if (!mounted) return;
    setState(() => _activeIndex = index);
    if (!_userPinned) _follow();
  }

  /// Smoothly keeps line [_activeIndex] vertically centred.
  void _follow({bool animated = true}) {
    if (!_scroll.hasClients || _activeIndex < 0) return;
    final double viewport = _scroll.position.viewportDimension;
    final double target = _activeIndex * _lineHeight +
        _lineHeight / 2 +
        _edgePadding -
        viewport / 2;
    final double min = _scroll.position.minScrollExtent;
    final double max = _scroll.position.maxScrollExtent;
    final double offset = target.clamp(min, max).toDouble();
    if (animated) {
      unawaited(_scroll.animateTo(
        offset,
        duration: _followDuration,
        curve: Curves.easeOutCubic,
      ));
    } else {
      _scroll.jumpTo(offset);
    }
  }

  /// Blank space above the first / below the last line so either can be
  /// centred in the viewport.
  double get _edgePadding =>
      ((widget.height - _headerHeight - _lineHeight) / 2).clamp(0.0, 10000.0);

  static const double _headerHeight = 44;

  /// Manual wheel/drag scrolling pins the view for a few seconds; auto-scroll
  /// then glides back onto the line currently being sung.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _pinTemporarily();
    }
    return false;
  }

  void _pinTemporarily() {
    _userPinned = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_autoScrollResume, () {
      _resumeTimer = null;
      if (!mounted) return;
      setState(() => _userPinned = false);
      _follow();
    });
  }

  void _seekToLine(int index) {
    final LyricsDocument? doc = _doc;
    if (doc == null || index < 0 || index >= doc.lines.length) return;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _userPinned = false;
    setState(() => _activeIndex = index);
    _follow();
    // Interactive sync: jump the engine to the line's exact timestamp.
    unawaited(_player.seek(doc.displayTime(doc.lines[index])));
    _player.emitOsd('Lyrics sync · ${index + 1}/${doc.lines.length}');
  }

  @override
  Widget build(BuildContext context) {
    final LyricsDocument? doc = _doc;
    if (doc == null || !LyricsController.instance.visible) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: <Widget>[
                _buildHeader(doc),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.symmetric(vertical: _edgePadding),
                      itemExtent: _lineHeight,
                      itemCount: doc.lines.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _buildLine(doc, index);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LyricsDocument doc) {
    return SizedBox(
      height: _headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.queue_music_rounded,
                size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            const Text(
              'LYRICS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            if (doc.title.isNotEmpty || doc.artist.isNotEmpty)
              Flexible(
                child: Text(
                  <String>[doc.artist, doc.title]
                      .where((String s) => s.isNotEmpty)
                      .join(' — '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ),
            IconButton(
              tooltip: 'Hide lyrics',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.visibility_off_outlined,
                  size: 16, color: AppColors.textSecondary),
              onPressed: LyricsController.instance.hide,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLine(LyricsDocument doc, int index) {
    final LyricsLine line = doc.lines[index];
    final bool active = index == _activeIndex;
    // Neighbouring lines keep readable but dim; distance fades them out.
    final int distance = (index - _activeIndex).abs();
    final double alpha = active
        ? 1.0
        : (1.0 - distance * 0.16).clamp(0.18, 0.85).toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _seekToLine(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          style: TextStyle(
            fontSize: active ? 20 : 15.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active
                ? AppColors.textPrimary
                : AppColors.textSecondary.withAlpha((alpha * 255).round()),
            height: 1.25,
          ),
          child: Text(
            line.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
