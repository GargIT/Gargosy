import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_strategy.dart';
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

  LaunchContext ctx(String emulator, {String profile = 'aaa', String? subfolder, List<String> gameFolders = const []}) {
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
      roms: root.roms,
      gameFolders: gameFolders,
    );
  }

  test('only the probed emulators are supported in v1', () {
    expect(ProfileLaunchConfig.supported, {
      'dolphin',
      'pcsx2',
      'retroarch',
      'mame',
      'xenia_canary',
      'ares',
      'xemu',
      'ppsspp',
      'duckstation',
      'mgba',
      'flycast',
      'ryujinx', // -r (issue #9)
      // a folder link (issues #8, #12–#15)
      'eden', 'azahar', 'cemu', 'melonds',
      'rpcs3', // RPCS3_CONFIG_DIR (issue #10)
      'scummvm',
    }); // --config, --savepath (issue #11)
    expect(ProfileLaunchConfig.of('not_an_emulator'), isNull);
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

  test("pcsx2: the profile's PCSX2 looks for BIOS files in the shared bios folder", () async {
    final c = ctx('pcsx2');
    final ini = io.File(p.join(c.data, 'PCSX2', 'inis', 'PCSX2.ini'));
    // A new profile: PCSX2 hasn't written its settings yet.
    await ProfileLaunchConfig.of('pcsx2')!.prepare(c);
    expect(ini.readAsStringSync(), contains('SettingsVersion = 1'));
    expect(ini.readAsStringSync(), contains('Bios = ${root.bios}'));
    // PCSX2's own settings: only the BIOS folder changes.
    ini.writeAsStringSync(
      '[UI]\nSettingsVersion = 1\nSetupWizardIncomplete = true\n[Folders]\nBios = bios\nMemoryCards = memcards\n',
    );
    await ProfileLaunchConfig.of('pcsx2')!.prepare(c);
    final text = ini.readAsStringSync();
    expect(text, contains('Bios = ${root.bios}'));
    expect(text, contains('MemoryCards = memcards'));
    expect(text, contains('SetupWizardIncomplete = true'));
    expect(text, contains('ConfirmShutdown = false'), reason: 'the quit buttons close it without asking (#141)');
    expect(text, contains('SaveStateOnShutdown = true'), reason: 'closing keeps a resume state');
  });

  test('dolphin stops without asking when closed (#141)', () async {
    final d = ctx('dolphin');
    await ProfileLaunchConfig.of('dolphin')!.prepare(d);
    final ini = io.File(p.join(d.data, 'Config', 'Dolphin.ini')).readAsStringSync();
    expect(ini, contains('ConfirmStop = False'));
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

  test(
    "retroarch: saves stay flat in saves\\ (sigil's save root): sorting by core or content is put back off",
    () async {
      final c = ctx('retroarch');
      io.Directory(c.data).createSync(recursive: true);
      io.File(p.join(c.data, 'retroarch.cfg'))
          .writeAsStringSync('sort_savefiles_enable = "true"\nsort_savefiles_by_content_enable = "true"\n');
      await ProfileLaunchConfig.of('retroarch')!.prepare(c);
      final cfg = io.File(p.join(c.data, 'retroarch.cfg')).readAsStringSync();
      expect(cfg, contains('sort_savefiles_enable = "false"'));
      expect(cfg, contains('sort_savefiles_by_content_enable = "false"'));
      expect(RegExp(r'^sort_savefiles\w* = "true"', multiLine: true).hasMatch(cfg), isFalse);
    },
  );

  test("retroarch: saves it had sorted come up into saves\\ before sorting goes off; nothing is overwritten", () async {
    final c = ctx('retroarch');
    void put(String rel, String text) => io.File(p.join(c.data, 'saves', rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    put(p.join('PCSX-ReARMed', 'FF7.srm'), 'sorted by core');
    put(p.join('Snes9x', 'snes', 'Zelda.srm'), 'sorted by core and content');
    put(p.join('Snes9x', 'Mario.srm'), 'the sorted one');
    put('Mario.srm', 'already flat');
    io.File(p.join(c.data, 'retroarch.cfg')).writeAsStringSync('sort_savefiles_enable = "true"\n');
    await ProfileLaunchConfig.of('retroarch')!.prepare(c);
    String read(String rel) => io.File(p.join(c.data, 'saves', rel)).readAsStringSync();
    expect(read('FF7.srm'), 'sorted by core');
    expect(read('Zelda.srm'), 'sorted by core and content');
    expect(read('Mario.srm'), 'already flat');
    expect(read(p.join('Snes9x', 'Mario.srm')), 'the sorted one', reason: 'left where it was, not overwritten');
  });

  test('retroarch: saves and states never go next to the ROM', () async {
    final c = ctx('retroarch');
    io.Directory(c.data).createSync(recursive: true);
    io.File(p.join(c.data, 'retroarch.cfg'))
        .writeAsStringSync('savefiles_in_content_dir = "true"\nsavestates_in_content_dir = "true"\n');
    await ProfileLaunchConfig.of('retroarch')!.prepare(c);
    final cfg = io.File(p.join(c.data, 'retroarch.cfg')).readAsStringSync();
    expect(cfg, contains('savefiles_in_content_dir = "false"'));
    expect(cfg, contains('savestates_in_content_dir = "false"'));
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

  test("xemu: the hard disk in bios\\ is copied into the profile once, and the ROMs come from bios\\", () async {
    io.Directory(root.bios).createSync(recursive: true);
    io.File(p.join(root.bios, 'xbox_hdd.qcow2')).writeAsBytesSync([1, 2, 3]);
    io.File(p.join(root.bios, 'mcpx_1.0.bin')).writeAsBytesSync([4]);
    io.File(p.join(root.bios, 'Complex_4627.bin')).writeAsBytesSync([5]);
    final c = ctx('xemu');
    await ProfileLaunchConfig.of('xemu')!.prepare(c);
    final hdd = io.File(p.join(c.data, 'xbox_hdd.qcow2'));
    expect(hdd.readAsBytesSync(), [1, 2, 3]);
    final toml = io.File(p.join(c.data, 'xemu.toml')).readAsStringSync();
    expect(toml, contains("bootrom_path = '${p.join(root.bios, 'mcpx_1.0.bin')}'"));
    expect(toml, contains("flashrom_path = '${p.join(root.bios, 'Complex_4627.bin')}'"));

    // The profile's disk holds its saves: a later launch never replaces it.
    hdd.writeAsBytesSync([9, 9]);
    await ProfileLaunchConfig.of('xemu')!.prepare(c);
    expect(hdd.readAsBytesSync(), [9, 9]);
    // A real copy, not a link: another profile's disk is its own.
    expect(io.File(p.join(root.bios, 'xbox_hdd.qcow2')).readAsBytesSync(), [1, 2, 3]);
  });

  test('xemu: ROM paths the profile set itself stay, unless the file is gone', () async {
    io.Directory(root.bios).createSync(recursive: true);
    io.File(p.join(root.bios, 'mcpx_1.0.bin')).writeAsBytesSync([4]);
    io.File(p.join(root.bios, 'Complex_4627.bin')).writeAsBytesSync([5]);
    final own = io.File(p.join(root.root, 'my_flash.bin'))..writeAsBytesSync([6]);
    final c = ctx('xemu');
    io.Directory(c.data).createSync(recursive: true);
    io.File(p.join(c.data, 'xemu.toml')).writeAsStringSync(
      "[sys.files]\nflashrom_path = '${own.path}'\nbootrom_path = '${p.join(root.root, 'gone.bin')}'\n",
    );
    await ProfileLaunchConfig.of('xemu')!.prepare(c);
    final toml = io.File(p.join(c.data, 'xemu.toml')).readAsStringSync();
    expect(toml, contains("flashrom_path = '${own.path}'"));
    expect(toml, contains("bootrom_path = '${p.join(root.bios, 'mcpx_1.0.bin')}'"));
  });

  test('duckstation: the profile settings are swapped in with folders in the profile, and back after exit', () async {
    final a = ctx('duckstation');
    final cfg = ProfileLaunchConfig.of('duckstation')!;
    await cfg.prepare(a);
    final live = io.File(p.join(a.exeDir, 'settings.ini'));
    expect(io.File(p.join(a.exeDir, 'portable.txt')).existsSync(), isTrue);
    expect(live.readAsStringSync(), contains('Directory = ${p.join(a.data, 'memcards')}'));
    expect(live.readAsStringSync(), contains('SaveStates = ${p.join(a.data, 'savestates')}'));
    expect(live.readAsStringSync(), contains('SaveStateOnExit = true'), reason: 'closing keeps a resume state');
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
    expect(
      io.File(p.join(b.data, 'config.ini')).existsSync()
          ? io.File(p.join(b.data, 'config.ini')).readAsStringSync()
          : '',
      isNot(contains('anna=1')),
    );
    expect(
      io.File(p.join(b.exeDir, 'config.ini')).existsSync()
          ? io.File(p.join(b.exeDir, 'config.ini')).readAsStringSync()
          : '',
      isNot(contains('anna=1')),
    );
  });

  test('a swap marker whose profile or emulator is not one plain name writes nothing', () async {
    final cfg = ProfileLaunchConfig.of('mgba')!;
    for (final bad in [
      {'profile': '..'},
      {'emulator': r'..\..\..\..\roms\x'},
    ]) {
      final a = ctx('mgba', profile: 'aaa');
      await cfg.prepare(a);
      final mark = io.File(p.join(a.exeDir, '.gargosy-swap'));
      final json = jsonDecode(mark.readAsStringSync()) as Map<String, dynamic>;
      mark.writeAsStringSync(jsonEncode({...json, ...bad}));
      final b = ctx('mgba', profile: 'bbb');
      await cfg.prepare(b);
      expect(io.Directory(p.join(a.profilesDir, '..', 'emulators')).existsSync(), isFalse, reason: '$bad');
      expect(io.Directory(p.join(root.roms, 'x')).existsSync(), isFalse, reason: '$bad');
      // The launch goes on: the marker is the new profile's.
      expect(jsonDecode(mark.readAsStringSync()), containsPair('profile', 'bbb'), reason: '$bad');
      await cfg.finish(b);
    }
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
    expect(await ProfileLaunchConfig.of('mgba')!.prepare(m), [
      '-C',
      'savegamePath=${p.join(m.data, 'saves')}',
      '-C',
      'savestatePath=${p.join(m.data, 'states')}',
    ]);
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
      start: (exePath, args, {workingDirectory, environment}) async {
        started.add([exePath, ...args]);
        return io.Process.start('cmd.exe', ['/c', 'exit', '0']);
      },
    );
    await dirs.launchGameWithHandle(game(1, 'G'), r'D:\roms\gc\g.iso', 'dolphin', exe.path, args: ['-b', '-e']);
    // The full screen flag first (on by default), then the profile's, the strategy's, the ROM.
    expect(started.single, [
      exe.path,
      '-C',
      'Dolphin.Display.Fullscreen=True',
      '--user=${paths.emulatorDir('dolphin')}',
      '-b',
      '-e',
      r'D:\roms\gc\g.iso',
    ]);
  });

  test("Open (an emulator on its own): the profile's folder, no game, no batch mode, not full screen", () async {
    final paths = ProfilePaths(root, 'aaa');
    final exe = io.File(p.join(root.emulators, 'dolphin', 'Dolphin.exe'))..createSync(recursive: true);
    final started = <List<String>>[];
    final dirs = ProfileLaunchDirectories(
      root: root,
      paths: paths,
      prefs: MemoryPrefs(),
      start: (exePath, args, {workingDirectory, environment}) async {
        started.add([exePath, ...args]);
        return io.Process.start('cmd.exe', ['/c', 'exit', '0']);
      },
    );
    final process = await dirs.openEmulator('dolphin', exe.path);
    await process.exitCode;
    expect(started.single, [exe.path, '--user=${paths.emulatorDir('dolphin')}']);
  });

  test(
    'mame gets the set name and its folder as -rompath, not the zip path (MAME only looks in its rompath)',
    () async {
      final paths = ProfilePaths(root, 'aaa');
      final exe = io.File(p.join(root.emulators, 'mame', 'mame.exe'))..createSync(recursive: true);
      final started = <List<String>>[];
      final dirs = ProfileLaunchDirectories(
        root: root,
        paths: paths,
        prefs: MemoryPrefs(),
        start: (exePath, args, {workingDirectory, environment}) async {
          started.add(args);
          return io.Process.start('cmd.exe', ['/c', 'exit', '0']);
        },
      );
      await dirs.launchGameWithHandle(game(1, '1943'), r'D:\roms\arcade\1943.zip', 'mame', exe.path);
      // MAME's own roms folder stays on the path, for BIOS sets kept there.
      expect(started.single.sublist(started.single.length - 3), [
        '-rompath',
        '${r'D:\roms\arcade'};${p.join(p.dirname(exe.path), 'roms')}',
        '1943',
      ]);
      expect(started.single, isNot(contains(r'D:\roms\arcade\1943.zip')));
    },
  );

  test("retroarch: Auto Load State is on only for a Resume of the auto slot, and the marker isn't passed on", () async {
    final paths = ProfilePaths(root, 'aaa');
    final exe = io.File(p.join(root.emulators, 'retroarch', 'retroarch.exe'))..createSync(recursive: true);
    final started = <List<String>>[];
    final dirs = ProfileLaunchDirectories(
      root: root,
      paths: paths,
      prefs: MemoryPrefs(),
      start: (exePath, args, {workingDirectory, environment}) async {
        started.add(args);
        return io.Process.start('cmd.exe', ['/c', 'exit', '0']);
      },
    );
    String autoLoad() => RegExp(
      r'^savestate_auto_load = "(\w+)"',
      multiLine: true,
    ).firstMatch(io.File(p.join(paths.emulatorDir('retroarch'), 'retroarch.cfg')).readAsStringSync())!.group(1)!;

    await dirs.launchGameWithHandle(
      game(1, 'G'),
      r'D:\roms\psx\g.chd',
      'retroarch',
      exe.path,
      args: const ['-L', 'core.dll', EmulatorStrategy.resumeAutoStateArg],
    );
    expect(autoLoad(), 'true');
    expect(started.last, isNot(contains(EmulatorStrategy.resumeAutoStateArg)));
    expect(started.last, containsAllInOrder(['-L', 'core.dll', r'D:\roms\psx\g.chd']));

    await dirs.launchGameWithHandle(game(1, 'G'), r'D:\roms\psx\g.chd', 'retroarch', exe.path, args: const ['-e', '2']);
    expect(autoLoad(), 'false', reason: 'a numbered slot loads with -e');
    await dirs.launchGameWithHandle(game(1, 'G'), r'D:\roms\psx\g.chd', 'retroarch', exe.path);
    expect(autoLoad(), 'false', reason: 'a plain Play never starts in the auto state');
    expect(
      io.File(p.join(paths.emulatorDir('retroarch'), 'retroarch.cfg')).readAsStringSync(),
      contains('savestate_auto_save = "true"'),
      reason: 'closing keeps the auto state',
    );
  });

  test('an emulator Gargosy can\'t point at a profile is refused', () async {
    final dirs = ProfileLaunchDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
    expect(
      () => dirs.launchGameWithHandle(game(1, 'G'), 'x', 'not_an_emulator', r'C:\x\x.exe'),
      throwsA(isA<UnsupportedEmulatorException>()),
    );
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

  group("the emulator's own game list shows Gargosy's ROM folders", () {
    test('PCSX2: added to its game folders; one the player added stays', () async {
      final c = ctx('pcsx2', gameFolders: [p.join(root.roms, 'ps2')]);
      await ProfileLaunchConfig.of('pcsx2')!.prepare(c);
      final ini = io.File(p.join(c.data, 'PCSX2', 'inis', 'PCSX2.ini'));
      expect(ini.readAsStringSync(), contains('RecursivePaths = ${p.join(root.roms, 'ps2')}'));
      ini.writeAsStringSync('[UI]\nSettingsVersion = 1\n[GameList]\nRecursivePaths = D:\\Mine\n');
      await ProfileLaunchConfig.of('pcsx2')!.prepare(c);
      final text = ini.readAsStringSync();
      expect(text, contains('RecursivePaths = D:\\Mine'));
      expect(text, contains('RecursivePaths = ${p.join(root.roms, 'ps2')}'));
      await ProfileLaunchConfig.of('pcsx2')!.prepare(c);
      expect(
        RegExp(RegExp.escape(p.join(root.roms, 'ps2'))).allMatches(ini.readAsStringSync()).length,
        1,
        reason: 'never added twice',
      );
    });

    test("DuckStation: in its settings.ini's game folders", () async {
      final c = ctx('duckstation', gameFolders: [p.join(root.roms, 'psx')]);
      await ProfileLaunchConfig.of('duckstation')!.prepare(c);
      expect(
        io.File(p.join(c.exeDir, 'settings.ini')).readAsStringSync(),
        contains('RecursivePaths = ${p.join(root.roms, 'psx')}'),
      );
    });

    test("Dolphin: its ISO folders (searched recursively), unless the player set their own", () async {
      final c = ctx('dolphin', gameFolders: [p.join(root.roms, 'ngc'), p.join(root.roms, 'wii')]);
      await ProfileLaunchConfig.of('dolphin')!.prepare(c);
      final ini = io.File(p.join(c.data, 'Config', 'Dolphin.ini'));
      final text = ini.readAsStringSync();
      expect(text, contains('ISOPaths = 2'));
      expect(text, contains('ISOPath0 = ${p.join(root.roms, 'ngc')}'));
      expect(text, contains('ISOPath1 = ${p.join(root.roms, 'wii')}'));
      expect(text, contains('RecursiveISOPaths = True'));
      ini.writeAsStringSync('[General]\nISOPaths = 1\nISOPath0 = D:\\Mine\n');
      await ProfileLaunchConfig.of('dolphin')!.prepare(c);
      expect(ini.readAsStringSync(), contains('ISOPath0 = D:\\Mine'));
    });

    test("RetroArch: its file browser starts in roms", () async {
      final c = ctx('retroarch');
      await ProfileLaunchConfig.of('retroarch')!.prepare(c);
      expect(
        io.File(p.join(c.data, 'retroarch.cfg')).readAsStringSync(),
        contains('rgui_browser_directory = "${root.roms}"'),
      );
    });
  });

  group("RetroArch: the shared BIOS files reach each core's own folder", () {
    test('PS2 BIOS dumps in bios\\ reach the PS2 core (pcsx2\\bios); others stay at the system root', () async {
      io.File(p.join(root.bios, 'ps2-0230a-20080220.bin')).writeAsBytesSync(List.filled(4 * 1024 * 1024, 7));
      io.File(p.join(root.bios, 'scph1001.bin')).writeAsBytesSync(List.filled(512 * 1024, 1));
      final c = ctx('retroarch');
      await ProfileLaunchConfig.of('retroarch')!.prepare(c);
      final system = p.join(c.data, 'system');
      expect(io.File(p.join(system, 'pcsx2', 'bios', 'ps2-0230a-20080220.bin')).existsSync(), isTrue);
      expect(io.File(p.join(system, 'scph1001.bin')).existsSync(), isTrue);
      expect(io.File(p.join(system, 'pcsx2', 'bios', 'scph1001.bin')).existsSync(), isFalse);
    });

    test("a core's named BIOS (Flycast's dc_boot.bin) reaches its folder (dc)", () async {
      io.File(p.join(root.bios, 'dc_boot.bin')).writeAsBytesSync([1, 2, 3]);
      final c = ctx('retroarch');
      await ProfileLaunchConfig.of('retroarch')!.prepare(c);
      expect(io.File(p.join(c.data, 'system', 'dc', 'dc_boot.bin')).existsSync(), isTrue);
    });

    test('the files are hard links: no extra space for each profile', () async {
      final src = io.File(p.join(root.bios, 'scph1001.bin'))..writeAsBytesSync([1, 2, 3]);
      final c = ctx('retroarch');
      await ProfileLaunchConfig.of('retroarch')!.prepare(c);
      src.writeAsBytesSync([9, 9, 9], mode: io.FileMode.writeOnly);
      expect(io.File(p.join(c.data, 'system', 'scph1001.bin')).readAsBytesSync(), [9, 9, 9]);
    });

    test(
      "a DSi NAND is each profile's own copy: melonDS DS writes into it, never into the shared one (#114)",
      () async {
        final nand = io.File(p.join(root.bios, 'dsi_nand_eur.bin'))..createSync(recursive: true);
        nand.openSync(mode: io.FileMode.write)
          ..truncateSync(251658304)
          ..closeSync();
        final a = ctx('retroarch');
        await ProfileLaunchConfig.of('retroarch')!.prepare(a);
        final copy = io.File(p.join(a.data, 'system', 'dsi_nand_eur.bin'));
        expect(copy.lengthSync(), 251658304);
        copy.openSync(mode: io.FileMode.append)
          ..setPositionSync(0)
          ..writeByteSync(7)
          ..closeSync();
        expect(firstByte(nand), 0);
        // The next launch keeps the profile's copy as it is.
        await ProfileLaunchConfig.of('retroarch')!.prepare(a);
        expect(firstByte(copy), 7);
      },
    );

    test('a NAND Gargosy linked before #114 is replaced by a copy', () async {
      final nand = io.File(p.join(root.bios, 'dsi_nand.bin'))..createSync(recursive: true);
      nand.openSync(mode: io.FileMode.write)
        ..truncateSync(251658304)
        ..closeSync();
      final a = ctx('retroarch');
      // What the old launch left: the shared file's bytes under the same name.
      final old = io.File(p.join(a.data, 'system', 'dsi_nand.bin'))..createSync(recursive: true);
      old.openSync(mode: io.FileMode.write)
        ..truncateSync(251658304)
        ..writeByteSync(5)
        ..closeSync();
      await ProfileLaunchConfig.of('retroarch')!.prepare(a);
      expect(firstByte(old), 0);
      expect(io.File(p.join(a.data, 'system', '.gargosy-own-copies.txt')).readAsStringSync(), 'dsi_nand.bin\n');
    });
  });
}

int firstByte(io.File f) {
  final raf = f.openSync();
  try {
    return raf.readByteSync();
  } finally {
    raf.closeSync();
  }
}
