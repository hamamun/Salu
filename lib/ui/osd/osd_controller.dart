import 'dart:async';

import 'package:flutter/foundation.dart';

/// The OSD deck's card model and singleton controller (outline · §4).
///
/// ONE slot at the top center: the latest card replaces whatever is up.
/// Discrete transport actions (buttons, keys, video tap) flash the deck;
/// bars never do (they have their own live chips). The deck never wakes
/// the chrome and never takes focus.

/// Which transport mark a card shows (rendered by `osd_deck.dart`).
enum OsdMark { play, pause, previous, next, seekBack, seekForward }

/// Base: every card carries its own lifetime.
sealed class OsdCard {
  const OsdCard({required this.ttl});

  /// How long the card stays up; repeats restart it.
  final Duration ttl;
}

/// A discrete transport flash: mark + optional text (new time or item
/// title).
class OsdTransportCard extends OsdCard {
  const OsdTransportCard({required this.mark, this.text})
      : super(ttl: const Duration(milliseconds: 1000));

  final OsdMark mark;
  final String? text;
}

/// The volume / mute flash (the deck renders the speaker mark + the
/// read-only volume bar itself).
class OsdVolumeCard extends OsdCard {
  const OsdVolumeCard({required this.muted})
      : super(ttl: const Duration(milliseconds: 1000));

  final bool muted;
}

/// The interactive Resume toast: resumed-at time + the Restart action.
class OsdResumeCard extends OsdCard {
  const OsdResumeCard({required this.position})
      : super(ttl: const Duration(milliseconds: 4000));

  final Duration position;
}

/// Singleton deck driver: holds the current card, runs its TTL.
class OsdController {
  OsdController._internal();

  /// The one and only OSD deck controller.
  static final OsdController instance = OsdController._internal();

  /// The card currently on the slot (`null` = empty deck).
  final ValueNotifier<OsdCard?> current = ValueNotifier<OsdCard?>(null);

  Timer? _ttl;
  int _generation = 0;

  /// Whether the interactive Resume toast is up.
  bool get isResumeToast => current.value is OsdResumeCard;

  /// Shows [card], replacing whatever is up; its TTL restarts on every
  /// repeat (a new show is a fresh card).
  void show(OsdCard card) {
    _ttl?.cancel();
    current.value = card;
    final int gen = ++_generation;
    _ttl = Timer(card.ttl, () {
      if (gen == _generation) dismiss();
    });
  }

  /// Empties the slot (also kills the toast's TTL).
  void dismiss() {
    _ttl?.cancel();
    _ttl = null;
    if (current.value != null) current.value = null;
  }

  /// A transport action while the Resume toast shows dismisses the
  /// toast — you've started watching.
  void dismissResumeToast() {
    if (isResumeToast) dismiss();
  }
}
