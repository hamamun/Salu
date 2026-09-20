import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';

import '../../core/info_controller.dart';
import '../../core/panel_service.dart';
import '../../core/player_service.dart';
import '../../core/queue_service.dart';
import '../../core/transport_actions.dart';
import '../../core/ui_lock.dart';
import '../widgets/dot_grid_icon.dart';
import '../widgets/glass_capsule.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';
import 'hover_chip.dart';

/// The secondary-button handler lives only on the full Player canvas. Web and
/// mini never build it. Panels above this layer win hit testing; the service
/// also enforces close-first for panels without a full-window barrier.
class RightMenuTarget extends StatelessWidget {
  const RightMenuTarget({super.key, required this.anchor, required this.child});
  final ValueNotifier<Offset> anchor;
  final Widget child;
  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (PointerDownEvent event) {
          if (event.buttons != kSecondaryButton) return;
          anchor.value = event.localPosition;
          PanelService.instance.handleSecondaryClick();
        },
        child: child,
      );
}

/// The full-canvas secondary strip. Remote is the deliberate rightmost door
/// after Settings; it is available only on the Player canvas, never mini/Web.
class RightMenu extends StatefulWidget {
  const RightMenu({
    super.key,
    required this.anchor,
    required this.onSettings,
    this.onRemote,
  });
  final ValueNotifier<Offset> anchor;
  final VoidCallback onSettings;
  final VoidCallback? onRemote;

  static const double height = 42;
  static double widthFor(bool channel) => channel ? 118 : 198;

  static Offset placement(Offset cursor, Size window, Size strip) {
    final double x = (cursor.dx - strip.width / 2)
        .clamp(12.0, math.max(12.0, window.width - strip.width - 12))
        .toDouble();
    final double below = cursor.dy + 10;
    final double y = (below + strip.height <= window.height - 12
            ? below
            : cursor.dy - 10 - strip.height)
        .clamp(12.0, math.max(12.0, window.height - strip.height - 12))
        .toDouble();
    return Offset(x, y);
  }

  @override
  State<RightMenu> createState() => _RightMenuState();
}

class _RightMenuState extends State<RightMenu>
    with SingleTickerProviderStateMixin {
  final PanelService _panels = PanelService.instance;
  final PlayerService _player = PlayerService.instance;
  late final AnimationController _animation;
  late final CurvedAnimation _curve;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _curve = CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic);
    _panels.rightMenuOpen.addListener(_onOpen);
    _onOpen();
  }

  void _onOpen() {
    if (_panels.rightMenuOpen.value) {
      if (!_locked) {
        _locked = true;
        ChromeLock.instance.acquire();
      }
      _animation.forward(from: 0);
    } else {
      if (_locked) {
        _locked = false;
        ChromeLock.instance.release();
      }
      _animation.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _panels.rightMenuOpen.removeListener(_onOpen);
    if (_locked) ChromeLock.instance.release();
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }

  void _door(VoidCallback action) {
    _panels.closeRightMenu();
    action();
  }

  @override
  Widget build(BuildContext context) {
    // Doors remove the strip before their own surface is mounted. No fading
    // barrier survives behind a modal or consumes a click after dismissal.
    if (!_panels.rightMenuOpen.value) return const SizedBox.shrink();
    return Focus(
      autofocus: true,
      onKeyEvent: (_, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _panels.closeRightMenu();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          widget.anchor,
          _player.shuffleOn,
          _player.repeatMode,
          _player.hasMedia,
          _player.transportState,
          _player.currentPath,
          QueueService.instance.items,
        ]),
        builder: (BuildContext context, Widget? _) {
          final bool channel = QueueService.instance.isChannelList;
          final bool suspended = _player.shuffleOn.value &&
              _player.repeatMode.value == RepeatMode.one;
          final bool ready = infoAvailable;
          final bool shuffle = ready && _player.shuffleOn.value && !suspended;
          final RepeatMode repeat = _player.repeatMode.value;
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size size = Size(
                RightMenu.widthFor(channel),
                RightMenu.height,
              );
              final Offset at = RightMenu.placement(
                widget.anchor.value,
                constraints.biggest,
                size,
              );
              return Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _panels.closeRightMenu,
                      onSecondaryTap: _panels.closeRightMenu,
                    ),
                  ),
                  Positioned(
                    left: at.dx,
                    top: at.dy,
                    width: size.width,
                    height: size.height,
                    child: FadeTransition(
                      opacity: _curve,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: .96,
                          end: 1,
                        ).animate(_curve),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          onSecondaryTap: _panels.closeRightMenu,
                          child: GlassCapsule(
                            radius: 12,
                            // Container adds its 1px border to padding: totals are 6/8.
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 7,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (!channel) ...<Widget>[
                                  _button(
                                    'Shuffle${suspended ? ' · suspended' : ''}',
                                    ShuffleMark(size: 18, quiet: !shuffle),
                                    () => unawaited(TransportActions.instance.toggleShuffle()),
                                    active: shuffle,
                                  ),
                                  const SizedBox(width: 6),
                                  _button(
                                    'Repeat · ${repeat.name}',
                                    RepeatMark(
                                      size: 18,
                                      quiet: !ready || repeat == RepeatMode.off,
                                      bead: repeat == RepeatMode.one,
                                    ),
                                    () => unawaited(TransportActions.instance.cycleRepeat()),
                                    active: ready && repeat != RepeatMode.off,
                                  ),
                                  const SizedBox(width: 14),
                                ],
                                _button(
                                  'Info',
                                  const InfoMark(size: 18),
                                  () => _door(_panels.openInfo),
                                  enabled: ready,
                                  active: _panels.infoOpen.value,
                                ),
                                const SizedBox(width: 6),
                                _button(
                                  'Settings',
                                  const DotGridIcon(size: 18),
                                  () => _door(widget.onSettings),
                                ),
                                const SizedBox(width: 6),
                                _button(
                                  'Remote',
                                  const QrMark(size: 18),
                                  () => _door(widget.onRemote ?? () {}),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _button(
    String label,
    Widget mark,
    VoidCallback action, {
    bool active = false,
    bool enabled = true,
  }) {
    // Tooltip handles delay, screen-edge placement and overlay lifetime. Its
    // visible surface is the SAME HoverChip the bars already use, fitted to text.
    final TextPainter measure = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          letterSpacing: .3,
          fontFamily: 'Segoe UI Variable',
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double width = measure.width + 16;
    measure.dispose();
    return Tooltip(
      key: ValueKey<String>(label.split(' · ').first),
      waitDuration: const Duration(milliseconds: 600),
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      decoration: const BoxDecoration(),
      excludeFromSemantics: true,
      richMessage: WidgetSpan(
        child: HoverChip(label: label, width: width),
      ),
      child: Semantics(
        label: label,
        button: true,
        enabled: enabled,
        child: SaluIconButton(
          size: 30,
          active: active,
          enabled: enabled,
          onTap: action,
          child: mark,
        ),
      ),
    );
  }
}
