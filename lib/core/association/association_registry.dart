import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'association_plan.dart';

/// association.md §5 — the only piece that touches Windows. Everything is
/// per-user (`HKEY_CURRENT_USER`): SALU never asks for elevation.
abstract class RegistryBackend {
  /// Writes one value (creating its key). Returns false on failure.
  bool write(RegWrite w);

  /// Reads a string value; null when the key or value is missing.
  String? read(String key, String name);

  /// Does the named value exist (any type)?
  bool hasValue(String key, String name);

  /// Deletes one value. Missing is success.
  void deleteValue(String key, String name);

  /// Deletes a key and everything under it. Missing is success.
  void deleteTree(String key);

  /// Full path of the executable Windows would open [ext] with.
  String? defaultExecutableFor(String ext);

  /// Tells Explorer that associations changed (icons + menus refresh).
  void notifyChanged();

  /// Opens a URI / file through the shell (`ms-settings:` pages).
  bool shellOpen(String target);
}

// ── Win32 FFI implementation ──────────────────────────────────────────────

typedef _RegCreateKeyExN = Int32 Function(IntPtr, Pointer<Utf16>, Uint32,
    Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Pointer<IntPtr>,
    Pointer<Uint32>);
typedef _RegCreateKeyExD = int Function(int, Pointer<Utf16>, int,
    Pointer<Utf16>, int, int, Pointer<Void>, Pointer<IntPtr>, Pointer<Uint32>);
typedef _RegSetValueExN = Int32 Function(
    IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<Uint8>, Uint32);
typedef _RegSetValueExD = int Function(
    int, Pointer<Utf16>, int, int, Pointer<Uint8>, int);
typedef _RegCloseKeyN = Int32 Function(IntPtr);
typedef _RegCloseKeyD = int Function(int);
typedef _RegDeleteTreeN = Int32 Function(IntPtr, Pointer<Utf16>);
typedef _RegDeleteTreeD = int Function(int, Pointer<Utf16>);
typedef _RegDeleteKeyValueN = Int32 Function(
    IntPtr, Pointer<Utf16>, Pointer<Utf16>);
typedef _RegDeleteKeyValueD = int Function(
    int, Pointer<Utf16>, Pointer<Utf16>);
typedef _RegGetValueN = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>,
    Uint32, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>);
typedef _RegGetValueD = int Function(int, Pointer<Utf16>, Pointer<Utf16>, int,
    Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>);
typedef _AssocQueryStringN = Int32 Function(Uint32, Uint32, Pointer<Utf16>,
    Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint32>);
typedef _AssocQueryStringD = int Function(int, int, Pointer<Utf16>,
    Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint32>);
typedef _SHChangeNotifyN = Void Function(
    Int32, Uint32, Pointer<Void>, Pointer<Void>);
typedef _SHChangeNotifyD = void Function(
    int, int, Pointer<Void>, Pointer<Void>);
typedef _ShellExecuteN = IntPtr Function(IntPtr, Pointer<Utf16>,
    Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Int32);
typedef _ShellExecuteD = int Function(int, Pointer<Utf16>, Pointer<Utf16>,
    Pointer<Utf16>, Pointer<Utf16>, int);

/// `HKEY_CURRENT_USER` — `(HKEY)(LONG)0x80000001`, sign-extended on x64.
const int _hkcu = -0x7FFFFFFF;
const int _keyReadWrite = 0x2001F; // KEY_READ | KEY_WRITE
const int _regNone = 0;
const int _regSz = 1;
const int _rrfRtAny = 0x0000FFFF;
const int _rrfRtRegSz = 0x00000002;
const int _assocfInitIgnoreUnknown = 0x00000400;
const int _assocstrExecutable = 2;
const int _shcneAssocChanged = 0x08000000;
const int _errorSuccess = 0;

class Win32RegistryBackend implements RegistryBackend {
  Win32RegistryBackend() {
    final DynamicLibrary advapi = DynamicLibrary.open('advapi32.dll');
    final DynamicLibrary shell = DynamicLibrary.open('shell32.dll');
    final DynamicLibrary shlwapi = DynamicLibrary.open('shlwapi.dll');
    _create = advapi
        .lookupFunction<_RegCreateKeyExN, _RegCreateKeyExD>('RegCreateKeyExW');
    _set = advapi
        .lookupFunction<_RegSetValueExN, _RegSetValueExD>('RegSetValueExW');
    _close = advapi.lookupFunction<_RegCloseKeyN, _RegCloseKeyD>('RegCloseKey');
    _deleteTree =
        advapi.lookupFunction<_RegDeleteTreeN, _RegDeleteTreeD>('RegDeleteTreeW');
    _deleteValue = advapi.lookupFunction<_RegDeleteKeyValueN,
        _RegDeleteKeyValueD>('RegDeleteKeyValueW');
    _get = advapi.lookupFunction<_RegGetValueN, _RegGetValueD>('RegGetValueW');
    _assoc = shlwapi.lookupFunction<_AssocQueryStringN, _AssocQueryStringD>(
        'AssocQueryStringW');
    _notify = shell
        .lookupFunction<_SHChangeNotifyN, _SHChangeNotifyD>('SHChangeNotify');
    _shellExecute =
        shell.lookupFunction<_ShellExecuteN, _ShellExecuteD>('ShellExecuteW');
  }

