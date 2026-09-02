import 'dart:async';

import '../player_service.dart';

/// Streams SALU's live player state back over the remote WebSocket, exactly
/// as specified in Phase 8 · Step 3: "millisecond-perfect UI updates for any
/// connected client".
///
/// The broadcaster listens to the mirrored [PlayerService] notifiers (never
/// raw mpv streams — everything is already piped through ValueNotifiers by
/// Phase 2) and re-emits a compact JSON snapshot:
///
/// ```json
/// {
///   "type": "state",
///   "has_media": true,
///   "title": "Interstellar",
///   "playing": true,
///   "muted": false,
///   "volume": 120,            // 0–200 (base + boost)
///   "position_ms": 42123,
///   "duration_ms": 921000,
///   "rate": 1.0,
///   "live": false
/// }
/// ```
///
/// Transport-relevant changes (play/pause, title, volume…) broadcast
/// instantly; the position ticker is throttled so a chatty mpv stream never
/// floods the LAN with JSON.
class PlayerStateBroadcaster {
  PlayerStateBroadcaster({
    required PlayerService player,
    required void Function(Map<String, Object?> payload) broadcast,
  })  : _player = player,
        _broadcast = broadcast;

  final PlayerService _player;
  final void Function(Map<String, Object?> payload) _broadcast;

  bool _attached = false;
  bool _dirty = false;
  Timer? _throttle;

  void attach() {
    if (_attached) return;
    _attached = true;
    _player.playing.addListener(_onUrgent);
    _player.muted.addListener(_onUrgent);
    _player.baseVolume.addListener(_onUrgent);
    _player.volumeBoost.addListener(_onUrgent);
    _player.duration.addListener(_onUrgent);
    _player.currentTitle.addListener(_onUrgent);
    _player.hasMedia.addListener(_onUrgent);
    _player.isLiveStream.addListener(_onUrgent);
    _player.rate.addListener(_onUrgent);
    _player.completed.addListener(_onUrgent);
    _player.position.addListener(_onPositionTick);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _player.playing.removeListener(_onUrgent);
    _player.muted.removeListener(_onUrgent);
    _player.baseVolume.removeListener(_onUrgent);
    _player.volumeBoost.removeListener(_onUrgent);
    _player.duration.removeListener(_onUrgent);
    _player.currentTitle.removeListener(_onUrgent);
    _player.hasMedia.removeListener(_onUrgent);
    _player.isLiveStream.removeListener(_onUrgent);
    _player.rate.removeListener(_onUrgent);
    _player.completed.removeListener(_onUrgent);
    _player.position.removeListener(_onPositionTick);
    _throttle?.cancel();
    _throttle = null;
    _dirty = false;
  }

  /// Latest snapshot — reused for `hello` and `get_state` replies.
  Map<String, Object?> snapshot() => <String, Object?>{
        'type': 'state',
        'has_media': _player.hasMedia.value,
        'title': _player.currentTitle.value,
        'playing': _player.playing.value,
        'completed': _player.completed.value,
        'muted': _player.muted.value,
        'volume':
            (_player.baseVolume.value + _player.volumeBoost.value).round(),
        'position_ms': _player.position.value.inMilliseconds,
        'duration_ms': _player.duration.value.inMilliseconds,
        'rate': _player.rate.value,
        'live': _player.isLiveStream.value,
      };

  void pushSnapshotNow() => _broadcast(snapshot());

  void _onUrgent() {
    // State semantics changed — every millisecond counts for the remote UI.
    _dirty = false;
    _throttle?.cancel();
    _throttle = null;
    _broadcast(snapshot());
  }

  void _onPositionTick() {
    _dirty = true;
    if (_throttle != null) return;
    _throttle = Timer(const Duration(milliseconds: 250), () {
      _throttle = null;
      if (!_dirty) return;
      _dirty = false;
      _broadcast(snapshot());
    });
  }
}
