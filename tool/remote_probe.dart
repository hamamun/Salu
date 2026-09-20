import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/core/remote/remote_protocol.dart';

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
      'f +10s, r -10s, v volume, m mute, h shuffle, t repeat, q quit.');
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
