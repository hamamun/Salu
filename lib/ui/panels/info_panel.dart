import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/clock_format.dart';
import '../../core/info_collector.dart';
import '../../core/info_controller.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import '../osc/controller_panel.dart' show kChromeBlockHeight;
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// Info's left-edge twin of the playlist. Facts never resize the chrome.
class InfoPanel extends StatefulWidget {
  const InfoPanel({super.key, this.controller});

  /// Optional externally owned controller for engine-free widget tests.
  final InfoController? controller;
  static double widthFor(double width) =>
      math.max(0.0, math.min(322.0, width - 24));

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel>
    with SingleTickerProviderStateMixin {
  final PanelService _panels = PanelService.instance;
  final PlayerService _player = PlayerService.instance;
  late final InfoController _facts;
  late final AnimationController _animation;
  late final CurvedAnimation _curve;
  bool _locked = false;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _facts = widget.controller ?? InfoController.player();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _curve = CurvedAnimation(
      parent: _animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _panels.infoOpen.addListener(_onOpen);
    _player.transportState.addListener(_onPlayback);
    _player.hasMedia.addListener(_onPlayback);
    _onOpen();
  }

  void _onPlayback() {
    if (!_player.hasMedia.value ||
        _player.transportState.value == TransportState.stopped ||
        _player.transportState.value == TransportState.idle) {
      _panels.closeInfo();
    }
  }

  void _onOpen() {
    final bool open = _panels.infoOpen.value;
    if (open) {
      if (!_locked) {
        _locked = true;
        ChromeLock.instance.acquire();
      }
      _animation.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _panels.infoOpen.value) _focus.requestFocus();
      });
    } else {
      if (_locked) {
        _locked = false;
        ChromeLock.instance.release();
      }
      _animation.reverse();
      if (_focus.hasFocus) _focus.unfocus();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _panels.infoOpen.removeListener(_onOpen);
    _player.transportState.removeListener(_onPlayback);
    _player.hasMedia.removeListener(_onPlayback);
    if (_locked) ChromeLock.instance.release();
    if (widget.controller == null) _facts.dispose();
    _focus.dispose();
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool open = _panels.infoOpen.value;
    return IgnorePointer(
      ignoring: !open,
      child: Focus(
        focusNode: _focus,
        canRequestFocus: open,
        onKeyEvent: (_, KeyEvent event) {
          if (open &&
              event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _panels.closeInfo();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = InfoPanel.widthFor(constraints.maxWidth);
            return Stack(
              children: <Widget>[
                // Chrome controls stay usable. The picture's closing click is
                // consumed, never forwarded to the transport.
                Positioned.fill(
                  top: kChromeBlockHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _panels.closeInfo,
                    onSecondaryTap: _panels.closeInfo,
                  ),
                ),
                Positioned(
                  top: kChromeBlockHeight,
                  left: 0,
                  bottom: 0,
                  width: width,
                  child: AnimatedBuilder(
                    animation: _curve,
                    builder: (BuildContext context, Widget? child) => Opacity(
                      opacity: _curve.value,
                      child: Transform.translate(
                        offset: Offset(-(1 - _curve.value) * width, 0),
                        child: child,
                      ),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      onSecondaryTap: _panels.closeInfo,
                      child: ClipPath(
                        clipper: const _TopRightRadius(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            key: const ValueKey<String>('info-panel-surface'),
                            decoration: const BoxDecoration(
                              color: AppColors.glass,
                              border: Border(
                                right: BorderSide(
                                  color: AppColors.surfaceOutline,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                SizedBox(
                                  height: 30,
                                  child: Row(
                                    children: <Widget>[
                                      const IconTheme(
                                        data: IconThemeData(
                                          color: AppColors.iconIdle,
                                        ),
                                        child: InfoMark(size: 18),
                                      ),
                                      const Spacer(),
                                      SaluIconButton(
                                        size: 30,
                                        tooltip: 'Close',
                                        onTap: _panels.closeInfo,
                                        child: const CloseMark(size: 16),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListenableBuilder(
                                    listenable: _facts,
                                    builder: (BuildContext context, Widget? _) {
                                      final InfoSnapshot? facts =
                                          _facts.snapshot;
                                      if (facts == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return ListenableBuilder(
                                        listenable: Listenable.merge(
                                          <Listenable>[
                                            _player.position,
                                            _player.duration,
                                          ],
                                        ),
                                        builder: (
                                          BuildContext context,
                                          Widget? _,
                                        ) =>
                                            InfoRows(
                                          snapshot: facts,
                                          position: _player.position.value,
                                          duration: _player.duration.value,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The view only formats the three live clocks. Frozen rows aren't recollected.
class InfoRows extends StatelessWidget {
  const InfoRows({
    super.key,
    required this.snapshot,
    required this.position,
    required this.duration,
  });
  final InfoSnapshot snapshot;
  final Duration position, duration;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<InfoRow>> groups = <String, List<InfoRow>>{};
    for (final String name in <String>[
      'Identity',
      'Picture',
      'Sound',
      'Clock & file',
      'SALU',
      'Stream',
    ]) {
      final List<InfoRow> rows = <InfoRow>[];
      if (name == 'Clock & file' && snapshot.local) {
        if (duration > Duration.zero) {
          rows.add(InfoRow('Duration', formatClockCompact(duration)));
        }
        rows.add(
          InfoRow(
            'Position',
            formatClockCompact(
              position < Duration.zero ? Duration.zero : position,
            ),
          ),
        );
        if (duration > Duration.zero) {
          rows.add(
            InfoRow(
              'Remaining',
              formatClockCompact(
                position > duration ? Duration.zero : duration - position,
              ),
            ),
          );
        }
      }
      rows.addAll(snapshot.groups[name] ?? const <InfoRow>[]);
      if (rows.isNotEmpty) groups[name] = rows;
    }
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final MapEntry<String, List<InfoRow>> group
                in groups.entries) ...<Widget>[
              if (group.key != groups.keys.first) ...<Widget>[
                const SizedBox(height: 10),
                const SizedBox(
                  height: 1,
                  width: double.infinity,
                  child: ColoredBox(color: AppColors.divider),
                ),
              ],
              Text(
                group.key.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.84,
                  color: AppColors.textSecondary,
                ),
              ),
              for (final InfoRow row in group.value)
                SizedBox(
                  height: 22,
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 78,
                        child: Text(
                          row.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopRightRadius extends CustomClipper<Path> {
  const _TopRightRadius(this.radius);
  final double radius;
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width - radius, 0)
    ..quadraticBezierTo(size.width, 0, size.width, radius)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_TopRightRadius old) => old.radius != radius;
}
