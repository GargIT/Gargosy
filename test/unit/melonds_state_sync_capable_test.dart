// #65: melonDS's save states through RomM (sync only: no Resume).
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/melonds_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/strategies/melonds_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

Uint8List meln({String magic = 'MELN', int major = 14, int minor = 1}) {
  final b = Uint8List(64);
  final d = ByteData.sublistView(b);
  b.setAll(0, magic.codeUnits);
  d.setUint16(4, major, Endian.little);
  d.setUint16(6, minor, Endian.little);
  d.setUint32(8, 64, Endian.little);
  return b;
}

void main() {
  final game = Game.fromJson({
    ...gameJson(1, 'Mario Kart DS', fsName: 'Mario Kart DS (USA).nds'),
    'platform_slug': 'nds',
  });
  const rom = r'D:\roms\nds\Mario Kart DS (USA).nds';
  final s = MelonDsSaveStrategy(DirectoryService(MemoryPrefs()));

  test("in a profile: the SavestatePath melonDS is told is where states are read", () async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    final paths = ProfilePaths(root, 'aaa');
    final dirs = ProfileSaveDirectories(root: root, paths: paths, prefs: MemoryPrefs());
    EmulatorLayout.of('melonds').ensureFolders(dirs.dataDir('melonds'));
    final c = LaunchContext(
      data: paths.emulatorDir('melonds'),
      exeDir: (io.Directory(p.join(root.emulators, 'melonds'))..createSync(recursive: true)).path,
      bios: root.bios,
      profileId: 'aaa',
      profilesDir: root.profiles,
      guard: PathGuard(root, activeProfileId: 'aaa'),
      roms: root.roms,
    );
    await ProfileLaunchConfig.of('melonds')!.prepare(c);
    final toml = io.File(p.join(c.data, 'portable', 'melonDS.toml')).readAsStringSync();
    final told = RegExp(r'''SavestatePath\s*=\s*['"]([^'"]+)['"]''').firstMatch(toml)!.group(1);
    expect(await MelonDsSaveStrategy(dirs).stateDirectory(game, rom), told);
  });

  test('the matcher: the ROM stem and .ml<N>; nothing else', () async {
    final match = (await s.stateFileMatcher(game, rom))!;
    for (final yes in ['Mario Kart DS (USA).ml1', 'Mario Kart DS (USA).ml8', 'mario kart ds (usa).ml3']) {
      expect(match(yes), isTrue, reason: yes);
    }
    for (final no in [
      'Mario Kart DS (USA).sav',
      'Mario Kart DS (USA).ml10',
      'Mario Kart DS (USA).ml1.bak',
      'Mario Kart DS.ml1',
      r'..\Mario Kart DS (USA).ml1',
    ]) {
      expect(match(no), isFalse, reason: no);
    }
  });

  test('outside a profile the state folder is not known', () {
    expect(() => s.stateDirectory(game, rom), throwsStateError);
  });

  test('slots, the MELN header and its format', () async {
    expect(s.slotOf('Mario Kart DS (USA).ml4'), const NumberedStateSlot(4));
    expect(s.looksLikeValidState(meln()), isTrue);
    expect(s.looksLikeValidState(meln(magic: 'NOPE')), isFalse);
    final tmp = io.Directory.systemTemp.createTempSync('gargosy-melnstate-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final state = io.File(p.join(tmp.path, 'a.ml1'))..writeAsBytesSync(meln(major: 14, minor: 2));
    expect((await s.describeState(state)).formatId, '14.2');
  });

  test('state sync without Resume: melonDS has no option to load a state at start', () {
    final emu = MelonDSStrategy(DirectoryService(MemoryPrefs()));
    expect(emu.supportsStateSync, isTrue);
    expect(emu.supportsStateLoadOnLaunch, isFalse);
  });
}
