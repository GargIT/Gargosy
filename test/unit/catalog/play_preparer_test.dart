import 'dart:io';

// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/core/save/backup_repository.dart';
import 'package:gargosy/core/save/backup_service.dart';
import 'package:gargosy/core/save/catalog/play_preparer.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/core/save/save_sync_service.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Sync extends SaveSyncService {
  _Sync(super.romm, super.dirs, super.registry, super.prefs, this.log, {this.fail = false, this.saveDirs = const {}});
  final List<String> log;
  final bool fail;

  /// Emulator id → its save folder (default: a folder of its own).
  final Map<String, String> saveDirs;

  @override
  Future<String?> saveDirFor(Game game, String romPath, {required String emulatorId, String? coreOverride}) async =>
      saveDirs[emulatorId] ?? '/saves/$emulatorId';
  @override
  Future<void> restoreChosenSave(
    Game game,
    String romPath,
    Map<String, dynamic> save, {
    required String emulatorId,
    String? coreOverride,
  }) async {
    log.add('romm ${save['file_name']} -> $emulatorId/$coreOverride');
    if (fail) throw SaveChoiceException('download failed');
  }

  @override
  Future<void> convertLocalSave(
    Game game,
    String romPath, {
    required String fromEmulatorId,
    String? fromTag,
    required String emulatorId,
    String? coreOverride,
  }) async {
    log.add('convert $fromEmulatorId/$fromTag -> $emulatorId');
  }
}

class _Backups extends BackupService {
  _Backups(this.log, {this.restoreOk = true, this.needsFile = false});
  final List<String> log;
  final bool restoreOk;

  /// Restore fails when the zip isn't there (as the real one does).
  final bool needsFile;
  @override
  Future<BackupResult?> createImmediate(
    Game game,
    String romPath,
    SaveSyncService syncService, {
    String? emulatorId,
    String? coreOverride,
  }) async {
    log.add(coreOverride == null ? 'backup $emulatorId' : 'backup $emulatorId/$coreOverride');
    return (zipPath: '/backups/b.zip', md5: 'm', coreId: null);
  }

  @override
  Future<bool> restore(
    String localZipPath,
    Game game,
    String romPath,
    SaveSyncService syncService, {
    String? emulatorId,
    String? coreOverride,
  }) async {
    log.add(coreOverride == null ? 'restore -> $emulatorId' : 'restore -> $emulatorId/$coreOverride');
    if (needsFile && !File(localZipPath).existsSync()) return false;
    return restoreOk;
  }
}

class _Repo extends BackupRepository {
  _Repo(this.added, {this.existing = const [], this.rotateOut});
  final List<BackupEntry> added;
  final List<BackupEntry> existing;

  /// A zip the 8-backup cap deletes when a backup is added.
  final String? rotateOut;
  @override
  List<BackupEntry> getEntries(String romId) => [...added.reversed, ...existing];
  @override
  Future<void> addEntry(String romId, BackupEntry entry) async {
    added.add(entry);
    if (rotateOut != null && File(rotateOut!).existsSync()) File(rotateOut!).deleteSync();
  }
}

