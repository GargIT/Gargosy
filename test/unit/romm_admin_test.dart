import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_admin.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/library/library_scan.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_dio_adapter.dart';

void main() {
  RommService romm(FakeDioAdapter a) => RommService(
    RomMConfig(baseUrl: 'https://romm.example', username: '', password: '', apiKey: 't'),
    dio: fakeDio(a),
    skipConnectivityCheck: true,
  );

  group('rights', () {
    test("RomM 5.4: an admin may do all; else each by RomM's action keys", () async {
      Future<RommRights> with_(Object body) => romm(FakeDioAdapter((r) => (status: 200, body: body))).rights();
      final admin = await with_({'is_admin': true, 'grants': []});
      expect([admin.scan, admin.upload, admin.match, admin.deleteGames], [true, true, true, true]);
      final editor = await with_({
        'is_admin': false,
        'grants': [
          {'action': 'rom.upload'},
          {'action': 'rom.match'},
        ],
      });
      expect([editor.scan, editor.upload, editor.match, editor.deleteGames], [false, true, true, false]);
      final scanner = await with_({
        'is_admin': false,
        'grants': [
          {'action': 'library.scan'},
        ],
      });
      expect(scanner.scan, isTrue);
      expect((await with_({'is_admin': false, 'grants': []})).any, isFalse);
    });

    test("an older RomM: an admin's or editor's role; RomM out of reach: nothing", () async {
      Future<RommRights> role(String r) => romm(
        FakeDioAdapter(
          (q) => q.path.endsWith('/permissions/me') ? (status: 404, body: {}) : (status: 200, body: {'role': r}),
        ),
      ).rights();
      final editor = await role('editor');
      // An older RomM has no REST scan or chunked upload (5.4): only match and delete.
      expect([editor.scan, editor.upload, editor.match, editor.deleteGames], [false, false, true, true]);
      expect((await role('viewer')).any, isFalse);
      expect((await romm(FakeDioAdapter((q) => (status: -1, body: null))).rights()).any, isFalse);
    });
  });

  group('scan', () {
    test("starts with RomM's type and platforms, and follows the task", () async {
      final a = FakeDioAdapter((r) {
        if (r.method == 'POST') return (status: 202, body: {'task_id': 'job-1', 'status': 'queued'});
        return (
          status: 200,
          body: {
            'task_id': 'job-1',
            'status': 'started',
            'meta': {
              'scan_stats': {'total_roms': 300, 'scanned_roms': 120, 'new_roms': 4, 'identified_roms': 100},
            },
          },
        );
      });
      final service = romm(a);
      expect(await service.startScan(ScanKind.complete, platformIds: [7]), 'job-1');
      expect(a.requests.first.path, '/api/tasks/scan');
      expect(a.requests.first.data, {
        'type': 'complete',
        'platforms': [7],
      });
      expect((await service.startScan(ScanKind.quick)), 'job-1');
      expect(a.requests[1].data, {'type': 'quick'});
      final p = await service.scanProgress('job-1');
      expect(a.requests.last.path, '/api/tasks/job-1');
      expect([p.running, p.scannedGames, p.totalGames, p.newGames], [true, 120, 300, 4]);
    });

    test("RomM's reason when it refuses: a scan running, no worker, a login without the scope", () async {
      Future<Object?> refused(int status, Object body) async {
        try {
          await romm(FakeDioAdapter((r) => (status: status, body: body))).startScan(ScanKind.quick);
        } on RommAdminRefused catch (e) {
          return e.message;
        }
        return null;
      }

      expect(await refused(409, {'detail': 'Scan is already running'}), contains('Scan is already running'));
      expect(await refused(503, {'detail': 'No task worker is listening'}), contains('No task worker'));
      expect(await refused(403, {'detail': 'Forbidden'}), contains('sign in again'));
      expect(await refused(404, {}), contains('5.4'));
    });

    test('the notifier follows a scan until it ends, past a passing 502, then reads the library again', () async {
      var looks = 0;
      final a = FakeDioAdapter((r) {
        if (r.method == 'POST') return (status: 202, body: {'task_id': 'job-2'});
        looks++;
        if (looks == 2) return (status: 502, body: 'Bad Gateway');
        return (status: 200, body: {'status': looks < 3 ? 'started' : 'finished', 'meta': {}});
      });
      var finished = 0;
      final scan = LibraryScanNotifier(romm(a), () => finished++, every: const Duration(milliseconds: 10));
      addTearDown(scan.dispose);
      expect(await scan.start(ScanKind.quick), isNull);
      expect(scan.state.running, isTrue);
      expect(await scan.start(ScanKind.quick), contains('running already'));
      for (var i = 0; i < 50 && finished == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(finished, 1);
      expect(scan.state.running, isFalse);
      expect(scanLine(scan.state), startsWith('Scan done.'));
    });

    test('a task RomM no longer has stops the following, and says so', () async {
      final a = FakeDioAdapter((r) {
        if (r.method == 'POST') return (status: 202, body: {'task_id': 'job-3'});
        return (status: 404, body: {'detail': "Task with ID 'job-3' not found"});
      });
      final scan = LibraryScanNotifier(romm(a), () {}, every: const Duration(milliseconds: 10));
      addTearDown(scan.dispose);
      await scan.start(ScanKind.quick);
      for (var i = 0; i < 50 && scan.state.error == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(scan.state.running, isFalse);
      expect(scan.state.error, contains('not found'));
    });
  });

  group('upload', () {
    late io.Directory dir;
    setUp(() async => dir = await io.Directory.systemTemp.createTemp('upload'));
    tearDown(() => dir.delete(recursive: true));

    String game(int bytes) {
      final f = io.File(p.join(dir.path, 'Café (Europe).zip'))..writeAsBytesSync(List.filled(bytes, 1));
      return f.path;
    }

    test("in RomM's pieces of 10 MB, then complete; the name in the body", () async {
      final a = FakeDioAdapter((r) {
        if (r.path.endsWith('/start')) return (status: 201, body: {'upload_id': 'up-1'});
        if (r.method == 'PUT') return (status: 200, body: {'received': 1, 'total': 3});
        return (status: 201, body: null);
      });
      final sent = <int>[];
      final size = 2 * 10 * 1024 * 1024 + 5;
      await romm(a).uploadGame(4, game(size), onProgress: (done, total) => sent.add(done));
      final start = a.requests.first;
      expect(start.path, '/api/roms/upload/start');
      expect(start.headers['X-Upload-Platform'], '4');
      expect(start.headers['X-Upload-Total-Size'], '$size');
      expect(start.headers['X-Upload-Total-Chunks'], '3');
      expect(start.headers['X-Upload-Filename'], Uri.encodeComponent('Café (Europe).zip'));
      expect(start.data, {'filename': 'Café (Europe).zip'});
      // The login goes with every call (headers beside it, not instead), and
      // the client never sends one of them twice by itself.
      for (final r in a.requests) {
        expect(r.headers['Authorization'], isNotNull, reason: r.path);
        expect(r.extra['no_retry'], isTrue, reason: r.path);
      }
      final puts = a.requests.where((r) => r.method == 'PUT').toList();
      expect([for (final r in puts) r.headers['X-Chunk-Index']], ['0', '1', '2']);
      expect(puts.every((r) => r.path == '/api/roms/upload/up-1'), isTrue);
      expect(a.requests.last.path, '/api/roms/upload/up-1/complete');
      expect(sent.last, size);
    });

    test('a piece RomM refuses cancels the upload there, and says why', () async {
      final a = FakeDioAdapter((r) {
        if (r.path.endsWith('/start')) return (status: 201, body: {'upload_id': 'up-2'});
        if (r.method == 'PUT') return (status: 413, body: {'detail': 'Chunk exceeds maximum allowed size'});
        return (status: 204, body: null);
      });
      await expectLater(
        romm(a).uploadGame(4, game(10)),
        throwsA(isA<RommAdminRefused>().having((e) => e.message, 'message', contains('Chunk exceeds'))),
      );
      expect(a.requests.last.path, '/api/roms/upload/up-2/cancel');
    });

    test('an empty file is refused before RomM hears of it', () async {
      final a = FakeDioAdapter((r) => (status: 201, body: {'upload_id': 'x'}));
      await expectLater(
        romm(a).uploadGame(4, game(0)),
        throwsA(isA<RommAdminRefused>().having((e) => e.message, 'message', contains('is empty'))),
      );
      expect(a.requests, isEmpty);
    });

    test('a file name RomM has already is refused before anything is sent', () async {
      final a = FakeDioAdapter((r) => (status: 400, body: {'detail': 'File Café (Europe).zip already exists'}));
      await expectLater(romm(a).uploadGame(4, game(10)), throwsA(isA<RommAdminRefused>()));
      expect(a.requests.where((r) => r.method == 'PUT'), isEmpty);
    });
  });

  group('fix match', () {
    test("the sources' games, with their ids and the first cover", () async {
      final a = FakeDioAdapter(
        (r) => (
          status: 200,
          body: [
            {
              'name': 'Burnout 3: Takedown',
              'igdb_id': 1234,
              'ss_id': 99,
              'moby_id': null,
              'summary': 'Crash.',
              'igdb_url_cover': 'https://images.igdb.com/t_cover_big/a.jpg',
              'platform_id': 1,
              'is_identified': true,
              'is_unidentified': false,
            },
            {'name': '', 'igdb_id': 1},
            {'name': 'No ids', 'platform_id': 1},
          ],
        ),
      );
      final found = await romm(a).searchMatches('42', term: 'Burnout 3');
      expect(a.requests.single.path, '/api/search/roms');
      expect(a.requests.single.queryParameters, {'rom_id': '42', 'search_by': 'name', 'search_term': 'Burnout 3'});
      expect(found.single.ids, {'igdb_id': '1234', 'ss_id': '99'});
      expect(found.single.sources, ['IGDB', 'ScreenScraper']);
      expect(found.single.coverForGame, 'https://images.igdb.com/t_1080p/a.jpg');
    });

    test(
      "sets every source's id (one the match lacks cleared), the name, summary and cover; not the file name",
      () async {
        final a = FakeDioAdapter((r) => (status: 200, body: {'id': 42}));
        await romm(a).applyMatch(
          '42',
          const MatchCandidate(name: 'Burnout 3', ids: {'igdb_id': '1234'}, summary: 'Crash.', cover: 'c'),
        );
        final r = a.requests.single;
        expect([r.method, r.path], ['PUT', '/api/roms/42']);
        final fields = {for (final f in (r.data as FormData).fields) f.key: f.value};
        expect(fields['igdb_id'], '1234');
        expect(fields['ss_id'], '');
        expect(fields['name'], 'Burnout 3');
        expect(fields['url_cover'], 'c');
        expect(fields.containsKey('fs_name'), isFalse);
      },
    );
  });
}
