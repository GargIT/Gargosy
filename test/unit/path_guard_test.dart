import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';

void main() {
  final root = AppRoot(r'D:\Gargosy');
  final guard = PathGuard(root, activeProfileId: 'aaa');

  test('allows the shared folders, settings.json and the active profile', () {
    for (final ok in [
      r'D:\Gargosy\roms\ps2\Burnout 3.chd',
      r'D:\Gargosy\emulators\dolphin\Dolphin.exe',
      r'D:\Gargosy\bios\scph1001.bin',
      r'D:\Gargosy\userdata\templates\dolphin\Config\Dolphin.ini',
      r'D:\Gargosy\userdata\app\temp\x',
      r'D:\Gargosy\userdata\settings.json',
      r'D:\Gargosy\userdata\profiles\aaa\profile.json',
    ]) {
      expect(guard.check(ok), ok, reason: ok);
    }
  });

  test('is case-insensitive, as Windows is', () {
    expect(guard.check(r'd:\gargosy\ROMS\x.iso'), r'd:\gargosy\ROMS\x.iso');
    expect(PathGuard(root, platform: const PlatformInfo('windows')).caseSensitive, isFalse);
  });

  test('guards on one root share its keys but keep their own profile and case rule', () {
    final shared = AppRoot(r'E:\Gargosy');
    final any = PathGuard(shared, activeProfileId: 'aaa', platform: const PlatformInfo('windows'));
    final exact = PathGuard(shared, activeProfileId: 'aaa', platform: const PlatformInfo('linux'));
    expect(any.check(r'E:\Gargosy\ROMS\x.iso'), r'E:\Gargosy\ROMS\x.iso');
    expect(() => exact.check(r'E:\Gargosy\ROMS\x.iso'), throwsA(isA<PathGuardException>()));
    expect(any.check(r'E:\Gargosy\userdata\SETTINGS.json'), r'E:\Gargosy\userdata\SETTINGS.json');
    expect(() => exact.check(r'E:\Gargosy\userdata\SETTINGS.json'), throwsA(isA<PathGuardException>()));
    final other = any.forProfile('bbb');
    expect(other.check(r'E:\Gargosy\userdata\profiles\bbb\x'), r'E:\Gargosy\userdata\profiles\bbb\x');
    expect(() => other.check(r'E:\Gargosy\userdata\profiles\aaa\x'), throwsA(isA<PathGuardException>()));
    expect(any.check(r'E:\Gargosy\userdata\profiles\aaa\x'), r'E:\Gargosy\userdata\profiles\aaa\x');
    expect(() => PathGuard(shared).check(r'E:\Gargosy\userdata\profiles\aaa\x'), throwsA(isA<PathGuardException>()));
  });

  group('on a case-sensitive file system (#204)', () {
    // The paths stay Windows' (the tests run there); only the comparison changes.
    final exact = PathGuard(root, activeProfileId: 'aaa', platform: const PlatformInfo('linux'));

    test('the allowed folders in their own case are writable', () {
      expect(exact.caseSensitive, isTrue);
      expect(exact.check(r'D:\Gargosy\roms\ps2\x.iso'), r'D:\Gargosy\roms\ps2\x.iso');
      expect(exact.check(r'D:\Gargosy\userdata\settings.json'), r'D:\Gargosy\userdata\settings.json');
      expect(exact.forProfile('aaa').check(r'D:\Gargosy\userdata\profiles\aaa\x'), isNotEmpty);
    });

    test('a folder that matches only when lowercased is another folder: refused', () {
      for (final bad in [
        r'D:\Gargosy\ROMS\x.iso',
        r'D:\gargosy\roms\x.iso',
        r'D:\Gargosy\userdata\Settings.json',
        r'D:\Gargosy\userdata\profiles\AAA\x',
        r'D:\Gargosy\userdata\App\temp\x',
      ]) {
        expect(() => exact.check(bad), throwsA(isA<PathGuardException>()), reason: bad);
      }
    });

    test('a server name that differs only in case lands in its own folder, never an allowed one', () {
      expect(() => exact.join(r'D:\Gargosy', 'ROMS'), throwsA(isA<PathGuardException>()));
      expect(exact.join(r'D:\Gargosy\roms', 'PS2'), r'D:\Gargosy\roms\PS2');
    });

    test('the profile from forProfile compares the same way', () {
      expect(exact.forProfile('aaa').caseSensitive, isTrue);
    });
  });

  test('samePath compares as the file system does, ignoring a trailing separator', () {
    final exact = PathGuard(root, platform: const PlatformInfo('linux'));
    final any = PathGuard(root, platform: const PlatformInfo('windows'));
    expect(any.samePath(r'D:\Gargosy\Profiles\aaa\', r'd:\gargosy\profiles\aaa'), isTrue);
    expect(exact.samePath(r'D:\Gargosy\Profiles\aaa', r'D:\Gargosy\profiles\aaa'), isFalse);
    expect(exact.samePath(r'D:\Gargosy\profiles\aaa\', r'D:\Gargosy\profiles\aaa'), isTrue);
  });

  test('rejects other profiles, userdata itself, outside folders and look-alike siblings', () {
    for (final bad in [
      r'D:\Gargosy\userdata\profiles\bbb\profile.json',
      r'D:\Gargosy\userdata\other.json',
      r'D:\Gargosy\userdata\profiles\aaa-evil\x',
      r'D:\Gargosy\romsX\x',
      r'C:\Windows\System32\x.dll',
      r'D:\Gargosy\roms\..\userdata\profiles\bbb\x',
    ]) {
      expect(() => guard.check(bad), throwsA(isA<PathGuardException>()), reason: bad);
    }
  });

  test('without an active profile no profile folder is writable', () {
    expect(() => PathGuard(root).check(r'D:\Gargosy\userdata\profiles\aaa\x'), throwsA(isA<PathGuardException>()));
  });

  test('forProfile gives a guard for that profile only', () {
    final b = guard.forProfile('bbb');
    expect(b.check(r'D:\Gargosy\userdata\profiles\bbb\x'), r'D:\Gargosy\userdata\profiles\bbb\x');
    expect(() => b.check(r'D:\Gargosy\userdata\profiles\aaa\x'), throwsA(isA<PathGuardException>()));
  });

  test('join accepts plain relative names and rejects escapes', () {
    expect(guard.join(r'D:\Gargosy\roms\ps2', r'SLUS-21050\disc.chd'), r'D:\Gargosy\roms\ps2\SLUS-21050\disc.chd');
    for (final bad in ['', r'..\x', r'a\..\..\x', r'C:\x', r'\x', '/x', 'a:b']) {
      expect(() => guard.join(r'D:\Gargosy\roms\ps2', bad), throwsA(isA<PathGuardException>()), reason: bad);
    }
  });

  test('refuses a profile id that is not one plain name', () {
    for (final bad in ['..', r'..\..', '../x', '.', '', r'a\b', 'A', 'x:y']) {
      expect(() => PathGuard(root, activeProfileId: bad), throwsArgumentError, reason: bad);
      expect(() => guard.forProfile(bad), throwsArgumentError, reason: bad);
    }
    expect(PathGuard.isProfileId('0f8e-4b2a'), isTrue);
  });

  test('isWithin compares as the file system does, and a folder is not within itself', () {
    expect(guard.isWithin(r'D:\Gargosy\emulators', r'd:\gargosy\EMULATORS\dolphin\User'), isTrue);
    expect(guard.isWithin(r'D:\Gargosy\emulators', r'D:\Gargosy\emulators'), isFalse);
    expect(guard.isWithin(r'D:\Gargosy\emulators', r'D:\Gargosy\emulators-old\x'), isFalse);
    expect(guard.isWithin(r'D:\Gargosy\emulators', r'D:\Gargosy\emulators\..\roms\x'), isFalse);
    final exact = PathGuard(root, platform: const PlatformInfo('linux'));
    expect(exact.isWithin(r'D:\Gargosy\emulators', r'D:\Gargosy\Emulators\dolphin'), isFalse);
    expect(exact.isWithin(r'D:\Gargosy\emulators', r'D:\Gargosy\emulators\dolphin'), isTrue);
  });
}
