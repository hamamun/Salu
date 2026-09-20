import 'dart:async';

import 'package:flutter/foundation.dart';

import 'info_collector.dart';
import 'panel_service.dart';
import 'player_service.dart';

/// Scoped to the panel widget: no work while closed and no stale async result
/// after close, dispose, Next, or a track change. A microtask coalesces a burst
/// of width/height/track notifications; it is not a polling timer.
class InfoController extends ChangeNotifier {
  InfoController({
    required this.open,
    required this.changes,
    required this.context,
    required this.collector,
    this.log,
  }) {
    open.addListener(_openChanged);
    for (final Listenable change in changes) {
      change.addListener(refresh);
    }
    if (open.value) _openChanged();
  }

  final ValueNotifier<bool> open;
  final List<Listenable> changes;
  final InfoContext Function() context;
  final InfoCollector collector;
  final void Function(String)? log;
  InfoSnapshot? snapshot;
  int _generation = 0;
  bool _disposed = false;
  bool _scheduled = false;
  bool _logPending = false;

  factory InfoController.player() {
    final PlayerService p = PlayerService.instance;
    return InfoController(
      open: PanelService.instance.infoOpen,
      changes: <Listenable>[
        p.currentPath,
        p.currentTitle,
        p.trackSurface,
        p.videoWidth,
        p.videoHeight,
        p.activeHwdec,
        p.resumedFrom,
      ],
      context: InfoContext.current,
      collector: InfoCollector(),
      log: kDebugMode ? debugPrint : null,
    );
  }

  void _openChanged() {
    _generation++;
    snapshot = null;
    _logPending = open.value;
    if (open.value) refresh();
    notifyListeners();
  }

  void refresh() {
    if (_disposed || !open.value) return;
    _generation++;
    snapshot = null;
    notifyListeners();
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() async {
      _scheduled = false;
      if (_disposed || !open.value) return;
      final int generation = _generation;
      final InfoSnapshot result = await collector.collect(context());
      if (_disposed || !open.value || generation != _generation) return;
      snapshot = result;
      if (_logPending) {
        _logPending = false;
        final Iterable<String> answered =
            result.probes.entries.where((e) => e.value).map((e) => e.key);
        final Iterable<String> missing =
            result.probes.entries.where((e) => !e.value).map((e) => e.key);
        log?.call(
          '[SALU/info] answered: ${answered.join(', ')}; unavailable: ${missing.join(', ')}',
        );
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    open.removeListener(_openChanged);
    for (final Listenable change in changes) {
      change.removeListener(refresh);
    }
    super.dispose();
  }
}

bool get infoAvailable {
  final PlayerService p = PlayerService.instance;
  return p.hasMedia.value &&
      p.currentPath.value != null &&
      p.transportState.value != TransportState.stopped &&
      p.transportState.value != TransportState.idle;
}
