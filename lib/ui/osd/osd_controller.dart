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

/// The interactive Undo toast (playlist_imp.md §5 — rule 3, no dialogs):
/// names what changed and offers the single allowed word-action, "Undo".
/// Shown for removals, drag-reorders and the absolute Clear playlist.
/// Auto-dismisses after 5 s; clicking "Undo" runs [onUndo] and dismisses.
class OsdUndoCard extends OsdCard {
  const OsdUndoCard({required this.label, required this.onUndo})
      : super(ttl: const Duration(seconds: 5));

  /// What changed (a file name, or "Playlist cleared").
  final String label;

  /// Performs the undo (the panel passes the captured [QueueUndo] token).
  final VoidCallback onUndo;
}

/// The folder auto-load whisper (autoload_imp.md §4): one transient
/// status card naming what just grew around the playing item — "12
/// videos queued from “Season 1”". Pure display, never interactive; a
/// big folder must never silently become the playlist.
class OsdAutoloadCard extends OsdCard {
  const OsdAutoloadCard({
    required this.count,
    required this.audio,
    required this.folder,
  }) : super(ttl: const Duration(milliseconds: 1000));

  /// Rows now in the queue.
  final int count;

  /// Kind word for the copy: `true` → tracks, `false` → videos.
  final bool audio;

  /// Display name of the folder the rows were picked up from.
  final String folder;
}

/// The "Failed to load" card (playlist_imp.md §10.8 · §10.10b): the
/// wording is fixed and the [name] is the **channel's** display label or
/// the **playlist's** name — never a URL, which would carry credentials
/// (§10.10e). Pure display; a failed channel stays put — the viewer zaps.
class OsdFailedCard extends OsdCard {
  const OsdFailedCard({required this.name})
      : super(ttl: const Duration(milliseconds: 2200));

  /// Channel label or playlist name. Never a URL.
  final String name;
}

/// The subtitle engine's cards (cc.md §3.5 · §6.5 · D10). Transient
/// 1-second deck flashes, each spoken at most once per session (the
/// service owns the once-flags). Four shapes:
///
///   · [OsdSubtitleCard.cc]        — `cc not configured` (D11's literal)
///   · [OsdSubtitleCard.checkKey]  — `Subtitles — check key` (401)
///   · [OsdSubtitleCard.limit]     — `Subtitle limit reached` (429/402)
///   · [OsdSubtitleCard.saved]     — `Saved · file` / `Already saved ·
///     file` (manual-fetch results, the D10 manual clause)
///   · [OsdSubtitleCard.signIn]    — `Subtitles — sign in` (manual Save
///     with no stored login: owner's call 2026-09-13 — a deliberate tap
///     must never fail in silence)
///   · [OsdSubtitleCard.downloadFailed] — `Subtitles — download failed`
///     (manual Save whose write/download died)
class OsdSubtitleCard extends OsdCard {
  const OsdSubtitleCard.cc()
      : kind = OsdSubtitleCardKind.ccNotConfigured,
        fileName = null,
        super(ttl: const Duration(seconds: 1));

  const OsdSubtitleCard.checkKey()
      : kind = OsdSubtitleCardKind.checkKey,
        fileName = null,
        super(ttl: const Duration(seconds: 1));

  const OsdSubtitleCard.limit()
      : kind = OsdSubtitleCardKind.limitReached,
        fileName = null,
        super(ttl: const Duration(seconds: 1));

  /// §6.5 result cards: [already] toggles the `Saved · file` /
  /// `Already saved · file` wording.
  const OsdSubtitleCard.saved({required String name, bool already = false})
      : kind = already
            ? OsdSubtitleCardKind.alreadySaved
            : OsdSubtitleCardKind.saved,
        fileName = name,
        super(ttl: const Duration(seconds: 1));

  /// §6.5 manual Save with no stored username/password — `/download`
  /// needs a Bearer token that only `/login` can mint (cc.md §4), and
  /// the password is memory-only (D13), so every restart lands here
  /// until the viewer signs in again. Named, not taught.
  const OsdSubtitleCard.signIn()
      : kind = OsdSubtitleCardKind.signIn,
        fileName = null,
        super(ttl: const Duration(seconds: 1));

  /// §6.5 manual Save that could not be written — the tap deserves an
  /// answer even though the AUTO engine stays silent (D10).
  const OsdSubtitleCard.downloadFailed()
      : kind = OsdSubtitleCardKind.downloadFailed,
        fileName = null,
        super(ttl: const Duration(seconds: 1));

  final OsdSubtitleCardKind kind;

  /// The D8 filename on `saved` / `alreadySaved`, else `null`.
  final String? fileName;
}

enum OsdSubtitleCardKind {
  ccNotConfigured,
  checkKey,
  limitReached,
  saved,
  alreadySaved,
  signIn,
  downloadFailed,
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