  late final _RegCreateKeyExD _create;
  late final _RegSetValueExD _set;
  late final _RegCloseKeyD _close;
  late final _RegDeleteTreeD _deleteTree;
  late final _RegDeleteKeyValueD _deleteValue;
  late final _RegGetValueD _get;
  late final _AssocQueryStringD _assoc;
  late final _SHChangeNotifyD _notify;
  late final _ShellExecuteD _shellExecute;

  @override
  bool write(RegWrite w) {
    return using((Arena arena) {
      final Pointer<IntPtr> handle = arena<IntPtr>();
      final int rc = _create(_hkcu, w.key.toNativeUtf16(allocator: arena), 0,
          nullptr, 0, _keyReadWrite, nullptr, handle, nullptr);
      if (rc != _errorSuccess) {
        debugPrint('[SALU] association: create ${w.key} failed ($rc)');
        return false;
      }
      try {
        final String? name = w.name;
        if (name == null) return true;
        final Pointer<Utf16> nameP = name.isEmpty
            ? nullptr
            : name.toNativeUtf16(allocator: arena);
        if (w.kind == RegKind.none) {
          return _set(handle.value, nameP, 0, _regNone, nullptr, 0) ==
              _errorSuccess;
        }
        final List<int> units = w.data.codeUnits;
        final Pointer<Uint16> buf = arena<Uint16>(units.length + 1);
        for (int i = 0; i < units.length; i++) {
          buf[i] = units[i];
        }
        buf[units.length] = 0;
        return _set(handle.value, nameP, 0, _regSz, buf.cast<Uint8>(),
                (units.length + 1) * 2) ==
            _errorSuccess;
      } finally {
        _close(handle.value);
      }
    });
  }

  @override
  String? read(String key, String name) {
    return using((Arena arena) {
      final Pointer<Utf16> keyP = key.toNativeUtf16(allocator: arena);
      final Pointer<Utf16> nameP =
          name.isEmpty ? nullptr : name.toNativeUtf16(allocator: arena);
      final Pointer<Uint32> size = arena<Uint32>();
      if (_get(_hkcu, keyP, nameP, _rrfRtRegSz, nullptr, nullptr, size) !=
          _errorSuccess) {
        return null;
      }
      final Pointer<Uint8> buf = arena<Uint8>(size.value + 2);
      if (_get(_hkcu, keyP, nameP, _rrfRtRegSz, nullptr, buf.cast(), size) !=
          _errorSuccess) {
        return null;
      }
      return buf.cast<Utf16>().toDartString();
    });
  }

  @override
  bool hasValue(String key, String name) {
    return using((Arena arena) {
      final Pointer<Uint32> size = arena<Uint32>();
      return _get(
              _hkcu,
              key.toNativeUtf16(allocator: arena),
              name.isEmpty ? nullptr : name.toNativeUtf16(allocator: arena),
              _rrfRtAny,
              nullptr,
              nullptr,
              size) ==
          _errorSuccess;
    });
  }

  @override
  void deleteValue(String key, String name) {
    using((Arena arena) {
      _deleteValue(_hkcu, key.toNativeUtf16(allocator: arena),
          name.isEmpty ? nullptr : name.toNativeUtf16(allocator: arena));
    });
  }

  @override
  void deleteTree(String key) {
    using((Arena arena) {
      _deleteTree(_hkcu, key.toNativeUtf16(allocator: arena));
    });
  }

  @override
  String? defaultExecutableFor(String ext) {
    return using((Arena arena) {
      final Pointer<Uint32> len = arena<Uint32>()..value = 1024;
      final Pointer<Utf16> out = arena<Uint16>(1024).cast<Utf16>();
      final int hr = _assoc(
          _assocfInitIgnoreUnknown,
          _assocstrExecutable,
          ext.toNativeUtf16(allocator: arena),
          'open'.toNativeUtf16(allocator: arena),
          out,
          len);
      if (hr != 0) return null;
      final String path = out.toDartString();
      return path.isEmpty ? null : path;
    });
  }

  @override
  void notifyChanged() => _notify(_shcneAssocChanged, 0, nullptr, nullptr);

  @override
  bool shellOpen(String target) {
    return using((Arena arena) {
      final int rc = _shellExecute(
          0,
          'open'.toNativeUtf16(allocator: arena),
          target.toNativeUtf16(allocator: arena),
          nullptr,
          nullptr,
          1 /* SW_SHOWNORMAL */);
      return rc > 32;
    });
  }
}

/// A no-op stand-in for non-Windows hosts (tests, analysis).
class NullRegistryBackend implements RegistryBackend {
  @override
  bool write(RegWrite w) => false;
  @override
  String? read(String key, String name) => null;
  @override
  bool hasValue(String key, String name) => false;
  @override
  void deleteValue(String key, String name) {}
  @override
  void deleteTree(String key) {}
  @override
  String? defaultExecutableFor(String ext) => null;
  @override
  void notifyChanged() {}
  @override
  bool shellOpen(String target) => false;
}

RegistryBackend createRegistryBackend() {
  if (!Platform.isWindows) return NullRegistryBackend();
  try {
    return Win32RegistryBackend();
  } catch (error) {
    debugPrint('[SALU] association: registry unavailable ($error)');
    return NullRegistryBackend();
  }
}
