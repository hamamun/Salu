import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ui/osd/osd_controller.dart';
import 'channel_favourites_service.dart';
import 'channel_logo_service.dart';
import 'm3u/channel_list_loader.dart';
import 'm3u/channel_source.dart';
import 'player_service.dart';
import 'queue_service.dart';

/// Routes a source to the channel-directory loader or to the engine
/// (playlist_imp.md §10.12 M-3 · M55).
///
/// Every open verb funnels through [openSource]: a channel directory —
/// an m3u **URL** or a local `.m3u` / `.m3u8` **file**, only the fetch
/// differs — is read by SALU (§10.0), and anything else keeps Phase A's
/// engine path exactly. mpv never receives a channel list again.
///
/// The load is progressive (§10.10b): the first batch installs the queue
/// and starts channel 0 immediately, later batches append behind it, and
/// clicking a channel while the tail is still arriving just plays it.
/// A newer load (or a plain open, or a clear) cancels the running one —
/// cancelling kills the worker isolate with its buffers.
///
/// Nothing here renders or logs a source URL (§10.10e): the failure
/// toast names the playlist (a local file name, a remote **host**).
class ChannelLoadService {
  ChannelLoadService._internal();

  /// The one and only channel loader for the whole app.
  static final ChannelLoadService instance = ChannelLoadService._internal();

  /// True from the moment a channel directory starts loading until its
  /// last batch, its failure or its cancellation. Drives the wordless
  /// fetch indicator (§10.10b — the still soft light lands in M-10);
  /// there is never a spinner and never text.
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// Channels delivered by the running (or last) load — the total the
  /// search field shows while parsing continues (§10.9, M-5 renders it).
  final ValueNotifier<int> loadedCount = ValueNotifier<int>(0);

  /// The outcome of the last [load] that has resolved so far: `true`
  /// once channels arrived, `false` once it failed, `null` while it is
  /// still undecided. Read by the URL library's health probe, which
  /// asks about the **playlist**, not the first channel.
  final ValueNotifier<bool?> lastLoadOk = ValueNotifier<bool?>(null);

  /// Storage key of the loaded playlist — its **host** for a remote
  /// source, its own canonical path for a local file — or `null` while
  /// none is loaded. Drives the favourites store's selection (two
  /// playlists on one host share favourites; two local files never do,
  /// §10.3) and is what Undo carries to restore the key. Never the full
  /// URL: it carries credentials (§10.10e).
  final ValueNotifier<String?> playlistKey = ValueNotifier<String?>(null);

  /// Counts every channel load (M-6/M-7: the panel's reset signal).
  /// The panel watches this — not the queue, not the loading flag — and
  /// every bump means "forget everything": grouping back to Flat,
  /// search cleared, favourites filter off, accordion closed, scroll to
  /// the top. Reads stale-while-clearing: Undo restores the rows
  /// without bumping, so the filters it preserves carry over.
  final ValueNotifier<int> loadGeneration = ValueNotifier<int>(0);

  StreamSubscription<ChannelListEvent>? _sub;

  /// Releases the running [load]'s awaiting caller. A cancel must not
  /// leave it hanging on a load that will never report anything.
  VoidCallback? _releaseCurrent;

  /// Bumped by every load and every cancel; late events from a
  /// superseded load are dropped by comparing against it.
  int _generation = 0;

  /// Whether a channel directory is being read right now.
  bool get isLoading => loading.value;

  /// Opens [source] the right way: a channel directory is parsed by
  /// SALU, anything else goes straight to the engine as before.
  ///
  /// Returns `true` when the source was routed to the channel loader.
  Future<bool> openSource(String source, {bool play = true}) async {
    final String s = source.trim();
    if (s.isEmpty) return false;
    if (!ChannelSource.looksLikeDirectory(s)) {
      // A plain open replaces the queue — a channel load still running
      // behind it would append into somebody else's list.
      cancel();
      await PlayerService.instance.openPath(s, play: play);
      return false;
    }
    await load(s, play: play);
    return true;
  }

