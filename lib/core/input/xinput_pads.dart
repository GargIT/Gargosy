import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:win32/win32.dart';

import 'gamepad_service.dart';
import 'held_combo.dart';

/// The quit combo's buttons read straight from XInput while a game runs
/// (#141): GameInput, which [GamepadService] reads, sends nothing while an
/// emulator is in front, and XInput answers whichever window has the
/// focus. Each of the four XInput slots is a controller of its own
/// (`xinput<n>`) on [held].
class XInputPads {
  XInputPads(this.held, {this.every = const Duration(milliseconds: 50)});

  final StreamController<HeldButtons> held;
  final Duration every;

  static const _bits = {
    XINPUT_GAMEPAD_BACK: PadButton.select,
    XINPUT_GAMEPAD_START: PadButton.start,
    XINPUT_GAMEPAD_LEFT_SHOULDER: PadButton.l1,
    XINPUT_GAMEPAD_RIGHT_SHOULDER: PadButton.r1,
    XINPUT_GAMEPAD_LEFT_THUMB: PadButton.l3,
    XINPUT_GAMEPAD_RIGHT_THUMB: PadButton.r3,
  };

  Timer? _timer;
  Pointer<XINPUT_STATE>? _state;
  final _last = List<int>.filled(XUSER_MAX_COUNT, 0);

  void start() {
    if (_timer != null) return;
    _state = calloc<XINPUT_STATE>();
    _last.fillRange(0, _last.length, 0);
    _timer = Timer.periodic(every, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    final state = _state;
    _state = null;
    if (state != null) calloc.free(state);
  }

  void _poll() {
    final state = _state;
    if (state == null) return;
    try {
      for (var i = 0; i < XUSER_MAX_COUNT; i++) {
        final read = XInputGetState(i, state);
        if (read != ERROR_SUCCESS && read != ERROR_DEVICE_NOT_CONNECTED) debugPrint('[Quit] xinput$i read: $read');
        final pressed = read == ERROR_SUCCESS ? state.ref.Gamepad.wButtons : 0;
        var bits = 0;
        for (final b in _bits.keys) {
          if (pressed & b != 0) bits |= b;
        }
        if (bits == _last[i]) continue;
        _last[i] = bits;
        final buttons = {
          for (final e in _bits.entries)
            if (bits & e.key != 0) e.value,
        };
        debugPrint('[Quit] xinput$i holds ${buttons.map((b) => b.name).join(' + ')}');
        if (!held.isClosed) held.add(HeldButtons('xinput$i', buttons));
      }
    } catch (e) {
      debugPrint('[Quit] XInput can not be read: $e');
      stop();
    }
  }
}
