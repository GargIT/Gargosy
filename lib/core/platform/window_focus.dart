import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import 'platform_info.dart';
import 'window_service.dart';

/// Puts Gargosy back in front once an emulator has closed (#141, #202).
/// Never throws: a window that stays behind mustn't fail the session.
abstract class WindowFocus {
  Future<void> bringToFront();
}

/// The [WindowFocus] of [platform]'s OS.
WindowFocus windowFocusFor(PlatformInfo platform) {
  if (platform.isWindows) return const WindowsWindowFocus();
  throw UnsupportedError('No window focus on ${platform.os} yet');
}

final windowFocusProvider = Provider<WindowFocus>((ref) => windowFocusFor(PlatformInfo.current));

/// Windows lets only the process with the last input take the foreground,
/// and a controller's buttons don't count: when the plain try doesn't take
/// it, an Alt tap (sent to the window in front, not to Gargosy) lifts that
/// lock and it's tried again.
class WindowsWindowFocus implements WindowFocus {
  const WindowsWindowFocus();

  @override
  Future<void> bringToFront() async {
    if (!WindowService.initialized) return;
    try {
      await windowManager.focus();
      if (await windowManager.isFocused()) return;
      _tapAlt();
      await windowManager.focus();
      debugPrint('[Window] brought to front: ${await windowManager.isFocused()}');
    } catch (e) {
      debugPrint('[Window] bringToFront failed: $e');
    }
  }

  static void _tapAlt() {
    final inputs = calloc<INPUT>(2);
    try {
      for (var i = 0; i < 2; i++) {
        inputs[i].type = INPUT_KEYBOARD;
        inputs[i].ki.wVk = VK_MENU;
        inputs[i].ki.dwFlags = i == 0 ? 0 : KEYEVENTF_KEYUP;
      }
      SendInput(2, inputs, sizeOf<INPUT>());
    } finally {
      calloc.free(inputs);
    }
  }
}
