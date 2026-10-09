import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  LaunchContext ctx(String emulator, {String profile = 'aaa', String? subfolder}) {
    final paths = ProfilePaths(root, profile);
    final exeDir = p.join(root.emulators, emulator, subfolder ?? '');
    io.Directory(exeDir).createSync(recursive: true);
    return LaunchContext(
      data: paths.emulatorDir(emulator),
      exeDir: exeDir,
      bios: root.bios,
      profileId: profile,
      profilesDir: root.profiles,
      guard: PathGuard(root, activeProfileId: profile),
    );
  }

  test('only the probed emulators are supported in v1', () {
    expect(ProfileLaunchConfig.supported,
        {'dolphin', 'pcsx2', 'retroarch', 'mame', 'xenia_canary', 'ares', 'xemu', 'ppsspp', 'duckstation', 'mgba', 'flycast'});
    expect(ProfileLaunchConfig.of('ryujinx'), isNull);
  });

  test('dolphin, xenia, ares and mame get their data-folder arguments', () async {
    final d = ctx('dolphin');
    expect(await ProfileLaunchConfig.of('dolphin')!.prepare(d), ['--user=${d.data}']);
    final x = ctx('xenia_canary');
    expect(await ProfileLaunchConfig.of('xenia_canary')!.prepare(x), [
      '--content_root=${p.join(x.data, 'content')}',
      '--storage_root=${p.join(x.data, 'storage')}',
      '--cache_root=${p.join(x.data, 'cache')}',
      '--log_file=${p.join(x.data, 'xenia.log')}',
    ]);
    final a = ctx('ares');
    final aresArgs = await ProfileLaunchConfig.of('ares')!.prepare(a);
    expect(aresArgs.take(2), ['--settings-file', p.join(a.data, 'settings.bml')]);
    expect(aresArgs, contains('Paths/Saves=${p.join(a.data, 'saves')}\\'));
    final m = ctx('mame');
    final mameArgs = await ProfileLaunchConfig.of('mame')!.prepare(m);
    expect(mameArgs.sublist(0, 2), ['-inipath', m.data]);
    expect(mameArgs, containsAllInOrder(['-nvram_directory', p.join(m.data, 'nvram')]));
    expect(io.Directory(d.data).existsSync(), isTrue);
  });

  test('pcsx2: -datapath, and portable markers next to the exe are turned off', () async {
    final c = ctx('pcsx2');
    io.File(p.join(c.exeDir, 'portable.txt')).writeAsStringSync('');
    expect(await ProfileLaunchConfig.of('pcsx2')!.prepare(c), ['-datapath', c.data]);
    expect(io.File(p.join(c.exeDir, 'portable.txt')).existsSync(), isFalse);
    expect(io.File(p.join(c.exeDir, 'portable.txt.gargosy-off')).existsSync(), isTrue);
  });

  test('retroarch: the profile cfg points every writable folder into the profile', () async {
    final c = ctx('retroarch');
    expect(await ProfileLaunchConfig.of('retroarch')!.prepare(c), ['--config=${p.join(c.data, 'retroarch.cfg')}']);
    final cfg = io.File(p.join(c.data, 'retroarch.cfg')).readAsStringSync();
    expect(cfg, contains('savefile_directory = "${p.join(c.data, 'saves')}"'));
    expect(cfg, contains('system_directory = "${p.join(c.data, 'system')}"'));
    expect(cfg, contains('core_info_cache_enable = "false"'));
    // a second prepare changes the keys in place, never duplicates them
    await ProfileLaunchConfig.of('retroarch')!.prepare(c);
    final again = io.File(p.join(c.data, 'retroarch.cfg')).readAsStringSync();
    expect(RegExp('^savefile_directory', multiLine: true).allMatches(again).length, 1);
  });

  test('ppsspp: installed.txt points at the profile; a portable memstick is moved aside', () async {
    final c = ctx('ppsspp');
    io.Directory(p.join(c.exeDir, 'memstick', 'PSP')).createSync(recursive: true);
    expect(await ProfileLaunchConfig.of('ppsspp')!.prepare(c), isEmpty);
    expect(io.File(p.join(c.exeDir, 'installed.txt')).readAsStringSync(), c.data);
    expect(io.Directory(p.join(c.exeDir, 'memstick')).existsSync(), isFalse);
  });

  test('xemu: its toml keeps the EEPROM and hard disk in the profile', () async {
    final c = ctx('xemu');
    expect(await ProfileLaunchConfig.of('xemu')!.prepare(c), ['-config_path', p.join(c.data, 'xemu.toml')]);
    final toml = io.File(p.join(c.data, 'xemu.toml')).readAsStringSync();
    expect(toml, contains('[sys.files]'));
    expect(toml, contains("eeprom_path = '${p.join(c.data, 'eeprom.bin')}'"));
    expect(toml, contains("hdd_path = '${p.join(c.data, 'xbox_hdd.qcow2')}'"));
  });

  test('duckstation: the profile settings are swapped in with folders in the profile, and back after exit', () async {
    final a = ctx('duckstation');
    final cfg = ProfileLaunchConfig.of('duckstation')!;
    await cfg.prepare(a);
    final live = io.File(p.join(a.exeDir, 'settings.ini'));
    expect(io.File(p.join(a.exeDir, 'portable.txt')).existsSync(), isTrue);
    expect(live.readAsStringSync(), contains('Directory = ${p.join(a.data, 'memcards')}'));
    expect(live.readAsStringSync(), contains('SaveStates = ${p.join(a.data, 'savestates')}'));
    live.writeAsStringSync('${live.readAsStringSync()}[Display]\nFullscreen = true\n'); // the user changed a setting
    await cfg.finish(a);
    expect(io.File(p.join(a.data, 'settings.ini')).readAsStringSync(), contains('Fullscreen = true'));
    expect(io.File(p.join(a.exeDir, '.gargosy-swap')).existsSync(), isFalse);
  });

  test('a swap left over from a crash goes back to its own profile first', () async {
    final cfg = ProfileLaunchConfig.of('mgba')!;
    final a = ctx('mgba', profile: 'aaa');
    await cfg.prepare(a);
    io.File(p.join(a.exeDir, 'config.ini')).writeAsStringSync('[ports.qt]\nanna=1\n');
    // Gargosy dies here: no finish(). Then Bob plays.
    final b = ctx('mgba', profile: 'bbb');
    await cfg.prepare(b);
    expect(io.File(p.join(a.data, 'config.ini')).readAsStringSync(), contains('anna=1'));
    expect(io.File(p.join(b.data, 'config.ini')).existsSync() ? io.File(p.join(b.data, 'config.ini')).readAsStringSync() : '',
        isNot(contains('anna=1')));
    expect(io.File(p.join(b.exeDir, 'config.ini')).existsSync() ? io.File(p.join(b.exeDir, 'config.ini')).readAsStringSync() : '',
        isNot(contains('anna=1')));
  });

  test('a crash with the exe in a subfolder still puts the settings back in the right emulator folder', () async {
    final cfg = ProfileLaunchConfig.of('mgba')!;
    final a = ctx('mgba', profile: 'aaa', subfolder: 'mGBA-0.10.5-win64');
    await cfg.prepare(a);
    io.File(p.join(a.exeDir, 'config.ini')).writeAsStringSync('[ports.qt]\nanna=1\n');
    await cfg.prepare(ctx('mgba', profile: 'bbb', subfolder: 'mGBA-0.10.5-win64'));
    expect(io.File(p.join(a.data, 'config.ini')).readAsStringSync(), contains('anna=1'));
  });

  test('mgba and flycast get their save-folder overrides; flycast stays portable', () async {
    final m = ctx('mgba');
    expect(await ProfileLaunchConfig.of('mgba')!.prepare(m),
        ['-C', 'savegamePath=${p.join(m.data, 'saves')}', '-C', 'savestatePath=${p.join(m.data, 'states')}']);
    expect(io.File(p.join(m.exeDir, 'portable.ini')).existsSync(), isTrue);
    final f = ctx('flycast');
    final args = await ProfileLaunchConfig.of('flycast')!.prepare(f);
    expect(args.first, '-config');
    expect(args[1], contains('Dreamcast.VMUPath=${p.join(f.data, 'vmu')}'));
    expect(io.File(p.join(f.exeDir, 'emu.cfg')).existsSync(), isTrue);
  });

  test('the launch view starts the exe with the profile arguments first, then the strategy\'s, then the ROM', () async {
    final paths = ProfilePaths(root, 'aaa');
    final exe = io.File(p.join(root.emulators, 'dolphin', 'Dolphin.exe'))..createSync(recursive: true);
    final started = <List<String>>[];
    final dirs = ProfileLaunchDirectories(
      root: root,
      paths: paths,
      prefs: MemoryPrefs(),
      start: (exePath, args, {workingDirectory}) async {
        started.add([exePath, ...args]);
        return io.Process.start('cmd.exe', ['/c', 'exit', '0']);
      },
    );
    await dirs.launchGameWithHandle(game(1, 'G'), r'D:\roms\gc\g.iso', 'dolphin', exe.path, args: ['-b', '-e']);
    expect(started.single, [exe.path, '--user=${paths.emulatorDir('dolphin')}', '-b', '-e', r'D:\roms\gc\g.iso']);
  });

  test('an emulator Gargosy can\'t point at a profile is refused', () async {
    final dirs = ProfileLaunchDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
    expect(() => dirs.launchGameWithHandle(game(1, 'G'), 'x', 'ryujinx', r'C:\x\Ryujinx.exe'),
        throwsA(isA<UnsupportedEmulatorException>()));
  });

  test("retroarch: each profile has its own system folder (cores keep cards there), with the BIOS copied in", () async {
    io.File(p.join(root.bios, 'pcsx2', 'bios', 'scph39001.bin'))
      ..createSync(recursive: true)
      ..writeAsStringSync('bios');
    final a = ctx('retroarch', profile: 'aaa');
    final b = ctx('retroarch', profile: 'bbb');
    await ProfileLaunchConfig.of('retroarch')!.prepare(a);
    await ProfileLaunchConfig.of('retroarch')!.prepare(b);
    expect(io.File(p.join(a.data, 'system', 'pcsx2', 'bios', 'scph39001.bin')).readAsStringSync(), 'bios');
    expect(io.File(p.join(b.data, 'system', 'pcsx2', 'bios', 'scph39001.bin')).existsSync(), isTrue);
    // A card the core made in A's system folder never reaches B.
    io.File(p.join(a.data, 'system', 'pcsx2', 'memcards', 'Mcd001.ps2')).createSync(recursive: true);
    await ProfileLaunchConfig.of('retroarch')!.prepare(b);
    expect(io.File(p.join(b.data, 'system', 'pcsx2', 'memcards', 'Mcd001.ps2')).existsSync(), isFalse);
    expect(io.File(p.join(root.bios, 'pcsx2', 'memcards', 'Mcd001.ps2')).existsSync(), isFalse);
  });

  test('repoint: a moved Gargosy folder gets its stored folder paths rewritten before the save pull', () async {
    final d = ctx('duckstation');
    io.File(p.join(d.data, 'settings.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[MemoryCards]\nDirectory = E:\\OldGargosy\\memcards\n[Main]\nLanguage = sv\n');
    ProfileLaunchConfig.of('duckstation')!.repoint(d);
    final ini = io.File(p.join(d.data, 'settings.ini')).readAsStringSync();
    expect(ini, contains('Directory = ${p.join(d.data, 'memcards')}'));
    expect(ini, contains('Language = sv'));
    final r = ctx('retroarch');
    io.File(p.join(r.data, 'retroarch.cfg'))
      ..createSync(recursive: true)
      ..writeAsStringSync('savefile_directory = "E:\\OldGargosy\\saves"\n');
    ProfileLaunchConfig.of('retroarch')!.repoint(r);
    expect(io.File(p.join(r.data, 'retroarch.cfg')).readAsStringSync(), contains(p.join(r.data, 'saves')));
  });
}
