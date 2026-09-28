import 'dart:io';

import 'package:flutter/foundation.dart';

import 'association_plan.dart';
import 'association_registry.dart';

/// association.md §3–§4 — SALU's Windows integration: which extensions it
/// is registered for, which of them Windows really opens with SALU, and
/// the right-click verbs. The registry is the one source of truth; nothing
/// here lives in `shared_preferences`, so it is never a "preference" and
/// never part of the Settings resets.
class AssociationService {
  AssociationService({RegistryBackend? backend, String? exePath})
      : _backend = backend ?? createRegistryBackend(),
        _exeOverride = exePath;

  static final AssociationService instance = AssociationService();

  final RegistryBackend _backend;
  final String? _exeOverride;

  /// Extensions SALU is registered for (OpenWithProgids + Capabilities).
  final ValueNotifier<Set<String>> associated =
      ValueNotifier<Set<String>>(const <String>{});

  /// Extensions Windows currently opens with SALU (the real default).
  final ValueNotifier<Set<String>> defaults =
      ValueNotifier<Set<String>>(const <String>{});

  /// Right-click verbs present.
  final ValueNotifier<bool> contextMenu = ValueNotifier<bool>(false);

  String get exePath => _exeOverride ?? Platform.resolvedExecutable;

  bool _samePath(String a, String b) =>
      a.replaceAll('/', r'\').toLowerCase() ==
      b.replaceAll('/', r'\').toLowerCase();

  /// Re-reads everything from the registry.
  void refresh() {
    final Set<String> reg = <String>{};
    final Set<String> def = <String>{};
    for (final String ext in allAssociableExtensions) {
      if (_backend.hasValue(
          AssociationKeys.openWith(ext), AssociationKeys.progId(ext))) {
        reg.add(ext);
      }
      final String? exe = _backend.defaultExecutableFor(ext);
      if (exe != null && _samePath(exe, exePath)) def.add(ext);
    }
    associated.value = reg;
    defaults.value = def;
    contextMenu.value = _backend.read(
            AssociationKeys.appKey, AssociationKeys.contextMenuValue) ==
        '1';
  }

  /// Launch-time upkeep (association.md §3): when the recorded exe is not
  /// the running one, repoint the base registration, every ProgID already
  /// associated and the live verbs. Never claims a new extension.
  void ensureRegistered() {
    final String? recorded = _backend.read(
        AssociationKeys.appKey, AssociationKeys.registeredExeValue);
    if (recorded != null && _samePath(recorded, exePath)) {
      refresh();
      return;
    }
    refresh();
    _writeAll(baseRegistration(exePath, associated.value));
    if (contextMenu.value) _writeAll(contextMenuWrites(exePath));
    _backend.notifyChanged();
    refresh();
  }

  /// Writes the draft: registers [wanted], unregisters the rest.
  AssociationDiff apply(Set<String> wanted) {
    refresh();
    final AssociationDiff diff =
        AssociationDiff.between(associated.value, wanted);
    _writeAll(baseRegistration(exePath, const <String>{}));
    for (final String ext in diff.add) {
      final String? current = _backend.read(AssociationKeys.extKey(ext), '');
      _writeAll(progIdWrites(exePath, ext,
          claimDefault: current == null || current.isEmpty));
    }
    for (final String ext in diff.remove) {
      _removeExtension(ext);
    }
    _backend.notifyChanged();
    refresh();
    return diff;
  }

  void _removeExtension(String ext) {
    final String progId = AssociationKeys.progId(ext);
    _backend.deleteValue(AssociationKeys.openWith(ext), progId);
    _backend.deleteValue(
        '${AssociationKeys.capabilities}\\FileAssociations', ext);
    if (_backend.read(AssociationKeys.extKey(ext), '') == progId) {
      _backend.deleteValue(AssociationKeys.extKey(ext), '');
    }
    _backend.deleteTree(AssociationKeys.progIdKey(ext));
  }

  /// Adds or removes the right-click verbs.
  void setContextMenu(bool on) {
    if (on) {
      _writeAll(baseRegistration(exePath, associated.value));
      _writeAll(contextMenuWrites(exePath));
    } else {
      contextMenuTrees().forEach(_backend.deleteTree);
      _backend.deleteValue(
          AssociationKeys.appKey, AssociationKeys.contextMenuValue);
    }
    _backend.notifyChanged();
    refresh();
  }

  /// Registers, then opens Windows Settings on SALU's Default apps page.
  /// Older builds ignore the query and land on the Default apps root.
  bool openDefaultApps() {
    _writeAll(baseRegistration(exePath, associated.value));
    _backend.notifyChanged();
    final bool opened = _backend.shellOpen(
            'ms-settings:defaultapps?registeredAppUser=${AssociationKeys.appName}') ||
        _backend.shellOpen('ms-settings:defaultapps');
    return opened;
  }

  /// `salu.exe --unregister` — removes everything SALU ever wrote.
  void unregisterAll() {
    for (final String ext in allAssociableExtensions) {
      _removeExtension(ext);
    }
    contextMenuTrees().forEach(_backend.deleteTree);
    registrationTrees().forEach(_backend.deleteTree);
    _backend.deleteValue(
        AssociationKeys.registeredApps, AssociationKeys.appName);
    _backend.notifyChanged();
    refresh();
  }

  void _writeAll(List<RegWrite> writes) {
    for (final RegWrite w in writes) {
      _backend.write(w);
    }
  }
}
