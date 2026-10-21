import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:dio/dio.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/save/catalog/play_preparer.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/core/save/save_strategy.dart';
import 'package:gargosy/core/save/save_sync_service.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:gargosy/play/save_deletion.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// A strategy whose save is the files given, in [dir].
class _Files extends SaveStrategy {
  _Files(this.dir, this.files, {this.shared = false});
  final String dir;
  final List<File> files;
  final bool shared;

  @override
  String get strategyId => 'files';
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => dir;
  @override
  Future<List<File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async => files;
  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => false;
  @override
  Future<bool> pullMustFinishBeforeLaunch(Game game, String romPath) async => shared;
}

class _Sync extends SaveSyncService {
  _Sync(super.romm, super.dirs, super.registry, super.prefs, this.strategy, this.log)
    : super(wrapSaves: (id, base) => base);
  final SaveStrategy strategy;
  final List<String> log;

  @override
  Future<T?> withStrategy<T>(
    Game game,
    Future<T> Function(SaveStrategy strategy) body, {
    String? emulatorId,
    String? coreOverride,
  }) async {
    log.add('lock $emulatorId/$coreOverride');
    return body(strategy);
  }
}

class _Preparer extends Fake implements PlayPreparer {
  _Preparer(this.log);
  final List<String> log;
  @override
  Future<void> backUp(Game game, String romPath, SaveMaker who) async => log.add('backup $who');
}

void main() {
  late Directory tmp;
  late AppRoot root;
  late PathGuard guard;
  late String saves;
  late List<String> log;
  final game = Game(id: '1', name: 'Metroid Fusion', platformSlug: 'gba', fileSize: 0);
  const mgba = SaveMaker('mgba');
  final save = SaveEntry(
    source: SaveSource.local,
    fileName: 'Metroid Fusion.sav',
    savedAt: DateTime(2026),
    maker: mgba,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('save_deletion');
    root = AppRoot(tmp.path);
    guard = PathGuard(root, activeProfileId: 'p1');
    saves = p.join(root.profiles, 'p1', 'emulators', 'mgba', 'saves');
    Directory(saves).createSync(recursive: true);
    log = [];
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> delete(SaveStrategy strategy) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final dirs = DirectoryService(prefs);
    final sync = _Sync(
      RommService(RomMConfig(baseUrl: '', username: '', password: '')),
      dirs,
      StrategyRegistry(dirs, prefs),
      prefs,
      strategy,
      log,
    );
    await deleteLocalSave(game, '/roms/gba/mf.gba', save, sync: sync, preparer: _Preparer(log), guard: guard);
  }

  File file(String dir, String name) => File(p.join(dir, name))..writeAsStringSync('save');

  test("this PC's save: backed up first, then its files deleted, under the save lock", () async {
    final sav = file(saves, 'Metroid Fusion.sav');
    final other = file(saves, 'Zelda.sav');
    await delete(_Files(saves, [sav]));
    expect(sav.existsSync(), isFalse);
    expect(other.existsSync(), isTrue, reason: "another game's save stays");
    expect(log, ['lock mgba/null', 'backup mgba', 'lock mgba/null']);
  });

  test('a save on a card other games share is refused, and nothing is backed up or deleted', () async {
    final card = file(saves, 'Mcd001.ps2');
    await expectLater(delete(_Files(saves, [card], shared: true)), throwsA(isA<SaveSyncNotPossibleException>()));
    expect(card.existsSync(), isTrue);
    expect(log, isNot(contains('backup mgba')));
  });

  test("a file outside the emulator's save folder is refused", () async {
    final elsewhere = file(p.join(root.profiles, 'p1'), 'x.sav');
    await expectLater(delete(_Files(saves, [elsewhere])), throwsA(isA<SaveSyncNotPossibleException>()));
    expect(elsewhere.existsSync(), isTrue);
  });

  test("a save folder outside Gargosy's writable folders is refused by the guard, before any backup", () async {
    final outside = Directory(p.join(tmp.path, 'elsewhere'))..createSync();
    final sav = file(outside.path, 'Metroid Fusion.sav');
    await expectLater(delete(_Files(outside.path, [sav])), throwsA(isA<PathGuardException>()));
    expect(sav.existsSync(), isTrue);
    expect(log, isNot(contains('backup mgba')));
  });

  test('no save on this PC: refused with why', () async {
    await expectLater(
      delete(_Files(saves, [File(p.join(saves, 'gone.sav'))])),
      throwsA(isA<SaveSyncNotPossibleException>().having((e) => e.message, 'message', contains('no save'))),
    );
  });

  group('a state of yours (#94)', () {
    late ResumeService resume;
    late DioAdapter adapter;
    late RommService romm;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      resume = ResumeService(
        emulatorsFor: (_) => const [],
        resolveSaveStrategy: (g, {emulatorId}) => null,
        prefs: prefs,
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://romm.example.com'));
      adapter = DioAdapter(dio: dio);
      romm = RommService(
        RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'key'),
        dio: dio,
        skipConnectivityCheck: true,
      );
    });

    ResumeEntry entry({File? local, int? remoteId, SaveOwner? owner}) => ResumeEntry(
      emulatorId: 'mgba',
      emulatorName: 'mGBA',
      fileName: 'Metroid Fusion.ss1',
      slot: const NumberedStateSlot(1),
      savedAt: DateTime(2026),
      where: local == null ? ResumeWhere.romm : (remoteId == null ? ResumeWhere.thisPc : ResumeWhere.both),
      localFile: local,
      remoteId: remoteId,
      owner: owner,
    );

    test('on this PC and RomM: the file goes, and RomM is asked to delete it', () async {
      final state = file(saves, 'Metroid Fusion.ss1');
      adapter.onPost(
        '/api/states/delete',
        (server) => server.reply(200, {}),
        data: {
          'states': [8],
        },
      );
      expect(
        await deleteOwnState(
          game,
          entry(local: state, remoteId: 8),
          resume: resume,
          guard: guard,
          romm: romm,
        ),
        isNull,
      );
      expect(state.existsSync(), isFalse);
    });

    test("RomM refusing: it's deleted on this PC, and it says RomM's copy stayed", () async {
      final state = file(saves, 'Metroid Fusion.ss1');
      adapter.onPost(
        '/api/states/delete',
        (server) => server.reply(500, {}),
        data: {
          'states': [8],
        },
      );
      final partly = await deleteOwnState(
        game,
        entry(local: state, remoteId: 8),
        resume: resume,
        guard: guard,
        romm: romm,
      );
      expect(partly, contains("RomM can't be reached"));
      expect(state.existsSync(), isFalse);
    });

    test("another player's state is never deleted", () async {
      await expectLater(
        deleteOwnState(
          game,
          entry(remoteId: 8, owner: const SaveOwner(userId: 7, username: 'maja')),
          resume: resume,
          guard: guard,
          romm: romm,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
