import 'package:flutter/material.dart';

import '../../core/clock_format.dart';
import '../../core/player_service.dart';
import '../../core/transport_actions.dart';
import '../../theme/app_theme.dart';
import '../osc/controller_panel.dart' show kChromeBlockHeight;
import '../osc/volume_bar.dart';
import '../widgets/glass_capsule.dart';
import '../widgets/transport_marks.dart';
import 'osd_controller.dart';

/// The OSD deck — ONE slot, two "feels" (outline · §4).
///
/// Screen-positioned in `HomeScreen`'s stack at `y = kChromeBlockHeight
/// + 8 = 156 px`, horizontally centered, never anchored to a widget:
/// with the controller visible it reads as a drawer popping down from
/// the block; with the chrome hidden it reads as a small system deck at
/// the top center. Because it sits BELOW the block, a chrome reveal
/// mid-toast never covers it.
///
/// Motion: enter fade + translateY −10 → 0 (160 ms, ease-out), clipped
/// at y = 148 so the top edge never paints over the chrome block; exit
/// fade + 0 → −6 (120 ms, ease-in). A card replacing a live card
/// cross-fades content in place (no re-slide).
///
/// Transient cards are `IgnorePointer` (clicks fall through to the
/// video); only the Resume toast is interactive. The deck never wakes
/// the chrome and never takes focus.
class OsdDeck extends StatefulWidget {
  const OsdDeck({super.key});

  @override
  State<OsdDeck> createState() => _OsdDeckState();
}

class _OsdDeckState extends State<OsdDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slot;
  late final Animation<double> _fade;
  late final Animation<double> _slide; // 0 = rested, 1 = slid up

  OsdCard? _card;

  @override
  void initState() {
    super.initState();
    _slot = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _fade = CurvedAnimation(
      parent: _slot,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<double>(begin: 0, end: 1).animate(_fade);
    OsdController.instance.current.addListener(_onCard);
  }

  @override
  void dispose() {
    OsdController.instance.current.removeListener(_onCard);
    _slot.dispose();
    super.dispose();
  }

  void _onCard() {
    final OsdCard? card = OsdController.instance.current.value;
    if (card != null) {
      _card = card;
      _slot.forward();
      setState(() {});
    } else {
      _slot.reverse().whenCompleteOrCancel(() {
        if (OsdController.instance.current.value == null && mounted) {
          setState(() => _card = null);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final OsdCard? card = _card;
    if (card == null && _slot.isDismissed) return const SizedBox.shrink();

    // The card rests at y = 8 inside the layer (= 156 px absolute).
    // Enter: translateY −10 → 0 (the first 2 px clip at the layer's top
    // edge, so the card never paints over the chrome block). Exit:
    // 0 → −6.
    final bool reversing = _slot.status == AnimationStatus.reverse;
    final double lift = reversing
        ? -6.0 * (1 - _slide.value)
        : -10.0 + 10.0 * _slide.value;

    return Positioned(
      top: kChromeBlockHeight, // the chrome block's bottom edge (= 148)
      left: 0,
      right: 0,
      height: 96,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _fade,
            child: Transform.translate(
              offset: Offset(0, 8 + lift),
              // A card replacing a live card cross-fades in place
              // (100 ms, no re-slide).
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 100),
                transitionBuilder:
                    (Widget child, Animation<double> animation) =>
                        FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ObjectKey(card),
                  child: _buildCard(card!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(OsdCard card) {
    return switch (card) {
      OsdTransportCard c => _TransientCard(child: _transportBody(c)),
      OsdVolumeCard c => _TransientCard(child: _volumeBody(c)),
      OsdResumeCard c => _ResumeToast(card: c),
    };
  }

  Widget _transportBody(OsdTransportCard card) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _mark(card.mark),
        if (card.text != null) ...<Widget>[
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              card.text!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _volumeBody(OsdVolumeCard card) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconTheme.merge(
          data: const IconThemeData(color: AppColors.textPrimary),
          child: SpeakerMark(
            size: 20,
            level: PlayerService.instance.volumeLevel.value,
            muted: card.muted,
          ),
        ),
        const SizedBox(width: 10),
        const VolumeBar(width: 120, readOnly: true),
      ],
    );
  }

  static Widget _mark(OsdMark mark) {
    final Widget child = switch (mark) {
      OsdMark.play => const PlayChevronMark(size: 18),
      OsdMark.pause => const PauseMark(size: 18),
      OsdMark.previous => const PreviousMark(size: 18),
      OsdMark.next => const NextMark(size: 18),
      OsdMark.seekBack => const SeekBackMark(size: 18),
      OsdMark.seekForward => const SeekForwardMark(size: 18),
    };
    return IconTheme.merge(
      data: const IconThemeData(color: AppColors.textPrimary),
      child: child,
    );
  }
}

// ── Card surfaces ──────────────────────────────────────────────────────────

/// Transient (1 s) cards: pure display, clicks fall through.
class _TransientCard extends StatelessWidget {
  const _TransientCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: GlassCapsule(
        radius: 10,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 360),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// The interactive Resume toast:
///
/// ```
/// [ > ]  12:34                    [ ↻  Restart ]
/// ```
///
/// Left: play chevron + compact resumed-at time. Right: the Restart
/// word-action (mark + word, one hover target — quiet gray at rest,
/// mark and word light to white together, no box). Auto-dismiss 4 s;
/// click-outside (a HomeScreen layer) and Esc dismiss it.
class _ResumeToast extends StatefulWidget {
  const _ResumeToast({required this.card});

  final OsdResumeCard card;

  @override
  State<_ResumeToast> createState() => _ResumeToastState();
}

class _ResumeToastState extends State<_ResumeToast> {
  bool _restartHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color tone =
        _restartHovered ? AppColors.textPrimary : AppColors.iconIdle;
    return GlassCapsule(
      radius: 10,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconTheme.merge(
            data: const IconThemeData(color: AppColors.textPrimary),
            child: const PlayChevronMark(size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            formatClockCompact(widget.card.position),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 26),
          // Restart — one hover target: mark and word light together.
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _restartHovered = true),
            onExit: (_) => setState(() => _restartHovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => TransportActions.instance.restart(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconTheme.merge(
                      data: IconThemeData(color: tone),
                      child: const RestartMark(size: 15),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Restart',
                      style: TextStyle(
                        color: tone,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
