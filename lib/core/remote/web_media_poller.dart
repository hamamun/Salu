import 'dart:async';

/// Completion-based web-media find loop (pc_part.md Part F4).
///
/// Replaces a periodic timer whose async callback could overlap itself.
/// Calling [start] again while a delay or a read is already outstanding
/// does not submit a second script and does not discard that result.
/// [stop] does discard it. A failed read reschedules; it cannot silently
/// stop the loop.
class WebMediaPoller {
  WebMediaPoller({
    required this.shouldPoll,
    required this.read,
    required this.apply,
    required this.generationOf,
    this.interval = const Duration(milliseconds: 500),
    this.onStopped,
  });

  final bool Function() shouldPoll;
  final Future<Object?> Function() read;
  final void Function(Object? raw) apply;
  final int Function() generationOf;
  final Duration interval;
  final void Function()? onStopped;

  int _generation = 0;
  bool _active = false;
  bool _started = false;
  Timer? _timer;

  bool get active => _active;

  void start() {
    if (!shouldPoll()) {
      if (_started || _active || _timer != null) stop();
      return;
    }
    _started = true;
    // A pending delay or an in-flight read is already the one operation.
    // Bumping the generation here would discard a result that is still
    // about this page, and arming again would overlap the script.
    if (_active || _timer != null) return;
    _arm(_generation, Duration.zero);
  }

  void stop() {
    _generation++;
    _started = false;
    _timer?.cancel();
    _timer = null;
    onStopped?.call();
  }

  void _arm(int generation, Duration delay) {
    _timer?.cancel();
    if (generation != _generation || !shouldPoll()) {
      _timer = null;
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_tick(generation));
    });
  }

  Future<void> _tick(int generation) async {
    if (generation != _generation || !shouldPoll()) return;
    if (_active) return;
    _active = true;
    final int surface = generationOf();
    try {
      final Object? raw = await read();
      if (generation == _generation &&
          shouldPoll() &&
          surface == generationOf()) {
        apply(raw);
      }
    } catch (_) {
      // A failed script must not disable polling.
    } finally {
      _active = false;
      if (!shouldPoll()) return;
      if (generation == _generation) {
        _arm(generation, interval);
      } else if (_started) {
        // stop() then start() arrived while this read was outstanding.
        // The in-flight script was the only one; arm the next now.
        _arm(_generation, interval);
      }
    }
  }
}
