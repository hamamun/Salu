import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';

/// The PC's own pointer, driven from the phone's trackpad (pc_part.md C3 ·
/// remote.md §17.14.3): `web_mouse_move {dx, dy}` and
/// `web_mouse_click {button, count}`.
///
/// **Real input, never page scripts.** The pointer moves through
/// `SendInput` with `MOUSEEVENTF_MOVE` and **without**
/// `MOUSEEVENTF_ABSOLUTE`, so Windows treats it exactly like a physical
/// mouse (pointer speed and all), and a click is a real button down/up at
/// wherever the cursor stands — over a canvas player, a video overlay or a
/// DOM button alike. Because the movement is genuine OS input, the window
/// under the cursor receives ordinary `WM_MOUSEMOVE`s: Flutter's hover
/// reaches the WebView's pointer listener, the page sees a real
/// `mousemove`, and a player that hid its cursor in fullscreen shows it
/// again. That is the pointer-visibility half of C3 — SALU itself never
/// hides the cursor over the browser, so nothing needs turning back on.
///
/// **Non-blocking by construction.** 25 moves a second arrive while a thumb
/// travels; each one is a synchronous `SendInput` call (microseconds) and
/// an ack. Nothing here awaits the page, a timer or the UI thread.
///
/// **One gain only.** The phone already multiplied the thumb's travel by
/// its pad gain and clamped every packet to ±320 px ([maxPacket]). This
/// service converts CSS pixels to device pixels (the SALU window's own
/// device-pixel ratio) and adds **no** acceleration of its own — two gains
/// is a pointer that overshoots everything.
class RemoteInputService {
  RemoteInputService({
    RemotePointerInjector? injector,
    double Function()? scale,
  })  : _injector = injector ?? RemotePointerInjector.platform(),
        _scale = scale ?? _viewScale;

  static final RemoteInputService instance = RemoteInputService();

  /// The phone's own per-packet clamp (`mouse_pad.dart`), re-applied at
  /// this edge so a third-party client cannot fling the cursor across three
  /// monitors in one frame.
  static const double maxPacket = 320;

  /// Click counts the verb accepts — a tap and a double tap.
  static const Set<int> clickCounts = <int>{1, 2};

  /// `button` names on the wire.
  static const Set<String> buttons = <String>{'left', 'right', 'middle'};

  final RemotePointerInjector _injector;
  final double Function() _scale;

  // Sub-pixel remainders, per axis. At DPR 1.25 a 1-px packet is 1.25
  // device pixels; rounding each packet alone would lose (or invent) a
  // quarter pixel every time. Carrying the remainder keeps "two moves in a
  // row add up" exact.
  double _carryX = 0;
  double _carryY = 0;

  /// Whether the pointer can be delivered at all on this PC. `hello.features`
  /// advertises `web_mouse` only when this is true (pc_part.md C3.4).
  bool get available => _injector.available;

  /// Moves the pointer by [dx]/[dy] CSS pixels. Returns false when the input
  /// could not be delivered (no injector, a locked session, UIPI) — the
  /// handler answers `no_web_mouse` for that.
  bool moveBy(double dx, double dy) {
    if (!_injector.available) return false;
    if (!dx.isFinite || !dy.isFinite) return false;
    final double scale = _safeScale();
    final double x = dx.clamp(-maxPacket, maxPacket).toDouble() * scale + _carryX;
    final double y = dy.clamp(-maxPacket, maxPacket).toDouble() * scale + _carryY;
    final int ix = x.truncate();
    final int iy = y.truncate();
    if (ix == 0 && iy == 0) {
      // Nothing whole to send yet — bank it, and the next packet pays it.
      _carryX = x;
      _carryY = y;
      return true;
    }
    final bool ok = _injector.moveBy(ix, iy);
    if (ok) {
      _carryX = x - ix;
      _carryY = y - iy;
    } else {
      _carryX = 0;
      _carryY = 0;
    }
    return ok;
  }

  /// A real click at the pointer's current position, [count] times. The
  /// press/release pairs go out as one `SendInput` batch, which Windows
  /// reads as a double click when [count] is 2 (same spot, well inside the
  /// system double-click time).
  bool click(String button, int count) {
    if (!_injector.available) return false;
    if (!buttons.contains(button) || !clickCounts.contains(count)) {
      return false;
    }
    return _injector.click(button, count);
  }

  /// The cursor's screen position, when it is cheap to read (the ack's
  /// optional `{x, y}`).
  ({int x, int y})? cursor() => _injector.cursor();

  double _safeScale() {
    final double s = _scale();
    if (!s.isFinite || s <= 0) return 1;
    return s;
  }

  static double _viewScale() {
    try {
      return WidgetsBinding
              .instance.platformDispatcher.implicitView?.devicePixelRatio ??
          1.0;
    } catch (_) {
      return 1;
    }
  }
}

/// The OS seam [RemoteInputService] drives. Production is
/// [RemotePointerInjector.platform] (Win32 `SendInput` on Windows, nothing
/// elsewhere); tests pass a recording fake.
abstract class RemotePointerInjector {
  const RemotePointerInjector();

