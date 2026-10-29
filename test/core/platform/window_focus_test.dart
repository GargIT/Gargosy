import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/platform/window_focus.dart';

void main() {
  group('windowFocusFor (#202)', () {
    test('Windows gets the Alt-tap focus', () {
      expect(windowFocusFor(const PlatformInfo('windows')), isA<WindowsWindowFocus>());
    });

    test('an OS without window focus yet is refused', () {
      expect(() => windowFocusFor(const PlatformInfo('linux')), throwsUnsupportedError);
    });
  });

  test('without the window plugin (tests) it does nothing and never throws', () async {
    await const WindowsWindowFocus().bringToFront();
  });
}
