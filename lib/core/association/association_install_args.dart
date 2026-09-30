import 'association_plan.dart';

/// Installer-only switches used by Inno Setup to register selected
/// Open-with groups without starting the SALU window.
const Map<String, AssociationGroup> associationInstallerArguments =
    <String, AssociationGroup>{
  '--associate-video': AssociationGroup.video,
  '--associate-audio': AssociationGroup.audio,
  '--associate-playlists': AssociationGroup.playlist,
};

/// Returns the extensions selected by the installer switches in [args].
/// Existing registrations are not removed; setup selections add to them.
Set<String> associationExtensionsFromInstallerArgs(Iterable<String> args) {
  final Set<String> switches = args.toSet();
  return <String>{
    for (final MapEntry<String, AssociationGroup> entry
        in associationInstallerArguments.entries)
      if (switches.contains(entry.key)) ...entry.value.extensions,
  };
}
