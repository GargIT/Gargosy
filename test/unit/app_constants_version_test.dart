// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/constants/app_constants.dart';

void main() {
  test('a leading v from the release tag is dropped, so the UI shows a single v', () {
    expect(AppConstants.normalizeVersion('v0.6.1'), '0.6.1');
    expect(AppConstants.normalizeVersion('V0.6.1'), '0.6.1');
  });

  test('a plain version is left alone', () {
    expect(AppConstants.normalizeVersion('0.6.1'), '0.6.1');
    expect(AppConstants.normalizeVersion(' 0.6.1 '), '0.6.1');
  });

  group('displayVersionOf', () {
    test("a release's numeric build number (pubspec's +11) is left out", () {
      expect(AppConstants.displayVersionOf('0.11.0', '11'), '0.11.0');
      expect(AppConstants.displayVersionOf('0.11.0', '0'), '0.11.0');
      expect(AppConstants.displayVersionOf('0.11.0', ''), '0.11.0');
      expect(AppConstants.displayVersionOf('0.11.0', ' '), '0.11.0');
    });

    test('other build metadata is kept after a +', () {
      expect(AppConstants.displayVersionOf('0.11.0', 'handtest.43aa4b1'), '0.11.0+handtest.43aa4b1');
      expect(AppConstants.displayVersionOf('0.2.0-preview.4', 'abc'), '0.2.0-preview.4+abc');
    });

    test('displayVersion follows version and buildNumber; version itself never carries metadata', () {
      final version = AppConstants.version;
      final build = AppConstants.buildNumber;
      addTearDown(() {
        AppConstants.version = version;
        AppConstants.buildNumber = build;
      });
      AppConstants.version = '0.11.0';
      AppConstants.buildNumber = 'handtest.43aa4b1';
      expect(AppConstants.displayVersion, '0.11.0+handtest.43aa4b1');
      expect(AppConstants.version, '0.11.0');
    });
  });
}
