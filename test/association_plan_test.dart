import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/association/association_install_args.dart';
import 'package:salu/core/association/association_plan.dart';
import 'package:salu/core/association/association_registry.dart';
import 'package:salu/core/association/association_service.dart';

/// An in-memory HKCU: key → (value name → data).
class FakeRegistry implements RegistryBackend {
  final Map<String, Map<String, String>> keys = <String, Map<String, String>>{};
  final Map<String, String> defaultExe = <String, String>{};
  final List<String> opened = <String>[];
  int notifications = 0;

  String _k(String key) => key.toLowerCase();

  @override
  bool write(RegWrite w) {
    final Map<String, String> k =
        keys.putIfAbsent(_k(w.key), () => <String, String>{});
    if (w.name != null) k[w.name!] = w.data;
    return true;
  }

  @override
  String? read(String key, String name) => keys[_k(key)]?[name];

  @override
  bool hasValue(String key, String name) =>
      keys[_k(key)]?.containsKey(name) ?? false;

  @override
  void deleteValue(String key, String name) => keys[_k(key)]?.remove(name);

  @override
  void deleteTree(String key) {
    final String root = _k(key);
    keys.removeWhere((String k, _) => k == root || k.startsWith('$root\\'));
  }

  @override
  String? defaultExecutableFor(String ext) => defaultExe[ext];

  @override
  void notifyChanged() => notifications++;

  @override
  bool shellOpen(String target) {
    opened.add(target);
    return true;
  }

  bool anySalu() => keys.keys.any((String k) => k.contains('salu'));
}

const String exe = r'C:\Apps\SALU\salu.exe';

void main() {
  test('groups cover every media + playlist extension exactly once', () {
    final List<String> all = allAssociableExtensions;
    expect(all.toSet().length, all.length);
    expect(all, containsAll(<String>['.mp4', '.mkv', '.mp3', '.flac', '.m3u']));
    expect(groupOf('.mp4'), AssociationGroup.video);
    expect(groupOf('.flac'), AssociationGroup.audio);
    expect(groupOf('.m3u8'), AssociationGroup.playlist);
  });

  test('installer switches select only the requested association groups', () {
    expect(
      associationExtensionsFromInstallerArgs(<String>[
        '--associate-video',
        '--associate-playlists',
      ]),
      <String>{
        ...AssociationGroup.video.extensions,
        ...AssociationGroup.playlist.extensions,
      },
    );
    expect(
      associationExtensionsFromInstallerArgs(<String>['--unknown']),
      isEmpty,
    );
  });

  test('commands quote the exe and the argument', () {
    expect(openCommand(exe), r'"C:\Apps\SALU\salu.exe" "%1"');
    expect(enqueueCommand(exe), r'"C:\Apps\SALU\salu.exe" --enqueue "%1"');
  });

  test('apply registers, claims only empty defaults, and deassociates', () {
    final FakeRegistry reg = FakeRegistry();
    reg.write(const RegWrite(r'Software\Classes\.mkv', '', 'VLC.mkv'));
    final AssociationService s = AssociationService(backend: reg, exePath: exe);

    s.apply(<String>{'.mp4', '.mkv'});
    expect(s.associated.value, <String>{'.mp4', '.mkv'});
    expect(reg.read(r'Software\Classes\.mp4', ''), 'SALU.mp4');
    expect(reg.read(r'Software\Classes\.mkv', ''), 'VLC.mkv');
    expect(reg.read(r'Software\Classes\SALU.mp4\shell\open\command', ''),
        openCommand(exe));
    expect(reg.read(r'Software\RegisteredApplications', 'SALU'),
        r'Software\SALU\Capabilities');

    s.apply(<String>{'.mkv'});
    expect(s.associated.value, <String>{'.mkv'});
    expect(reg.read(r'Software\Classes\.mp4', ''), isNull);
    expect(reg.hasValue(r'Software\Classes\SALU.mp4', ''), isFalse);
    expect(reg.notifications, greaterThan(0));
  });

  test('defaults come from the real Windows association', () {
    final FakeRegistry reg = FakeRegistry()
      ..defaultExe['.mp3'] = r'c:\apps\salu\SALU.EXE'
      ..defaultExe['.mp4'] = r'C:\VLC\vlc.exe';
    final AssociationService s = AssociationService(backend: reg, exePath: exe)
      ..refresh();
    expect(s.defaults.value, <String>{'.mp3'});
  });

  test('context menu on / off', () {
    final FakeRegistry reg = FakeRegistry();
    final AssociationService s = AssociationService(backend: reg, exePath: exe);
    s.setContextMenu(true);
    expect(s.contextMenu.value, isTrue);
    expect(
        reg.read(
            r'Software\Classes\Directory\shell\SALU.Enqueue\command', ''),
        enqueueCommand(exe));
    s.setContextMenu(false);
    expect(s.contextMenu.value, isFalse);
    expect(reg.hasValue(r'Software\Classes\Directory\shell\SALU.Play', 'MUIVerb'),
        isFalse);
  });

  test('ensureRegistered repoints a moved exe without claiming', () {
    final FakeRegistry reg = FakeRegistry();
    AssociationService(backend: reg, exePath: r'D:\Old\salu.exe')
        .apply(<String>{'.mp4'});
    final AssociationService moved =
        AssociationService(backend: reg, exePath: exe)..ensureRegistered();
    expect(reg.read(r'Software\Classes\SALU.mp4\shell\open\command', ''),
        openCommand(exe));
    expect(moved.associated.value, <String>{'.mp4'});
  });

  test('default apps door registers first, then opens Settings', () {
    final FakeRegistry reg = FakeRegistry();
    AssociationService(backend: reg, exePath: exe).openDefaultApps();
    expect(reg.opened.single, startsWith('ms-settings:defaultapps'));
    expect(reg.read(r'Software\SALU', 'RegisteredExe'), exe);
  });

  test('unregisterAll leaves nothing behind', () {
    final FakeRegistry reg = FakeRegistry();
    final AssociationService s = AssociationService(backend: reg, exePath: exe)
      ..apply(allAssociableExtensions.toSet())
      ..setContextMenu(true);
    s.unregisterAll();
    expect(reg.anySalu(), isFalse,
        reason: reg.keys.entries
            .where((e) => e.key.contains('salu'))
            .map((e) => e.key)
            .join('\n'));
  });
}
