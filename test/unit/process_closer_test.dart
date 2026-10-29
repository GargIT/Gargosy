import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/emulators/process_closer.dart';

void main() {
  group('processCloserFor (#199)', () {
    test('Windows closes with taskkill', () {
      expect(processCloserFor(const PlatformInfo('windows')), isA<TaskkillProcessCloser>());
    });

    test('an OS without a closer yet is refused, not given taskkill', () {
      expect(() => processCloserFor(const PlatformInfo('linux')), throwsUnsupportedError);
    });
  });
}