  /// Reads [source] as a channel directory. Any running load is
  /// cancelled first.
  Future<void> load(String source, {bool play = true}) async {
    cancel();
    final int gen = ++_generation;
    final String s = source.trim();
    final bool remote = ChannelSource.isRemote(s);
    final String name = ChannelSource.displayName(s);

    // A new playlist starts blank: its favourites key is selected, its
    // in-flight logos are dropped (§10.4), and the panel resets through
    // the generation bump (M6/M-7). Even a failed load
    // keeps this key — an empty channel-less panel has no favourites
    // surface to misuse it.
    playlistKey.value =
        ChannelFavouritesService.playlistKeyForSource(s);
    ChannelFavouritesService.instance.setPlaylist(playlistKey.value);
    ChannelLogoService.instance.cancelStale();
    loadGeneration.value++;
    loading.value = true;
    loadedCount.value = 0;
    lastLoadOk.value = null;
    bool started = false;
    int total = 0;

    // Completes as soon as the load is DECIDED: the first channels are
    // open, the source turned out to be mpv's job, or it failed. The
    // tail keeps arriving behind it (§10.10b) — this is not "finished".
    final Completer<void> decided = Completer<void>();
    void decide() {
      if (!decided.isCompleted) decided.complete();
    }
    _releaseCurrent = decide;

    void done() {
      if (gen != _generation) return;
      loading.value = false;
      unawaited(_sub?.cancel());
      _sub = null;
    }

    void fail() {
      if (gen != _generation) return;
      done();
      if (!started) lastLoadOk.value = false;
      // §10.10b: a failed PLAYLIST load is not a failed channel — the
      // same wording, never the M3b skip, never the source URL.
      OsdController.instance.show(OsdFailedCard(name: name));
      decide();
    }

    void handOverToEngine() {
      // The body turned out to be an HLS manifest (a channel's own
      // segment/variant list) or not M3U text at all — mpv's job
      // (§10.0). Nothing was queued, so this is an ordinary open.
      if (gen != _generation) return;
      done();
      unawaited(PlayerService.instance
          .openPath(s, play: play)
          .whenComplete(decide));
    }

    _sub = ChannelListLoader.open(
      remote ? s : ChannelSource.localPath(s),
      isFile: !remote,
    ).listen(
      (ChannelListEvent event) {
        if (gen != _generation) return;
        switch (event) {
          case ChannelBatch(items: final List<QueueItem> batch):
            if (batch.isEmpty) return;
            total += batch.length;
            loadedCount.value = total;
            if (!started) {
              started = true;
              lastLoadOk.value = true;
              // A fresh load starts at row 0 of the shown list
              // (§1 decision 5) — the tail arrives behind it.
              QueueService.instance.setItems(batch, 0);
              final Future<void> opened =
                  PlayerService.instance.playIndex(0, play: play);
              unawaited(opened.whenComplete(decide));
            } else {
              QueueService.instance.appendItems(batch);
            }
          case ChannelListDone():
            done();
            // A directory with zero entries never started anything.
            if (!started) lastLoadOk.value = false;
            decide();
          case ChannelListHls():
          case ChannelListNotPlaylist():
            if (started) {
              // Impossible today (both verdicts precede any entry), but
              // a queue that already exists is never thrown away.
              done();
            } else {
              handOverToEngine();
            }
          case ChannelListFailed():
            // Whatever already loaded keeps playing; only the rest is
            // lost. An empty load leaves SALU exactly as it was.
            fail();
        }
      },
      onError: (Object _) => fail(),
      onDone: () {
        // The stream always closes on a terminal event; this only
        // catches a worker that vanished without one.
        if (gen == _generation && loading.value) fail();
      },
      cancelOnError: true,
    );

    // The caller waits only for the DECISION, never for the tail: a
    // 50 000-channel list is watchable long before its last row lands.
    // The cap matches the URL library's own health window — past it the
    // load simply keeps going in the background (the timeout is not an
    // error, so `onTimeout` just ends the wait).
    await decided.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  /// Opens a **batch** the way Open File… / a multi-file drop delivers
  /// it (playlist_imp.md M55).
  ///
  /// A `.m3u` / `.m3u8` file is a channel directory, not a media file,
  /// so it can never share a queue with videos — putting one in the
  /// engine's playlist is exactly the "handed whole to mpv" behaviour
  /// M55 removes. The rule: **media wins**. A batch with any media
  /// plays that media and ignores the playlist files; a batch of only
  /// playlist files loads the first one as a channel directory.
  ///
  /// Returns `true` when the batch was routed to the channel loader.
  Future<bool> openBatch(List<String> paths, {bool play = true}) async {
    if (paths.isEmpty) return false;
    final List<String> media = paths
        .where((String p) => !ChannelSource.looksLikeDirectory(p))
        .toList(growable: false);
    if (media.isNotEmpty) {
      cancel();
      if (media.length == 1) {
        await PlayerService.instance.openPath(media.first, play: play);
      } else {
        await PlayerService.instance.openPaths(media, play: play);
      }
      return false;
    }
    await load(paths.first, play: play);
    return true;
  }

  /// Stops a running load (a newer open, a cleared playlist, shutdown).
  /// The worker isolate dies with its buffers; no terminal event fires.
  /// In-flight logo fetches are dropped with it (§10.4); the key stays
  /// until the next load (or Undo's restore) selects another.
  void cancel() {
    _generation++;
    unawaited(_sub?.cancel());
    _sub = null;
    if (loading.value) loading.value = false;
    ChannelLogoService.instance.cancelStale();
    _releaseCurrent?.call();
    _releaseCurrent = null;
  }
}
