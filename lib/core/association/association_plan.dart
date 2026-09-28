import '../media_utils.dart';

/// association.md §2 — the pure half of Windows integration: which
/// extensions SALU offers, and exactly which per-user registry keys and
/// values each operation writes or removes. No I/O here, so the whole
/// plan is unit-tested on any host.

/// The extension groups the Associations tab shows, in display order.
enum AssociationGroup { video, audio, playlist }

extension AssociationGroupInfo on AssociationGroup {
  String get label => switch (this) {
        AssociationGroup.video => 'Video',
        AssociationGroup.audio => 'Audio',
        AssociationGroup.playlist => 'Playlist',
      };

  /// The ProgID's friendly type name ("SALU Video").
  String get typeName => 'SALU $label';

  /// Extensions (leading dot, lower case) in a stable, sorted order.
  List<String> get extensions {
    final Set<String> source = switch (this) {
      AssociationGroup.video => MediaUtils.videoExtensions,
      AssociationGroup.audio => MediaUtils.audioExtensions,
      AssociationGroup.playlist => MediaUtils.playlistExtensions,
    };
    return source.toList()..sort();
  }
}

/// Every extension SALU can associate.
List<String> get allAssociableExtensions => <String>[
      for (final AssociationGroup g in AssociationGroup.values) ...g.extensions,
    ];

AssociationGroup? groupOf(String ext) {
  for (final AssociationGroup g in AssociationGroup.values) {
    if (g.extensions.contains(ext)) return g;
  }
  return null;
}

/// Registry value kinds SALU writes.
enum RegKind { string, none }

/// One registry write. [name] empty = the key's (default) value; a null
/// [name] means "just make sure the key exists".
class RegWrite {
  const RegWrite(this.key, this.name, this.data, {this.kind = RegKind.string});
  const RegWrite.ensureKey(this.key)
      : name = null,
        data = '',
        kind = RegKind.string;

  final String key;
  final String? name;
  final String data;
  final RegKind kind;

  @override
  String toString() => 'RegWrite($key, $name, $data, $kind)';
}

/// All paths are relative to HKEY_CURRENT_USER.
class AssociationKeys {
  AssociationKeys._();

  static const String appName = 'SALU';
  static const String exeName = 'salu.exe';
  static const String classes = r'Software\Classes';
  static const String appKey = r'Software\SALU';
  static const String capabilities = r'Software\SALU\Capabilities';
  static const String registeredApps = r'Software\RegisteredApplications';
  static const String applications = '$classes\\Applications\\$exeName';
  static const String registeredExeValue = 'RegisteredExe';
  static const String contextMenuValue = 'ContextMenu';

  static const String playVerb = 'SALU.Play';
  static const String enqueueVerb = 'SALU.Enqueue';

  static String progId(String ext) => 'SALU${ext.toLowerCase()}';
  static String progIdKey(String ext) => '$classes\\${progId(ext)}';
  static String extKey(String ext) => '$classes\\$ext';
  static String openWith(String ext) => '${extKey(ext)}\\OpenWithProgids';
  static String sysVerbs(String ext) =>
      '$classes\\SystemFileAssociations\\$ext\\shell';
  static const String dirVerbs = '$classes\\Directory\\shell';
}

String _q(String s) => '"$s"';
String openCommand(String exe) => '${_q(exe)} "%1"';
String enqueueCommand(String exe) => '${_q(exe)} --enqueue "%1"';
String iconRef(String exe) => '${_q(exe)},0';

/// The app-level registration — present regardless of which extensions
/// are ticked, so SALU always appears in "Open with" and Default apps.
List<RegWrite> baseRegistration(String exe, Set<String> associated) {
  const String app = AssociationKeys.applications;
  const String cap = AssociationKeys.capabilities;
  return <RegWrite>[
    RegWrite(AssociationKeys.appKey, AssociationKeys.registeredExeValue, exe),
    RegWrite(app, 'FriendlyAppName', AssociationKeys.appName),
    RegWrite('$app\\DefaultIcon', '', iconRef(exe)),
    RegWrite('$app\\shell\\open\\command', '', openCommand(exe)),
    for (final String ext in allAssociableExtensions)
      RegWrite('$app\\SupportedTypes', ext, ''),
    RegWrite(cap, 'ApplicationName', AssociationKeys.appName),
    RegWrite(cap, 'ApplicationDescription', 'SALU media player'),
    RegWrite(cap, 'ApplicationIcon', iconRef(exe)),
    const RegWrite.ensureKey('$cap\\FileAssociations'),
    RegWrite(AssociationKeys.registeredApps, AssociationKeys.appName, cap),
    for (final String ext in associated) ...progIdWrites(exe, ext),
  ];
}

