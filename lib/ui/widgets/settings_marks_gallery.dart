import 'package:flutter/material.dart';

import 'settings_marks.dart';

/// Standalone sketch gallery for the Settings-mark candidates
/// (settings_marks.dart). Not part of the app — run it alone:
///
///     flutter run -t lib/ui/widgets/settings_marks_gallery.dart
///
/// Every card shows a large copy, then the mark at caption size (20) and
/// at 16. Hovering runs the candidate's §2 motion: gray → white glide
/// plus the mark's own movement. SALU dark only; nothing behind the marks.

void main() => runApp(const SettingsMarksGalleryApp());

class SettingsMarksGalleryApp extends StatelessWidget {
  const SettingsMarksGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SALU · Settings marks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const _GalleryPage(),
    );
  }
}

class _Candidate {
  const _Candidate(this.name, this.idea, this.motion, this.mark);

  final String name;
  final String idea;

  /// Hover-motion caption (the §2 recipe for this mark).
  final String motion;

  final Widget Function(double motion, double size) mark;
}

final List<_Candidate> _candidates = <_Candidate>[
  _Candidate('Knob', 'hi-fi rotary knob', 'pointer swings +25°',
      (double m, double s) => KnobMark(size: s, motion: m)),
  _Candidate('Hub', 'everything converges', 'ticks 15° to the next detent',
      (double m, double s) => HubMark(size: s, motion: m)),
  _Candidate('Spirit level', 'calibration · the house is level',
      'bubble slides to center',
      (double m, double s) => SpiritLevelMark(size: s, motion: m)),
  _Candidate('Balance', 'the house weighs its choices', 'beam tilts, then levels',
      (double m, double s) => BalanceMark(size: s, motion: m)),
  _Candidate('Dial face', 'instrument panel', 'index tick drops inward',
      (double m, double s) => DialFaceMark(size: s, motion: m)),
  _Candidate('DIP bank', 'the settings plate inside', 'right switch flips down',
      (double m, double s) => DipBankMark(size: s, motion: m)),
  _Candidate('Selector ring', 'six dots · dial plate', 'ring steps 15°',
      (double m, double s) => SelectorRingMark(size: s, motion: m)),
  _Candidate('Cascade', 'six dots · evolved', 'lights only (identity, not control)',
      (double m, double s) => CascadeMark(size: s, motion: m)),
];

class _GalleryPage extends StatelessWidget {
  const _GalleryPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(32, 24, 32, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    'SETTINGS MARK · CANDIDATES',
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 2.2,
                      color: Color(0xFFE8E8E8),
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'hover a card — gray → white + motion',
                    style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
                  Spacer(),
                  Text(
                    '2026-09-28',
                    style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  mainAxisExtent: 240,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _candidates.length,
                itemBuilder: (BuildContext context, int i) =>
                    _CandidateCard(candidate: _candidates[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatefulWidget {
  const _CandidateCard({required this.candidate});

  final _Candidate candidate;

  @override
  State<_CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<_CandidateCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color idle = Color(0xFFA6A6A6);
    const Color lit = Color(0xFFFFFFFF);

    return MouseRegion(
      onEnter: (_) => _hover.forward(),
      onExit: (_) => _hover.reverse(),
      cursor: SystemMouseCursors.click,
      child: AnimatedBuilder(
        animation: _hover,
        builder: (BuildContext context, Widget? _) {
          final double t = Curves.easeOutCubic.transform(_hover.value);
          final Color ink = Color.lerp(idle, lit, t)!;

          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: IconTheme(
                      data: IconThemeData(color: ink),
                      child: widget.candidate.mark(t, 56),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconTheme(
                          data: IconThemeData(color: ink),
                          child: widget.candidate.mark(t, 20),
                        ),
                        const SizedBox(width: 18),
                        IconTheme(
                          data: IconThemeData(color: ink),
                          child: widget.candidate.mark(t, 16),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.candidate.name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.8,
                      color: Color(0xFFE8E8E8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.candidate.idea,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A8A8A),
                    ),
                  ),
                  Text(
                    widget.candidate.motion,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6A6A6A),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
