import '../../core/sub_delay_service.dart' show formatSubDelay;
import '../osd/osd_controller.dart';

/// The mini bar's ONE feedback channel (mini.md §6).
///
/// The OSD deck does not exist in mini, so every card the full window would
/// have flashed becomes a transient title swap instead: `Volume 45 %`,
/// `Muted`, `+15 s · 01:12:34`, `Stopped — queue parked`, the next track or
/// channel name, `→ 01:23 · 02:19 left`. Subtle, same size, same color
/// family — never a card, never an overlay.
///
/// The mapping lives here — pure, no widget, no player — so the deck's facts
/// ([OsdCard], handed over by `TransportActions.onCard`) and the bar's copy
/// can never disagree, and so the copy is unit-testable on its own.
///
/// `null` means "no swap": the event either has no §6 line of its own (the
/// play/pause mark's own `>` ↔ `II` swap is the answer there) or it belongs
/// to a surface that does not exist in mini (a resume toast, a subtitle
/// fetch, a folder whisper).
String? miniSwapText(
  OsdCard card, {
  required double volume,
  required bool muted,
}) {
  if (card is OsdTransportCard) {
    switch (card.mark) {
      case OsdMark.previous:
      case OsdMark.next:
        // §6 — "next track / channel name": the deck's own label, which is
        // the channel's display name in channel mode.
        return card.text;
      case OsdMark.seekBack:
      case OsdMark.seekForward:
        // §6 — `+15 s · 01:12:34`, from the deck's `+15s  01:12:34`.
        return _seekText(card.text);
      case OsdMark.play:
      case OsdMark.pause:
        return null;
    }
  }
  if (card is OsdVolumeCard) {
    return volumeSwapText(volume, muted);
  }
  if (card is OsdSubDelayCard) {
    // The subtitle-sync keys stay live while the bar has focus (§5); the
    // offset with no panel to watch speaks in the deck's own words.
    return 'sub ${formatSubDelay(card.delay)}';
  }
  return null;
}

/// §6's two volume lines — `Muted` / `Volume 45 %` — in one place, so the
/// speaker mark, the volume keys and the wheel all say the same thing. The
/// wheel has no card to carry it (it never leaves the bar), which is why
/// the rule is a function and not a branch inside the mapper.
String volumeSwapText(double volume, bool muted) =>
    muted ? 'Muted' : 'Volume ${volume.round().clamp(0, 100)} %';

/// The deck writes a seek step as `-3s  00:00:20` (sign, seconds, two
/// spaces, the new clock). The bar's own line is `-3 s · 00:00:20`: the
/// number keeps the sign the deck applied, the unit gets its space, and the
/// clock follows a separator instead of a gap.
final RegExp _stepPattern = RegExp(r'^([-+])(\d+)s\s+(.+)$');

String? _seekText(String? deckText) {
  if (deckText == null) return null;
  final RegExpMatch? match = _stepPattern.firstMatch(deckText);
  if (match == null) return deckText; // unexpected shape: never swallow it
  return '${match.group(1)}${match.group(2)} s · ${match.group(3)}';
}
