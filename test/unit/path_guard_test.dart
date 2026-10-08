import 'package:flutter_test/flutter_test.dart';
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
}
