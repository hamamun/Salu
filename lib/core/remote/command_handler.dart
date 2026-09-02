import 'dart:async';
import 'dart:math' as math;

import '../player_service.dart';
import 'websocket_server.dart';

/// Interprets JSON commands coming over the remote WebSocket (Phase 8 · Step 2).
///
/// The protocol is one flat JSON object per frame:
///
/// ```json
/// { "action": "play_pause" }
/// { "action": "volume_up" }            // +5 %
/// { "action": "volume_down" }           // −5 %
/// { "action": "set_volume", "value": 60 }   // 0–200 (boost range)
/// { "action": "mute_toggle" }
/// { "action": "seek_forward" }          // +5 s
/// { "action": "seek_backward" }         // −5 s
/// { "action": "seek_to", "position_ms": 125000 }
/// { "action": "next_track" }
/// { "action": "previous_track" }
/// { "action": "set_rate", "value": 1.5 }
/// { "action": "stop" }
/// { "action": "get_state" }
/// ```
///
/// Every message gets a compact reply so the controller can show progress:
/// `{"type": "result", "action": "…", "ok": true}` (or `type: error`).
class RemoteCommandHandler {
  RemoteCommandHandler(
    this._player, {
    required Map<String, Object?> Function() stateProvider,
  }) : _stateProvider = stateProvider;

  final PlayerService _player;
  final Map<String, Object?> Function() _stateProvider;

  static const Duration seekStep = Duration(seconds: 5);
  static const double volumeStep = 5;

  Map<String, Object?> handle(RemoteClient client, Map<String, dynamic> message) {
    final String action =
        (message['action'] ?? message['cmd'] ?? '').toString().toLowerCase();
    if (action.isEmpty) {
      return _error(action, 'Missing "action" field.');
    }

    try {
      switch (action) {
        case 'play_pause':
          _player.playOrPause();
        case 'play':
          _player.play();
        case 'pause':
          _player.pause();
        case 'volume_up':
          _setBaseVolume(_player.baseVolume.value + volumeStep);
        case 'volume_down':
          _setBaseVolume(_player.baseVolume.value - volumeStep);
        case 'set_volume':
          _applyEffectiveVolume(_asDouble(message['value']) ?? 100);
        case 'mute_toggle':
          _player.toggleMute();
        case 'seek_forward':
          _player.seekBy(seekStep);
        case 'seek_backward':
          _player.seekBy(-seekStep);
        case 'seek_to':
          final double? ms = _asDouble(message['position_ms']);
          if (ms == null) return _error(action, 'seek_to needs "position_ms".');
          _player.seek(Duration(milliseconds: ms.round()));
        case 'next_track':
          _player.next();
        case 'previous_track':
          _player.previous();
        case 'set_rate':
          final double? rate = _asDouble(message['value']);
          if (rate == null) return _error(action, 'set_rate needs "value".');
          _player.setRate(rate.clamp(0.25, 4.0));
        case 'stop':
          // Unloads the media entirely (matches the desktop behaviour).
          unawaited(_player.player.stop());
        case 'get_state':
          return <String, Object?>{
            'type': 'result',
            'action': action,
            'ok': true,
            'state': _stateProvider(),
          };
        default:
          return _error(action, 'Unknown action "$action".');
      }
      return <String, Object?>{'type': 'result', 'action': action, 'ok': true};
    } catch (error) {
      return _error(action, 'Command failed: $error');
    }
  }

  void _setBaseVolume(double value) {
    _player.setBaseVolume(value.clamp(0.0, 100.0).toDouble());
  }

  /// 0–100 edits the base volume, 100–200 spends the mpv boost headroom.
  void _applyEffectiveVolume(double value) {
    final double v = value.clamp(0.0, 200.0).toDouble();
    _player.setBaseVolume(math.min(v, 100.0));
    _player.setVolumeBoost(math.max(0.0, v - 100.0));
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static Map<String, Object?> _error(String action, String message) =>
      <String, Object?>{
        'type': 'error',
        'action': action,
        'ok': false,
        'message': message,
      };
}
