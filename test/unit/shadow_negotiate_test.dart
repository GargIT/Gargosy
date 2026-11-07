import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/game_launch_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/romm/sync_negotiate.dart';
import 'package:gargosy/core/save/strategy_lock.dart';
import 'package:gargosy/core/save/upload_stats.dart';
import 'package:gargosy/play/shadow_negotiate.dart';
import 'package:path/path.dart' as p;

Game _game() => Game(id: '7', name: 'Game', platformSlug: 'gba', fileSize: 1);

NegotiateSave _save() => NegotiateSave(
  romId: '7',
  fileName: 'Game.sav',
  slot: 'gargosy',
  emulator: 'mgba',
  contentHash: 'abc',
  updatedAt: DateTime.utc(2026, 11, 7),
  sizeBytes: 150,
);

/// Shadow negotiate (#294): RomM's negotiate asked, logged beside what
/// Gargosy did, never acted on.
void main() {
  group('ShadowNegotiate', () {
    late List<({List<NegotiateSave> saves, List<String> romIds, List<String> emulators})> asked;
    late List<int> completed;
    late Future<NegotiateResult?> Function() answer;

    ShadowNegotiate make() => ShadowNegotiate(
      ask: ({required saves, required romIds, required emulators}) {
        asked.add((saves: saves, romIds: romIds, emulators: emulators));
        return answer();
      },
      complete: (id) async => completed.add(id),
    );

    setUp(() {
      asked = [];
      completed = [];
      answer = () async => const NegotiateResult(5, [SyncOperation(action: 'no_op', saveId: 9)]);
    });

    test("asks for the game only, with this PC's save and its emulator, then closes the session", () async {
      final look = make().look('launch', _game(), (emulator: 'mgba', slot: 'gargosy', save: _save()))!;
      await look.told("kept this PC's save");
      expect(asked.single.romIds, ['7']);
      expect(asked.single.emulators, ['mgba']);
      expect(asked.single.saves.single.fileName, 'Game.sav');
      expect(completed, [5]);
    });

    test('without a save on this PC it still asks, with none', () async {
      final look = make().look('launch', _game(), (emulator: 'mgba', slot: 'gargosy', save: null))!;
      await look.told('x');
      expect(asked.single.saves, isEmpty);
    });

    test('nothing to describe is not asked', () {
      expect(make().look('launch', _game(), null), isNull);
    });

    test("a RomM without negotiate isn't asked again", () async {
      answer = () async => null;
      final shadow = make();
      await shadow.look('launch', _game(), (emulator: 'mgba', slot: 'gargosy', save: null))!.told('x');
      expect(shadow.look('push', _game(), (emulator: 'mgba', slot: 'gargosy', save: null)), isNull);
      expect(completed, isEmpty);
    });

    test('a RomM that fails or is slow changes nothing and throws nothing', () async {
      answer = () async => throw StateError('down');
      await make().look('launch', _game(), (emulator: 'mgba', slot: 'gargosy', save: null))!.told('x');
      expect(completed, isEmpty);
    });

    test('only the first word on what Gargosy did counts', () async {
      final look = make().look('push', _game(), (emulator: 'mgba', slot: 'gargosy', save: null))!;
      await look.told('pushed');
      await look.told('the push stopped with an error');
      expect(completed, [5]);
    });

    test("an answer later than the wait isn't logged, but its session is still completed", () async {
      final late = Completer<NegotiateResult?>();
      answer = () => late.future;
      final shadow = ShadowNegotiate(
        ask: ({required saves, required romIds, required emulators}) => answer(),
        complete: (id) async => completed.add(id),
        timeout: const Duration(milliseconds: 10),
      );
      await shadow.look('launch', _game(), (emulator: 'mgba', slot: 'gargosy', save: null))!.told('x');
      expect(completed, isEmpty);
      late.complete(const NegotiateResult(8, []));
      await Future<void>.delayed(Duration.zero);
      expect(completed, [8]);
    });

    test("what Gargosy did is said in words", () {
      expect(describePull(true), contains('pulled'));
      expect(describePull(false), contains("didn't pull"));
      expect(describePull(null, 'x'), contains('failed'));
      expect(describePush(null), 'no session');
      expect(describePush(LaunchResult(syncOk: true, saveUnchanged: true)), contains('nothing to push'));
    });
  });

  group("RomM's negotiate calls", () {
    late RommService romm;
    final sent = <RequestOptions>[];
    var status = 200;
    Object? body;

    setUp(() {
      sent.clear();
      status = 200;
      body = null;
      final dio = Dio(BaseOptions(baseUrl: 'https://romm.example.com'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            sent.add(o);
            final response = Response(requestOptions: o, statusCode: status, data: body);
            if (o.validateStatus(status)) {
              h.resolve(response);
            } else {
              h.reject(DioException.badResponse(statusCode: status, requestOptions: o, response: response));
            }
          },
        ),
      );
      romm = RommService(
        RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
        dio: dio,
      );
    });

    test('negotiate sends the device, the save, the scope and its options, and reads the operations', () async {
      body = {
        'session_id': 12,
        'operations': [
          {'action': 'download', 'save_id': 3, 'slot': 'gargosy', 'reason': 'Server save is newer'},
          'not an operation',
        ],
      };
      final r = await romm.negotiateSync(
        deviceId: 'dev',
        saves: [_save()],
        romIds: ['7'],
        restoreUnlisted: true,
        emulators: ['mgba'],
      );
      final data = sent.single.data as Map;
      expect(sent.single.path, '/api/sync/negotiate');
      expect(data['device_id'], 'dev');
      expect(data['rom_ids'], [7]);
      expect(data['restore_unlisted'], isTrue);
      expect(data['emulators'], ['mgba']);
      expect((data['saves'] as List).single['content_hash'], 'abc');
      expect(r!.sessionId, 12);
      expect(r.operations.single.toString(), 'download save 3 [gargosy]: Server save is newer');
    });

    test('a RomM without negotiate answers null; a refusal throws', () async {
      status = 404;
      expect(await romm.negotiateSync(deviceId: 'd', saves: [], romIds: ['7']), isNull);
      status = 400;
      await expectLater(romm.negotiateSync(deviceId: 'd', saves: [], romIds: ['7']), throwsA(anything));
    });

    test('completing a session never throws', () async {
      await romm.completeSync(12);
      expect(sent.single.path, '/api/sync/sessions/12/complete');
      status = 500;
      await romm.completeSync(12);
    });
  });

  test('a folder save counts every file inside, its newest change and its size', () async {
    final dir = await Directory.systemTemp.createTemp('upload_stats');
    addTearDown(() => dir.delete(recursive: true));
    final card = Directory(p.join(dir.path, 'card'))..createSync();
    File(p.join(card.path, 'a.bin')).writeAsBytesSync(List.filled(10, 1));
    final b = File(p.join(card.path, 'b.bin'))..writeAsBytesSync(List.filled(5, 1));
    b.setLastModifiedSync(DateTime(2030));
    final single = File(p.join(dir.path, 'x.sav'))..writeAsBytesSync(List.filled(3, 1));
    final stats = (await uploadStats([File(card.path), single]))!;
    expect(stats.bytes, 18);
    expect(stats.newest, DateTime(2030));
    expect(await uploadStats([File(p.join(dir.path, 'gone'))]), isNull);
  });

  test('the save lock says when an operation runs or waits', () async {
    final lock = StrategyLock();
    expect(lock.busy, isFalse);
    final gate = Completer<void>();
    final first = lock.run(() => gate.future);
    final second = lock.run(() async {});
    expect(lock.busy, isTrue);
    gate.complete();
    await first;
    await second;
    expect(lock.busy, isFalse);
  });
}
