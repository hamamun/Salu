import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:salu/core/remote/remote_protocol.dart';

/// Tiny terminal client for R1. It deliberately uses only dart:io and the
/// pure protocol/pairing files, so it can prove a Windows SALU build before
/// the Android project exists.
Future<void> main(List<String> args) async {
  final _Options options = _Options.parse(args);
  final WebSocket socket = await WebSocket.connect(
    'ws://${options.host}:${options.port}',
  );
  socket.listen((Object? event) {
    if (event is String) {
      try {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(RemoteProtocol.decode(event)));
      } catch (_) {
        stdout.writeln(event);
      }
    }
  }, onDone: () => exit(0));

  int id = 1;
  void send(String verb, [Map<String, Object?> args = const <String, Object?>{}]) {
    socket.add(RemoteProtocol.encode(<String, Object?>{
      'type': 'cmd',
      'id': id++,
      'proto': protocolVersion,
      'verb': verb,
      if (args.isNotEmpty) 'args': args,
    }));
  }

  socket.add(RemoteProtocol.encode(RemoteProtocol.authByPairingCode(
    id: id++,
    pair: options.code,
    deviceId: 'remote-probe',
    deviceName: 'SALU terminal probe',
    platform: 'cli',
  )));
  stdout.writeln('Connected. Commands: p play/pause, n next, b previous, s stop, '
      'f +10s, r -10s, v volume, m mute, h shuffle, t repeat, c clear queue, '
      'o restart (start over), q quit.\n'
      'Web section (pc_part.md A): g web_media_get, k +60s seek, j -10s seek, '
      'd web_media_volume 10, l web_tabs_get, a web_tab_close 0, '
      'w web_tab_new example.com, u web_bookmarks_get, 1/2/3/4 web_key '
      '(↓/↑/Enter/Escape), e web_focus_get.');
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
    final String c = line.trim().toLowerCase();
    switch (c) {
      case 'p':
        send('play_pause');
        break;
      case 'n':
        send('next');
        break;
      case 'b':
        send('previous');
        break;
      case 's':
        send('stop');
        break;
      case 'f':
        send('seek_by', <String, Object?>{'delta': 10000});
        break;
      case 'r':
        send('seek_by', <String, Object?>{'delta': -10000});
        break;
      case 'v':
        send('volume_step', <String, Object?>{'delta': 5});
        break;
      case 'm':
        send('mute_toggle');
        break;
      case 'h':
        send('shuffle_toggle');
        break;
      case 't':
        send('repeat_cycle');
        break;
      case 'c':
        send('queue_clear');
        break;
      case 'o':
        send('restart');
        break;
      // ── Web section (pc_part.md A — the units bridge, tabs, bookmarks,
      //    the D-pad) ──────────────────────────────────────────────────────
      case 'g':
        send('web_media_get');
        break;
      case 'k':
        send('web_media_seek', <String, Object?>{'to': 60000});
        break;
      case 'j':
        send('web_media_seek', <String, Object?>{'delta': -10000});
        break;
      case 'd':
        send('web_media_volume', <String, Object?>{'percent': 10});
        break;
      case 'l':
        send('web_tabs_get');
        break;
      case 'a':
        send('web_tab_close', <String, Object?>{'index': 0});
        break;
      case 'w':
        send('web_tab_new', <String, Object?>{'url': 'https://example.com'});
        break;
      case 'u':
        send('web_bookmarks_get');
        break;
      case '1':
        send('web_key', <String, Object?>{'key': 'ArrowDown'});
        break;
      case '2':
        send('web_key', <String, Object?>{'key': 'ArrowUp'});
        break;
      case '3':
        send('web_key', <String, Object?>{'key': 'Enter'});
        break;
      case '4':
        send('web_key', <String, Object?>{'key': 'Escape'});
        break;
      case 'e':
        send('web_focus_get');
        break;
      case 'q':
        unawaited(socket.close());
        exit(0);
    }
  });
}

class _Options {
  const _Options(this.host, this.port, this.code);
  final String host;
  final int port;
  final String code;

  static _Options parse(List<String> args) {
    String host = '127.0.0.1';
    int port = 7258;
    String? code;
    final List<String> positional = <String>[];
    for (int i = 0; i < args.length; i++) {
      final String arg = args[i];
      if (arg == '--code' && i + 1 < args.length) {
        code = args[++i];
      } else if (arg == '--port' && i + 1 < args.length) {
        port = int.tryParse(args[++i]) ?? port;
      } else if (!arg.startsWith('--')) {
        positional.add(arg);
      }
    }
    if (positional.isNotEmpty) host = positional.first;
    code ??= positional.length > 1 ? positional[1] : '';
    if (code.isEmpty) {
      stderr.writeln('Usage: dart run tool/remote_probe.dart --code 7K4M-QP2X [host] [--port 7258]');
      exit(64);
    }
    return _Options(host, port, code.replaceAll(RegExp(r'[-\s]'), '').toUpperCase());
  }
}
