// Issue #3: what's new after an update, once, from CHANGELOG.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/changelog/whats_new.dart';
import 'package:pub_semver/pub_semver.dart';

import '../helpers/profile_test_env.dart';

const _changelog = '''
# Changelog

What changed in each release of Gargosy.

## [Unreleased]

### Added

- Not out yet.

## [0.3.0] - 2026-12-01

### Added

- Three.

## [0.2.0] - 2026-11-01

### Fixed

- Two.

## [0.2.0-preview.2] - 2026-10-20

- Preview two.

## [0.1.0] - 2026-10-10

- One.

[Unreleased]: https://github.com/GargIT/Gargosy/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.3.0
''';

void main() {
  group('changelogSince', () {
    test('every section after the last version, up to this one, a skipped release too', () {
      final text = changelogSince(_changelog, Version(0, 1, 0), Version(0, 3, 0))!;
      expect(text, startsWith('## [0.3.0] - 2026-12-01'));
      expect(text, contains('- Three.'));
      expect(text, contains('- Two.'));
      expect(text, contains('- Preview two.'));
      expect(text, isNot(contains('- One.')));
      expect(text, isNot(contains('Not out yet')), reason: '[Unreleased] never counts');
      expect(text, isNot(contains('# Changelog')));
      expect(text, isNot(contains('compare/')), reason: 'the link list at the end is left out');
    });

    test('a preview to its release: only the release', () {
      final text = changelogSince(_changelog, Version.parse('0.2.0-preview.2'), Version(0, 2, 0))!;
      expect(text, startsWith('## [0.2.0]'));
      expect(text, isNot(contains('Preview two')));
    });

    test('nothing between: null', () {
      expect(changelogSince(_changelog, Version(0, 3, 0), Version(0, 3, 1)), isNull);
    });
  });

  test("a reference link inside a section doesn't cut the section short", () {
    const md = '## [0.2.0] - 2026-11-01\n\n- Fixed X ([#3]).\n\n[#3]: https://github.com/GargIT/Gargosy/issues/3\n\n- Fixed Y.\n';
    final text = changelogSince(md, Version(0, 1, 0), Version(0, 2, 0))!;
    expect(text, contains('- Fixed Y.'));
  });

  group('whatsNewToShow', () {
    Future<String?> show(MemoryPrefs prefs, String current,
        {String? Function()? read, bool existingInstall = false}) async {
      final news = await whatsNewToShow(prefs, current,
          readChangelog: read ?? () => _changelog, existingInstall: existingInstall);
      await news.recordRun();
      return news.text;
    }

    test('after an update: shown once, then not again', () async {
      final prefs = MemoryPrefs()..values[lastRunVersionKey] = '0.1.0';
      expect(await show(prefs, '0.2.0'), contains('- Two.'));
      expect(prefs.getString(lastRunVersionKey), '0.2.0');
      expect(await show(prefs, '0.2.0'), isNull);
    });

    test('nothing is recorded until the caller says it was shown', () async {
      final prefs = MemoryPrefs()..values[lastRunVersionKey] = '0.1.0';
      final news = await whatsNewToShow(prefs, '0.2.0', readChangelog: () => _changelog);
      expect(news.text, contains('- Two.'));
      expect(prefs.getString(lastRunVersionKey), '0.1.0', reason: 'not shown yet: next start shows it');
    });

    test('a fresh install shows nothing, and records the version', () async {
      final prefs = MemoryPrefs();
      expect(await show(prefs, '0.2.0'), isNull);
      expect(prefs.getString(lastRunVersionKey), '0.2.0');
    });

    test('Gargosy in use before this feature (no version recorded): this release only', () async {
      final prefs = MemoryPrefs();
      final text = await show(prefs, '0.2.0', existingInstall: true);
      expect(text, startsWith('## [0.2.0]'));
      expect(text, isNot(contains('Preview two')), reason: 'only the release that brings it');
      expect(prefs.getString(lastRunVersionKey), '0.2.0');
    });

    test('a downgrade shows nothing and keeps the newer version', () async {
      final prefs = MemoryPrefs()..values[lastRunVersionKey] = '0.3.0';
      expect(await show(prefs, '0.2.0'), isNull);
      expect(prefs.getString(lastRunVersionKey), '0.3.0');
    });

    test('no changelog, or one that throws: nothing shown, the version still recorded', () async {
      final missing = MemoryPrefs()..values[lastRunVersionKey] = '0.1.0';
      expect(await show(missing, '0.2.0', read: () => null), isNull);
      expect(missing.getString(lastRunVersionKey), '0.2.0');
      final locked = MemoryPrefs()..values[lastRunVersionKey] = '0.1.0';
      expect(await show(locked, '0.2.0', read: () => throw StateError('locked')), isNull);
      expect(locked.getString(lastRunVersionKey), '0.2.0');
    });

    test('a dev build is recorded as it is (build metadata dropped); the release after it shows its section', () async {
      final prefs = MemoryPrefs()..values[lastRunVersionKey] = '0.1.0';
      expect(await show(prefs, '0.2.0-dev+5'), isNull,
          reason: '0.2.0-dev sorts before 0.2.0-preview.2: nothing released in between');
      expect(prefs.getString(lastRunVersionKey), '0.2.0-dev');
      expect(await show(prefs, '0.2.0'), contains('- Two.'));
    });
  });
}