void main() {
  final game = Game(id: '1', name: 'Mario Kart 64', platformSlug: 'n64', fileSize: 0);
  const ares = SaveMaker('ares');
  const mupen = SaveMaker('retroarch', coreId: 'mupen64plus_next');
  late List<String> log;
  late List<BackupEntry> added;

  Future<PlayPreparer> preparer({
    bool fail = false,
    bool restoreOk = true,
    List<BackupEntry> existing = const [],
    Map<String, String> saveDirs = const {},
    String? rotateOut,
    bool needsFile = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dirs = DirectoryService(prefs);
    final registry = StrategyRegistry(dirs, prefs);
    final romm = RommService(RomMConfig(baseUrl: '', username: '', password: ''));
    return PlayPreparer(
      sync: _Sync(romm, dirs, registry, prefs, log, fail: fail, saveDirs: saveDirs),
      backups: _Backups(log, restoreOk: restoreOk, needsFile: needsFile),
      repository: _Repo(added, existing: existing, rotateOut: rotateOut),
    );
  }

  setUp(() {
    log = [];
    added = [];
  });

  test('a RomM save: back up the target\'s save, register it, then download into the target', () async {
    final p = await preparer();
    await p.prepare(
      game,
      '/r/mk.z64',
      SaveEntry(
        source: SaveSource.romm,
        fileName: 'mk.srm',
        savedAt: DateTime(2026),
        maker: mupen,
        rommSave: {'file_name': 'mk.srm'},
      ),
      target: ares,
    );
    expect(log, ['backup ares', 'romm mk.srm -> ares/null']);
    expect(added.single.emulatorId, 'ares');
  });

  test('a pre-play backup is a local safety copy, never queued for upload to RomM', () async {
    final p = await preparer();
    await p.backUp(game, '/r/mk.z64', ares);
    expect(added.single.isSynced, isTrue);
  });

  test('a backup identical to the newest one is not listed again', () async {
    final p = await preparer(
      existing: [BackupEntry(timestamp: DateTime(2026), md5Hash: 'm', localZipPath: '/backups/a.zip')],
    );
    await p.backUp(game, '/r/mk.z64', ares);
    expect(added, isEmpty);
  });

  test('a RetroArch backup records the core, and is taken from that core\'s folder', () async {
    final p = await preparer();
    await p.backUp(game, '/r/mk.z64', const SaveMaker('retroarch', coreId: 'mgba'));
    expect(log, ['backup retroarch/mgba_libretro']);
    expect(added.single.emulatorId, 'retroarch');
    expect(added.single.coreId, 'mgba');
  });

  test('the target\'s own local save: nothing to do, no backup', () async {
    final p = await preparer();
    await p.prepare(
      game,
      '/r/mk.z64',
      SaveEntry(source: SaveSource.local, fileName: 'mk.eeprom', savedAt: DateTime(2026), maker: ares),
      target: ares,
    );
    expect(log, isEmpty);
  });

  test('another emulator\'s local save is converted into the target', () async {
    final p = await preparer();
    await p.prepare(
      game,
      '/r/mk.z64',
      SaveEntry(source: SaveSource.local, fileName: 'mk.srm', savedAt: DateTime(2026), maker: mupen),
      target: ares,
    );
    expect(log, ['backup ares', 'convert retroarch/mupen64plus_next -> ares']);
  });

  String zipFile() {
    final dir = Directory.systemTemp.createTempSync('prep');
    addTearDown(() => dir.deleteSync(recursive: true));
    return (File('${dir.path}/old.zip')..writeAsStringSync('zip')).path;
  }

  test('a backup is restored into the target', () async {
    final p = await preparer(needsFile: true);
    final backup = BackupEntry(timestamp: DateTime(2026), md5Hash: 'x', localZipPath: zipFile(), emulatorId: 'ares');
    await p.prepare(
      game,
      '/r/mk.z64',
      SaveEntry(source: SaveSource.backup, fileName: 'old.zip', savedAt: DateTime(2026), maker: ares, backup: backup),
      target: ares,
    );
    expect(log, ['backup ares', 'restore -> ares']);
  });

  test('RetroArch\'s core goes with the download', () async {
    final p = await preparer();
    await p.prepare(
      game,
      '/r/mk.z64',
      SaveEntry(
        source: SaveSource.romm,
        fileName: 'mk.eeprom',
        savedAt: DateTime(2026),
        maker: ares,
        rommSave: {'file_name': 'mk.eeprom'},
      ),
      target: mupen,
    );
    expect(log.last, 'romm mk.eeprom -> retroarch/mupen64plus_next');
  });

  test('a failure throws, after the backup was registered', () async {
    final p = await preparer(fail: true);
    await expectLater(
      p.prepare(
        game,
        '/r/mk.z64',
        SaveEntry(
          source: SaveSource.romm,
          fileName: 'mk.srm',
          savedAt: DateTime(2026),
          maker: mupen,
          rommSave: {'file_name': 'mk.srm'},
        ),
        target: ares,
      ),
      throwsA(isA<SaveChoiceException>()),
    );
    expect(added, hasLength(1));
  });

  test('nothing is written when the emulator keeps saves in the ROM\'s folder', () async {
    final p = await preparer(saveDirs: {'mgba': '/r'});
    await expectLater(
      p.prepare(
        game,
        '/r/mk.gba',
        SaveEntry(
          source: SaveSource.romm,
          fileName: 'mk.sav',
          savedAt: DateTime(2026),
          rommSave: {'file_name': 'mk.sav'},
        ),
        target: const SaveMaker('mgba'),
      ),
      throwsA(isA<SaveChoiceException>()),
    );
    expect(log, isEmpty);
  });

  test('a RetroArch save of another core is not played in this core', () async {
    final p = await preparer();
    await expectLater(
      p.prepare(
        game,
        '/r/mk.z64',
        SaveEntry(source: SaveSource.local, fileName: 'mk.srm', savedAt: DateTime(2026), maker: mupen),
        target: const SaveMaker('retroarch', coreId: 'parallel_n64'),
      ),
      throwsA(isA<SaveChoiceException>()),
    );
    expect(log, isEmpty);
  });

  test('a backup that can\'t be restored throws', () async {
    final p = await preparer(restoreOk: false);
    final backup = BackupEntry(timestamp: DateTime(2026), md5Hash: 'x', localZipPath: zipFile());
    await expectLater(
      p.prepare(
        game,
        '/r/mk.z64',
        SaveEntry(source: SaveSource.backup, fileName: 'old.zip', savedAt: DateTime(2026), backup: backup),
        target: ares,
      ),
      throwsA(isA<SaveChoiceException>()),
    );
  });

  test("restoring the oldest backup works even when the backup made first rotates it out of the 8", () async {
    final dir = Directory.systemTemp.createTempSync('prep');
    addTearDown(() => dir.deleteSync(recursive: true));
    final oldest = File('${dir.path}/oldest.zip')..writeAsStringSync('zip');
    final p = await preparer(rotateOut: oldest.path, needsFile: true);
    final backup = BackupEntry(timestamp: DateTime(2026), md5Hash: 'x', localZipPath: oldest.path, emulatorId: 'ares');
    await p.prepare(
      game,
      '/r/mk.z64',
      SaveEntry(
        source: SaveSource.backup,
        fileName: 'oldest.zip',
        savedAt: DateTime(2026),
        maker: ares,
        backup: backup,
      ),
      target: ares,
    );
    expect(log, ['backup ares', 'restore -> ares']);
  });

  test("a backup that's gone from this PC says so, and nothing is backed up or changed", () async {
    final p = await preparer();
    final backup = BackupEntry(timestamp: DateTime(2026), md5Hash: 'x', localZipPath: '/nowhere/gone.zip');
    await expectLater(
      p.prepare(
        game,
        '/r/mk.z64',
        SaveEntry(source: SaveSource.backup, fileName: 'gone.zip', savedAt: DateTime(2026), backup: backup),
        target: ares,
      ),
      throwsA(isA<SaveChoiceException>()),
    );
    expect(log, isEmpty);
  });
}
