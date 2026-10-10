import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_strategy.dart';
import 'package:gargosy/core/save/save_sync_service.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'save_sync_regression_test.mocks.dart';

/// A strategy that hands over one unit file and restores units itself, as
/// sigil's does.
class _UnitStrategy extends SaveStrategy {
  _UnitStrategy(this.unit);
  final File unit;
  int uploads = 0;
  final restored = <(String, Uint8List)>[];
  final chosen = <bool>[];

  @override
  String get strategyId => 'mgba';
  @override
  bool get supportsSaveSync => true;
  @override
  bool get shouldZip => false;
  @override
  String uploadSlotFor(Game game) => 'autosave';
  @override
  bool restoresUnitsItselfFor(Game game) => true;
  @override
  Future<void> afterUpload(Game game, String romPath) async => uploads++;
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => unit.parent.path;
  @override
  Future<List<File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async => [unit];
  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    restored.add((filename, data));
    chosen.add(SaveStrategy.isChosenRestore);
    return true;
  }
}

void main() {
  late MockRommService romm;
  late MockDirectoryService dirs;
  late MockStrategyRegistry registry;
  late Directory tmp;
  late _UnitStrategy unit;
  late SaveSyncService service;
  final game = Game(id: '42', name: 'Tetris', platformSlug: 'gb', fileSize: 0);

  void answerUpload(bool ok) => when(
    romm.uploadSave(
      any,
      any,
      emulator: anyNamed('emulator'),
      slot: anyNamed('slot'),
      deviceId: anyNamed('deviceId'),
      autocleanup: anyNamed('autocleanup'),
      autocleanupLimit: anyNamed('autocleanupLimit'),
      overwrite: anyNamed('overwrite'),
      screenshotFile: anyNamed('screenshotFile'),
      overrideFilename: anyNamed('overrideFilename'),
    ),
  ).thenAnswer((_) async => (ok: ok, conflict: null, saved: null));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    romm = MockRommService();
    dirs = MockDirectoryService();
    registry = MockStrategyRegistry();
    tmp = await Directory.systemTemp.createTemp('sigil_hooks');
    unit = _UnitStrategy(File(p.join(tmp.path, 'Tetris (World).srm'))..writeAsBytesSync(List.filled(32768, 7)));
    when(registry.getPreferredEmulatorId(any)).thenReturn(null);
    when(registry.getStrategyForSlug(any)).thenReturn(null);
    when(registry.getGameEmulatorPreference(any)).thenReturn(null);
    when(registry.getGameCorePreference(any)).thenReturn(null);
    when(dirs.getEmulatorDirectory('temp')).thenAnswer((_) async => tmp.path);
    when(romm.getLatestSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => null);
    when(romm.fetchCapabilities()).thenAnswer((_) async => RommCapabilities.unknown());
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    service = SaveSyncService(
      romm,
      dirs,
      registry,
      prefs,
      wrapSaves: (emulatorId, base) => emulatorId == 'mgba' ? unit : base,
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test("an upload goes to the strategy's slot, and afterUpload runs once it succeeded", () async {
    answerUpload(true);
    await service.pushSaves(game, p.join(tmp.path, 'Tetris (World).gb'), emulatorId: 'mgba');
    final slot = verify(
      romm.uploadSave(
        '42',
        any,
        emulator: anyNamed('emulator'),
        slot: captureAnyNamed('slot'),
        deviceId: anyNamed('deviceId'),
        autocleanup: anyNamed('autocleanup'),
        autocleanupLimit: anyNamed('autocleanupLimit'),
        overwrite: anyNamed('overwrite'),
        screenshotFile: anyNamed('screenshotFile'),
        overrideFilename: anyNamed('overrideFilename'),
      ),
    ).captured.single;
    expect(slot, 'autosave');
    expect(unit.uploads, 1);
  });

  test('a failed upload leaves afterUpload uncalled (the state stays as it was)', () async {
    answerUpload(false);
    await service.pushSaves(game, p.join(tmp.path, 'Tetris (World).gb'), emulatorId: 'mgba');
    expect(unit.uploads, 0);
  });

  group('on RomM 4.9+ (device sync)', () {
    setUp(() => when(romm.fetchCapabilities()).thenAnswer((_) async => RommCapabilities(version: '5.3.1')));
    String capturedSlot() =>
        verify(
              romm.uploadSave(
                '42',
                any,
                emulator: anyNamed('emulator'),
                slot: captureAnyNamed('slot'),
                deviceId: anyNamed('deviceId'),
                autocleanup: anyNamed('autocleanup'),
                autocleanupLimit: anyNamed('autocleanupLimit'),
                overwrite: anyNamed('overwrite'),
                screenshotFile: anyNamed('screenshotFile'),
                overrideFilename: anyNamed('overrideFilename'),
              ),
            ).captured.single
            as String;

    test('the unit goes to autosave and the state is committed once', () async {
      answerUpload(true);
      await service.pushSaves(game, p.join(tmp.path, 'Tetris (World).gb'), emulatorId: 'mgba');
      expect(capturedSlot(), 'autosave');
      expect(unit.uploads, 1);
    });

    test('a failed upload commits nothing', () async {
      answerUpload(false);
      await service.pushSaves(game, p.join(tmp.path, 'Tetris (World).gb'), emulatorId: 'mgba');
      expect(unit.uploads, 0);
    });

    test('an unchanged save is not uploaded again, and the state is not rewritten', () async {
      answerUpload(true);
      await service.pushSaves(game, p.join(tmp.path, 'Tetris (World).gb'), emulatorId: 'mgba');
      await service.pushSaves(game, p.join(tmp.path, 'Tetris (World).gb'), emulatorId: 'mgba');
      expect(capturedSlot(), 'autosave'); // one upload only
      expect(unit.uploads, 1);
    });
  });

  test('a download goes to a unit-restoring strategy as it came, without conversion', () async {
    final bytes = Uint8List.fromList(List.filled(32768, 9));
    when(romm.downloadSave(any, deviceId: anyNamed('deviceId'))).thenAnswer((_) async => bytes);
    await service.restoreChosenSave(game, p.join(tmp.path, 'Tetris (World).gb'), {
      'id': 5,
      'file_name': 'Tetris (World).srm',
      'download_path': '/api/saves/5/content',
      'emulator': 'gambatte',
    }, emulatorId: 'mgba');
    expect(unit.restored.single.$1, 'Tetris (World).srm');
    expect(unit.restored.single.$2, bytes);
    expect(unit.chosen, [true], reason: 'a restore picked on the play screen may replace a local change');
  });
}
