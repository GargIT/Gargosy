import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late io.Directory source;
  setUp(() async {
    root = await tempAppRoot();
    source = await io.Directory.systemTemp.createTemp('emu_src');
  });
  tearDown(() async {
    await io.Directory(root.root).delete(recursive: true);
    await source.delete(recursive: true);
  });

  EmulatorLibrary library() {
    final dirs = ProfileLaunchDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
    return EmulatorLibrary(root, StrategyRegistry(dirs, MemoryPrefs()).allStrategies);
  }

  test('lists the emulators; the probed ones are supported; none installed yet', () async {
    final list = await library().list();
    final dolphin = list.firstWhere((e) => e.id == 'dolphin');
    expect(dolphin.supported, isTrue);
    expect(dolphin.installedExe, isNull);
    expect(list.firstWhere((e) => e.id == 'ryujinx').supported, isTrue, reason: 'pointed with -r (#9)');
    expect(list.firstWhere((e) => e.id == 'scummvm').supported, isTrue, reason: '--config and --savepath (#11)');
    // Supported exactly when Gargosy can point it at a profile.
    for (final e in list) {
      expect(e.supported, ProfileLaunchConfig.supported.contains(e.id), reason: e.id);
    }
  });

  test('import copies the program and leaves the install\'s own saves and markers behind', () async {
    io.File(p.join(source.path, 'Dolphin-x64', 'Dolphin.exe')).createSync(recursive: true);
    io.File(p.join(source.path, 'Dolphin-x64', 'Sys', 'GC', 'font.bin')).createSync(recursive: true);
    io.File(p.join(source.path, 'Dolphin-x64', 'portable.txt')).createSync();
    io.File(p.join(source.path, 'Dolphin-x64', 'User', 'GC', 'USA', 'Card A', 'save.gci')).createSync(recursive: true);
    await library().importFrom('dolphin', source.path);
    final emu = p.join(root.emulators, 'dolphin');
    expect(io.File(p.join(emu, 'Dolphin-x64', 'Dolphin.exe')).existsSync(), isTrue);
    expect(io.File(p.join(emu, 'Dolphin-x64', 'Sys', 'GC', 'font.bin')).existsSync(), isTrue);
    expect(io.File(p.join(emu, 'Dolphin-x64', 'portable.txt')).existsSync(), isFalse);
    expect(io.Directory(p.join(emu, 'Dolphin-x64', 'User')).existsSync(), isFalse);
    final dolphin = (await library().list()).firstWhere((e) => e.id == 'dolphin');
    expect(dolphin.installedExe, p.join(emu, 'Dolphin-x64', 'Dolphin.exe'));
    expect(io.File(p.join(source.path, 'Dolphin-x64', 'User', 'GC', 'USA', 'Card A', 'save.gci')).existsSync(), isTrue,
        reason: 'the source install is never changed');
  });

  test('importing a folder without the emulator\'s exe is refused', () async {
    io.File(p.join(source.path, 'readme.txt')).createSync();
    expect(() => library().importFrom('dolphin', source.path), throwsA(isA<StateError>()));
    expect(io.Directory(p.join(root.emulators, 'dolphin')).existsSync(), isFalse);
  });

  test('remove deletes only that emulator', () async {
    io.File(p.join(root.emulators, 'dolphin', 'Dolphin.exe')).createSync(recursive: true);
    io.File(p.join(root.emulators, 'pcsx2', 'pcsx2-qt.exe')).createSync(recursive: true);
    await library().remove('dolphin');
    expect(io.Directory(p.join(root.emulators, 'dolphin')).existsSync(), isFalse);
    expect(io.File(p.join(root.emulators, 'pcsx2', 'pcsx2-qt.exe')).existsSync(), isTrue);
  });

  test('an install records where it came from, and an update keeps every profile\'s data', () async {
    final lib = library();
    io.File(p.join(root.emulators, 'duckstation', 'duckstation-qt-x64-ReleaseLTCG.exe')).createSync(recursive: true);
    final mine = io.File(p.join(ProfilePaths(root, 'aaa').emulatorDir('duckstation'), 'memcards', 'shared_card_1.mcd'))
      ..createSync(recursive: true)
      ..writeAsStringSync('card');
    await lib.recordInstall('duckstation', from: 'https://example/duckstation-1.zip');
    var info = (await lib.list()).firstWhere((e) => e.id == 'duckstation');
    expect(info.installedFrom, 'https://example/duckstation-1.zip');
    await lib.recordInstall('duckstation', from: 'https://example/duckstation-2.zip');
    info = (await lib.list()).firstWhere((e) => e.id == 'duckstation');
    expect(info.installedFrom, 'https://example/duckstation-2.zip');
    expect(mine.readAsStringSync(), 'card');
  });

  test('an imported install says so', () async {
    io.File(p.join(source.path, 'Dolphin.exe')).createSync(recursive: true);
    await library().importFrom('dolphin', source.path);
    expect((await library().list()).firstWhere((e) => e.id == 'dolphin').installedFrom, EmulatorLibrary.imported);
  });

  test('a folder without the program (a failed or wrong download) is cleared before a download; a real install is not', () async {
    final junk = io.File(p.join(root.emulators, 'pcsx2', 'pcsx2-qt.pdb'))..createSync(recursive: true);
    await library().clearIfNoProgram('pcsx2');
    expect(junk.existsSync(), isFalse);
    final exe = io.File(p.join(root.emulators, 'dolphin', 'Dolphin.exe'))..createSync(recursive: true);
    await library().clearIfNoProgram('dolphin');
    expect(exe.existsSync(), isTrue);
  });
}
