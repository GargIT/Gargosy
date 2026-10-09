import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/emulators/emulator_library.dart';
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
    expect(list.firstWhere((e) => e.id == 'ryujinx').supported, isFalse);
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
}