/// The ProgID and the `OpenWithProgids` / Capabilities entries for one
/// ticked extension. [claimDefault] also sets the class default — only
/// used when the extension's (default) is empty (association.md §1).
List<RegWrite> progIdWrites(String exe, String ext,
    {bool claimDefault = false}) {
  final String key = AssociationKeys.progIdKey(ext);
  final String type = groupOf(ext)?.typeName ?? AssociationKeys.appName;
  return <RegWrite>[
    RegWrite(key, '', type),
    RegWrite(key, 'FriendlyTypeName', type),
    RegWrite('$key\\DefaultIcon', '', iconRef(exe)),
    RegWrite('$key\\shell\\open\\command', '', openCommand(exe)),
    RegWrite(AssociationKeys.openWith(ext), AssociationKeys.progId(ext), '',
        kind: RegKind.none),
    RegWrite('${AssociationKeys.capabilities}\\FileAssociations', ext,
        AssociationKeys.progId(ext)),
    if (claimDefault)
      RegWrite(AssociationKeys.extKey(ext), '', AssociationKeys.progId(ext)),
  ];
}

/// The right-click verbs (association.md §2 · feature C).
List<RegWrite> contextMenuWrites(String exe) {
  List<RegWrite> verbs(String shell) => <RegWrite>[
        RegWrite('$shell\\${AssociationKeys.playVerb}', 'MUIVerb',
            'Play with SALU'),
        RegWrite('$shell\\${AssociationKeys.playVerb}', 'Icon', iconRef(exe)),
        RegWrite('$shell\\${AssociationKeys.playVerb}\\command', '',
            openCommand(exe)),
        RegWrite('$shell\\${AssociationKeys.enqueueVerb}', 'MUIVerb',
            'Add to SALU queue'),
        RegWrite(
            '$shell\\${AssociationKeys.enqueueVerb}', 'Icon', iconRef(exe)),
        RegWrite('$shell\\${AssociationKeys.enqueueVerb}\\command', '',
            enqueueCommand(exe)),
      ];
  return <RegWrite>[
    for (final String ext in <String>[
      ...AssociationGroup.video.extensions,
      ...AssociationGroup.audio.extensions,
    ])
      ...verbs(AssociationKeys.sysVerbs(ext)),
    ...verbs(AssociationKeys.dirVerbs),
    RegWrite(AssociationKeys.appKey, AssociationKeys.contextMenuValue, '1'),
  ];
}

/// Keys (whole trees) the context-menu removal deletes.
List<String> contextMenuTrees() => <String>[
      for (final String ext in <String>[
        ...AssociationGroup.video.extensions,
        ...AssociationGroup.audio.extensions,
      ]) ...<String>[
        '${AssociationKeys.sysVerbs(ext)}\\${AssociationKeys.playVerb}',
        '${AssociationKeys.sysVerbs(ext)}\\${AssociationKeys.enqueueVerb}',
      ],
      '${AssociationKeys.dirVerbs}\\${AssociationKeys.playVerb}',
      '${AssociationKeys.dirVerbs}\\${AssociationKeys.enqueueVerb}',
    ];

/// Keys (whole trees) removed by `--unregister`, besides every ProgID.
List<String> registrationTrees() => <String>[
      AssociationKeys.applications,
      AssociationKeys.appKey,
      for (final String ext in allAssociableExtensions)
        AssociationKeys.progIdKey(ext),
    ];

/// The difference between what is registered and what the draft wants.
class AssociationDiff {
  const AssociationDiff(this.add, this.remove);

  factory AssociationDiff.between(Set<String> current, Set<String> wanted) =>
      AssociationDiff(wanted.difference(current), current.difference(wanted));

  final Set<String> add;
  final Set<String> remove;

  bool get isEmpty => add.isEmpty && remove.isEmpty;
}