  /// Win32 on Windows; [UnavailablePointerInjector] everywhere else (and if
  /// user32 cannot be bound — the verb then answers `no_web_mouse` and the
  /// flag is not advertised).
  factory RemotePointerInjector.platform() {
    if (!Platform.isWindows) return const UnavailablePointerInjector();
    try {
      return Win32PointerInjector();
    } catch (_) {
      return const UnavailablePointerInjector();
    }
  }

  bool get available;

  /// Relative move in device pixels. True when the OS accepted the event.
  bool moveBy(int dx, int dy);

  /// [button] is `left` / `right` / `middle`; [count] is 1 or 2.
  bool click(String button, int count);

  ({int x, int y})? cursor();
}

class UnavailablePointerInjector extends RemotePointerInjector {
  const UnavailablePointerInjector();

  @override
  bool get available => false;

  @override
  bool moveBy(int dx, int dy) => false;

  @override
  bool click(String button, int count) => false;

  @override
  ({int x, int y})? cursor() => null;
}

/// `SendInput` / `GetCursorPos` from user32 (the same FFI shape as
/// `remote_fs_service.dart`'s `_Win32`). The `INPUT` struct is written by
/// hand into a byte buffer because its union offset depends on the pointer
/// size: `type` (DWORD) is followed by a union whose `MOUSEINPUT` ends in a
/// `ULONG_PTR`, so the union sits at offset 8 and `INPUT` is 40 bytes on
/// 64-bit Windows, offset 4 / 28 bytes on 32-bit.
class Win32PointerInjector extends RemotePointerInjector {
  Win32PointerInjector() : _user32 = DynamicLibrary.open('user32.dll') {
    _sendInput = _user32.lookupFunction<
        Uint32 Function(Uint32, Pointer<Uint8>, Int32),
        int Function(int, Pointer<Uint8>, int)>('SendInput');
    _getCursorPos = _user32.lookupFunction<Int32 Function(Pointer<Int32>),
        int Function(Pointer<Int32>)>('GetCursorPos');
  }

  final DynamicLibrary _user32;
  late final int Function(int, Pointer<Uint8>, int) _sendInput;
  late final int Function(Pointer<Int32>) _getCursorPos;

  static const int _inputMouse = 0;
  static const int _move = 0x0001;
  static const int _leftDown = 0x0002;
  static const int _leftUp = 0x0004;
  static const int _rightDown = 0x0008;
  static const int _rightUp = 0x0010;
  static const int _middleDown = 0x0020;
  static const int _middleUp = 0x0040;

  static int get _unionOffset => sizeOf<IntPtr>() == 8 ? 8 : 4;
  static int get _inputSize => sizeOf<IntPtr>() == 8 ? 40 : 28;

  @override
  bool get available => true;

  @override
  bool moveBy(int dx, int dy) =>
      _send(<(int, int, int)>[(dx, dy, _move)]);

  @override
  bool click(String button, int count) {
    final (int down, int up) = switch (button) {
      'right' => (_rightDown, _rightUp),
      'middle' => (_middleDown, _middleUp),
      _ => (_leftDown, _leftUp),
    };
    return _send(<(int, int, int)>[
      for (int i = 0; i < count; i++) ...<(int, int, int)>[
        (0, 0, down),
        (0, 0, up),
      ],
    ]);
  }

  @override
  ({int x, int y})? cursor() {
    final Pointer<Int32> point = calloc<Int32>(2);
    try {
      if (_getCursorPos(point) == 0) return null;
      return (x: point[0], y: point[1]);
    } catch (_) {
      return null;
    } finally {
      calloc.free(point);
    }
  }

  /// One `SendInput` call for the whole batch — the events land back to
  /// back, never interleaved with the physical mouse. The return value is
  /// the number of events inserted; anything short of the batch means the
  /// input was blocked (a locked desktop, UIPI against an elevated window).
  bool _send(List<(int dx, int dy, int flags)> events) {
    final int size = _inputSize;
    final int offset = _unionOffset;
    final Pointer<Uint8> buffer = calloc<Uint8>(size * events.length);
    try {
      final ByteData data =
          ByteData.sublistView(buffer.asTypedList(size * events.length));
      for (int i = 0; i < events.length; i++) {
        final int base = i * size;
        final (int dx, int dy, int flags) = events[i];
        data.setUint32(base, _inputMouse, Endian.little);
        data.setInt32(base + offset, dx, Endian.little); // dx
        data.setInt32(base + offset + 4, dy, Endian.little); // dy
        data.setUint32(base + offset + 8, 0, Endian.little); // mouseData
        data.setUint32(base + offset + 12, flags, Endian.little); // dwFlags
        data.setUint32(base + offset + 16, 0, Endian.little); // time
        // dwExtraInfo stays 0 (calloc).
      }
      final int sent = _sendInput(events.length, buffer, size);
      return sent == events.length;
    } catch (_) {
      return false;
    } finally {
      calloc.free(buffer);
    }
  }
}
