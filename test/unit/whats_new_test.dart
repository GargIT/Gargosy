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

  group('whatsNewToShow', () {
    test('after an update: shown once, then not again', () async {
      final prefs = MemoryPrefs();
      await prefs.setString(lastRunVersionKey, '0.1.0');
      expect(await whatsNewToShow(prefs, '0.2.0', readChangelog: () => _changelog), contains('- Two.'));
      expect(prefs.getString(lastRunVersionKey), '0.2.0');
      expect(await whatsNewToShow(prefs, '0.2.0', readChangelog: () => _changelog), isNull);
    });

    test('a first start shows nothing, and records the version', () async {
      final prefs = MemoryPrefs();
      expect(await whatsNewToShow(prefs, '0.2.0', readChangelog: () => _changelog), isNull);
      expect(prefs.getString(lastRunVersionKey), '0.2.0');
    });

    test('a downgrade shows nothing and keeps the newer version', () async {
      final prefs = MemoryPrefs();
      await prefs.setString(lastRunVersionKey, '0.3.0');
      expect(await whatsNewToShow(prefs, '0.2.0', readChangelog: () => _changelog), isNull);
      expect(prefs.getString(lastRunVersionKey), '0.3.0');
    });

    test('no changelog (or unreadable): nothing shown, but the version is recorded', () async {
      final prefs = MemoryPrefs();
      await prefs.setString(lastRunVersionKey, '0.1.0');
      expect(await whatsNewToShow(prefs, '0.2.0', readChangelog: () => null), isNull);
      expect(await whatsNewToShow(MemoryPrefs()..values[lastRunVersionKey] = '0.1.0', '0.2.0',
          readChangelog: () => throw StateError('locked')), isNull);
      expect(prefs.getString(lastRunVersionKey), '0.2.0');
    });

    test('a dev build is recorded as it is (build metadata dropped); the release after it shows its section', () async {
      final prefs = MemoryPrefs()..values[lastRunVersionKey] = '0.1.0';
      expect(await whatsNewToShow(prefs, '0.2.0-dev+5', readChangelog: () => _changelog), isNull,
          reason: '0.2.0-dev sorts before 0.2.0-preview.2: nothing released in between');
      expect(prefs.getString(lastRunVersionKey), '0.2.0-dev');
      expect(await whatsNewToShow(prefs, '0.2.0', readChangelog: () => _changelog), contains('- Two.'));
    });
  });
}
