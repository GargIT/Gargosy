// #66: ares' save states through RomM.
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/ares_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/strategies/ares_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  final n64 = Game(id: '1', name: 'Mario 64', fileSize: 0, platformSlug: 'n64');
  const rom = r'D:\roms\n64\Super Mario 64 (USA).z64';
  final s = AresSaveStrategy(DirectoryService(MemoryPrefs()));

  test("in a profile: <Paths/Saves>\\<system>, the saves path ares is told, beside the game's saves", () async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    final paths = ProfilePaths(root, 'aaa');
    final dirs = ProfileSaveDirectories(root: root, paths: paths, prefs: MemoryPrefs());
    EmulatorLayout.of('ares').ensureFolders(dirs.dataDir('ares'));
    final args = await ProfileLaunchConfig.of('ares')!.prepare(
      LaunchContext(
        data: paths.emulatorDir('ares'),
        exeDir: (io.Directory(p.join(root.emulators, 'ares'))..createSync(recursive: true)).path,
        bios: root.bios,
        profileId: 'aaa',
        profilesDir: root.profiles,
        guard: PathGuard(root, activeProfileId: 'aaa'),
        roms: root.roms,
      ),
    );
    final told = args.firstWhere((a) => a.startsWith('Paths/Saves=')).substring('Paths/Saves='.length);
    final dir = await AresSaveStrategy(dirs).stateDirectory(n64, rom);
    expect(p.dirname(dir), p.normalize(told));
    expect(p.basename(dir), 'Nintendo 64');
  });

  test('the matcher: the ROM stem and .bs1-.bs9; not the undo files or saves', () async {
    final match = (await s.stateFileMatcher(n64, rom))!;
    for (final yes in ['Super Mario 64 (USA).bs1', 'Super Mario 64 (USA).bs9', 'super mario 64 (usa).bs2']) {
      expect(match(yes), isTrue, reason: yes);
    }
    for (final no in [
      'Super Mario 64 (USA).bs0',
      'Super Mario 64 (USA).bsu',
      'Super Mario 64 (USA).blu',
      'Super Mario 64 (USA).eeprom',
      'Super Mario 64 (USA).bs1.bak',
      'Super Mario 64.bs1',
      r'..\Super Mario 64 (USA).bs1',
    ]) {
      expect(match(no), isFalse, reason: no);
    }
  });

  test('slots are the number in the name', () {
    expect(s.slotOf('Super Mario 64 (USA).bs4'), const NumberedStateSlot(4));
    expect(s.slotOf('Super Mario 64 (USA).bsu'), isA<UnknownStateSlot>());
  });

  test("another slot's state name (#92): .bsN, slots 1 to 9", () {
    expect(s.stateFileForSlot('Super Mario 64 (USA).bs4', 2), 'Super Mario 64 (USA).bs2');
    expect(s.stateFileForSlot('Super Mario 64 (USA).bs4', 0), isNull);
    expect(s.stateFileForSlot('Super Mario 64 (USA).srm', 2), isNull);
  });

  test('Resume: --save-state <slot>', () {
    final emu = AresStrategy(DirectoryService(MemoryPrefs()));
    expect(emu.supportsStateSync, isTrue);
    expect(emu.supportsStateLoadOnLaunch, isTrue);
    expect(emu.stateLoadArgs(r'C:\d\saves\Nintendo 64\Super Mario 64 (USA).bs5'), ['--save-state', '5']);
    expect(emu.canLoadState('Super Mario 64 (USA).bs5'), isTrue);
    expect(emu.canLoadState('Super Mario 64 (USA).bsu'), isFalse);
  });
}
