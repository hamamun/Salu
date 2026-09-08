/// The failure-skip decision (playlist_imp.md §10.8 · §10.8a-ii, M-4b).
///
/// Pure bookkeeping, no engine and no UI, so the rule the owner locked
/// can be exercised on its own:
///
/// - a channel fails → toast **"Failed to load"** + its name, then open
///   the **next channel in list order** and play it;
/// - **three consecutive failures stop the cascade** — that is a dead
///   provider (expired credentials, no internet), not a dead channel,
///   and stampeding 50 000 entries with a toast each is the worse
///   failure mode. SALU stops on the third and leaves the toast up;
/// - the counter resets on **any successful playback** and on **any
///   manual pick** (row click, Prev/Next) — a deliberate choice is never
///   part of a cascade;
/// - **never wrap**: a failing tail stops, it does not loop to index 0;
/// - one dead channel often emits several mpv error lines — only the
///   first counts as a strike, and only one skip is fired.
class ChannelSkipPolicy {
  /// How many consecutive failures stop the cascade (FINAL: 3).
  static const int strikeLimit = 3;

  int _strikes = 0;
  int _failedIndex = -1;
  bool _busy = false;

  /// Consecutive channel failures counted so far.
  int get strikes => _strikes;

  /// Whether the cascade guard has already stopped the skipping.
  bool get stopped => _strikes >= strikeLimit;

  /// Successful playback — the cascade is over (§10.8a-ii).
  void recordSuccess() {
    _strikes = 0;
    _failedIndex = -1;
  }

  /// A deliberate pick (row click, Prev/Next) — never part of a cascade.
  void recordManualPick() {
    _strikes = 0;
    _failedIndex = -1;
  }

  /// The skip's own `open` finished, so later errors belong to whatever
  /// is loaded now.
  void settle() => _busy = false;

  /// Answers one failure report for the channel at [index] of a list of
  /// [count] channels.
  ///
  /// Returns what the caller must do; [ChannelSkipAction.ignore] means
  /// the report was a duplicate (a second error line for the same dead
  /// channel, or an error arriving while the skip is still opening) and
  /// nothing at all should happen — no toast, no strike, no skip.
  ChannelSkipAction onFailure({required int index, required int count}) {
    if (_busy || index < 0 || index >= count) {
      return ChannelSkipAction.ignore;
    }
    if (index == _failedIndex) return ChannelSkipAction.ignore;
    _failedIndex = index;
    _strikes++;
    if (_strikes >= strikeLimit) return ChannelSkipAction.stop;
    if (index >= count - 1) return ChannelSkipAction.stop; // never wrap
    _busy = true;
    return ChannelSkipAction.skip;
  }

  /// Forgets everything (a fresh list, a clear).
  void reset() {
    _strikes = 0;
    _failedIndex = -1;
    _busy = false;
  }
}

/// What [ChannelSkipPolicy.onFailure] tells the caller to do.
enum ChannelSkipAction {
  /// A duplicate report — do nothing at all.
  ignore,

  /// Toast "Failed to load" + the channel's name, then open and play the
  /// **next** channel.
  skip,

  /// Toast "Failed to load" + the channel's name, and stop there: the
  /// cascade guard tripped, or this was the last channel (no wrap).
  stop,
}
