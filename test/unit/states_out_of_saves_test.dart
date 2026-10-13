// Issue #30 (state-sync plan S0.3): save states never ride in game saves,
// whatever the state-sync switch says. An older bundle that carried one
// still restores its real save, and its state only where this PC has none.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_strategy.dart';
import 'package:gargosy/core/save/strategies/dolphin_save_strategy.dart';
import 'package:gargosy/core/save/strategies/ppsspp_save_strategy.dart';
import 'package:gargosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Finds each emulator's exe in [exes] (a portable install), nothing else.
class _Installs extends DirectoryService {
  _Installs(super.prefs, this.exes);
  final Map<String, String> exes;

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async => exes[emulatorId];
}

Uint8List _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late io.Directory tmp;
  late DirectoryService dirs;
  const windows = PlatformInfo('windows');

  void put(String path, List<int> bytes) => io.File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  setUp(() async {
    tmp = io.Directory.systemTemp.createTempSync('gargosy-states-out-');
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dolphin = p.join(tmp.path, 'dolphin');
    final ppsspp = p.join(tmp.path, 'ppsspp');
    final retroarch = p.join(tmp.path, 'retroarch');
    io.Directory(p.join(dolphin, 'User', 'GC', 'USA', 'Card A')).createSync(recursive: true);
    io.Directory(p.join(ppsspp, 'memstick', 'PSP', 'SAVEDATA')).createSync(recursive: true);
    io.Directory(p.join(retroarch, 'saves')).createSync(recursive: true);
    put(p.join(dolphin, 'Dolphin.exe'), const []);
    put(p.join(ppsspp, 'PPSSPPWindows64.exe'), const []);
    put(p.join(retroarch, 'retroarch.exe'), const []);
    io.File(p.join(retroarch, 'retroarch.cfg')).writeAsStringSync(
        'savefile_directory = "${p.join(retroarch, 'saves')}"\n'
        'savestate_directory = "${p.join(retroarch, 'states')}"\n'
        'sort_savefiles_enable = "false"\nsort_savestates_enable = "false"\n');
    dirs = _Installs(prefs, {
      'dolphin': p.join(dolphin, 'Dolphin.exe'),
      'ppsspp': p.join(ppsspp, 'PPSSPPWindows64.exe'),
      'retroarch': p.join(retroarch, 'retroarch.exe'),
    });
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('Dolphin', () {
    const rom = 'Super Mario Sunshine (USA)';
    final game = Game(id: 'gc', name: 'Super Mario Sunshine', fsName: '$rom.iso', platformSlug: 'ngc', fileSize: 0);
    late String romPath;
    late String states;
    setUp(() {
      romPath = p.join(tmp.path, 'roms', '$rom.iso');
      put(romPath, [...'GMSE01'.codeUnits, ...List.filled(64, 0)]);
      put(p.join(tmp.path, 'dolphin', 'User', 'GC', 'USA', 'Card A', '01-GMSE01-Super Mario Sunshine.gci'), List.filled(8256, 1));
      states = p.join(tmp.path, 'dolphin', 'User', 'StateSaves');
      put(p.join(states, 'GMSE01.s01'), List.filled(64, 2));
    });

    test('the save files hold the save, never a state', () async {
      final files = await DolphinSaveStrategy(dirs, platform: windows).getSaveFiles(game, romPath);
      expect(files.map((f) => p.basename(f.path)), ['01-GMSE01-Super Mario Sunshine.gci']);
    });

    test("an older bundle's state goes to StateSaves only when there's none of that name", () async {
      final strategy = DolphinSaveStrategy(dirs, platform: windows);
      final bundle = _zip({'GMSE01.s01': List.filled(64, 9), 'GMSE01.s02': List.filled(64, 8)});
      expect(await strategy.restoreSave(game, romPath, bundle, 'save.zip'), isTrue);
      expect(io.File(p.join(states, 'GMSE01.s01')).readAsBytesSync(), List.filled(64, 2), reason: "this PC's state stays");
      expect(io.File(p.join(states, 'GMSE01.s02')).readAsBytesSync(), List.filled(64, 8), reason: 'a state only the bundle had');
    });
  });

  group('PPSSPP', () {
    final game = Game(id: 'psp', name: 'Patapon', fsName: 'Patapon.iso', platformSlug: 'psp', fileSize: 0, titleId: 'UCUS98711');
    late String states;
    setUp(() {
      states = p.join(tmp.path, 'ppsspp', 'memstick', 'PSP', 'PPSSPP_STATE');
      put(p.join(tmp.path, 'ppsspp', 'memstick', 'PSP', 'SAVEDATA', 'UCUS98711DATA', 'DATA.BIN'), List.filled(64, 1));
      put(p.join(states, 'Patapon.ppst'), List.filled(64, 2));
    });

    test('the save files hold the save folder, never a .ppst', () async {
      final files = await PpssppSaveStrategy(dirs, platform: windows).getSaveFiles(game, 'Patapon.iso');
      expect(files, isNotEmpty);
      expect(files.where((f) => f.path.toLowerCase().endsWith('.ppst')), isEmpty);
    });

    test("an older bundle's state only where this PC has none of that name", () async {
      final strategy = PpssppSaveStrategy(dirs, platform: windows);
      final bundle = _zip({
        'UCUS98711DATA/DATA.BIN': List.filled(64, 7),
        'Patapon.ppst': List.filled(64, 9),
        'Other_1.00_0.ppst': List.filled(64, 8),
      });
      expect(await strategy.restoreSave(game, 'Patapon.iso', bundle, 'save.zip'), isTrue);
      expect(io.File(p.join(tmp.path, 'ppsspp', 'memstick', 'PSP', 'SAVEDATA', 'UCUS98711DATA', 'DATA.BIN')).readAsBytesSync(),
          List.filled(64, 7), reason: 'the real save is restored');
      expect(io.File(p.join(states, 'Patapon.ppst')).readAsBytesSync(), List.filled(64, 2), reason: "this PC's state stays");
      expect(io.File(p.join(states, 'Other_1.00_0.ppst')).existsSync(), isTrue, reason: 'a state only the bundle had');
    });
  });

  group('RetroArch, with state sync off', () {
    final game = Game(id: 'gba', name: 'Pokemon Emerald', fsName: 'Pokemon Emerald.gba', platformSlug: 'gba', fileSize: 0);
    late String romPath;
    late String states;
    setUp(() {
      romPath = p.join(tmp.path, 'roms', 'gba', 'Pokemon Emerald.gba');
      put(romPath, const [1]);
      put(p.join(tmp.path, 'retroarch', 'saves', 'Pokemon Emerald.srm'), List.filled(64, 1));
      states = p.join(tmp.path, 'retroarch', 'states');
      put(p.join(states, 'Pokemon Emerald.state1'), List.filled(64, 2));
    });

    test('the save files hold the .srm, never a state', () async {
      final files = await RetroArchSaveStrategy(dirs, platform: windows).getSaveFiles(game, romPath);
      expect(files.map((f) => p.basename(f.path)), ['Pokemon Emerald.srm']);
    });

    test("an older bundle's state only where this PC has none of that name", () async {
      final strategy = RetroArchSaveStrategy(dirs, platform: windows);
      final bundle = _zip({
        'Pokemon Emerald.srm': List.filled(64, 7),
        'Pokemon Emerald.state1': List.filled(64, 9),
        'Pokemon Emerald.state2': List.filled(64, 8),
      });
      expect(await strategy.restoreSave(game, romPath, bundle, 'save.zip'), isTrue);
      expect(io.File(p.join(tmp.path, 'retroarch', 'saves', 'Pokemon Emerald.srm')).readAsBytesSync(), List.filled(64, 7));
      expect(io.File(p.join(states, 'Pokemon Emerald.state1')).readAsBytesSync(), List.filled(64, 2), reason: "this PC's state stays");
      expect(io.File(p.join(states, 'Pokemon Emerald.state2')).readAsBytesSync(), List.filled(64, 8), reason: 'only the bundle had it');
    });
  });

  group('restoreStateIfMissing', () {
    test("a server name never leaves the folder: '..' and folders are dropped", () async {
      final dir = p.join(tmp.path, 'states');
      await restoreStateIfMissing(dir, r'..\..\..\evil.ppst', const [1]);
      await restoreStateIfMissing(dir, '../../x/also.state1', const [2]);
      expect(io.File(p.join(dir, 'evil.ppst')).existsSync(), isTrue);
      expect(io.File(p.join(dir, 'also.state1')).existsSync(), isTrue);
      expect(io.File(p.join(tmp.path, 'evil.ppst')).existsSync(), isFalse);
    });

    test("it keeps the bundle's time, so an old state doesn't look like the newest", () async {
      final dir = p.join(tmp.path, 'states');
      final then = DateTime(2025, 3, 4, 5, 6, 8);
      await restoreStateIfMissing(dir, 'old.state2', const [1], modified: then);
      expect(io.File(p.join(dir, 'old.state2')).lastModifiedSync(), then);
    });
  });

  test("Dolphin: an old bundle's .sav (StateSaves' undo state) is a state, not a save", () {
    expect(isDolphinStateName('lastState.sav'), isTrue);
    expect(isDolphinStateName('GMSE01.s03'), isTrue);
    expect(isDolphinStateName('StateSaves/GMSE01.s01'), isTrue);
    expect(isDolphinStateName('01-GMSE01-Super Mario Sunshine.gci'), isFalse);
    expect(isDolphinStateName('data.bin'), isFalse);
  });
}
