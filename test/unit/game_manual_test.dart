import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/library/game_manual.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4\n…'));

Game withManual(int id, String? path) => Game.fromJson({...gameJson(id, 'G$id'), 'path_manual': path});

void main() {
  late AppRoot root;
  late PathGuard guard;
  late String dir;

  setUp(() async {
    root = await tempAppRoot();
    guard = PathGuard(root, activeProfileId: 'aaa');
    dir = p.join(ProfilePaths(root, 'aaa').cache, 'manuals');
  });
  tearDown(() => io.Directory(root.root).deleteSync(recursive: true));

  test("RomM's path_manual, kept in the snapshot; only a PDF is a manual Gargosy shows", () {
    final game = withManual(1, 'roms/4/1/manual/1.pdf');
    expect(game.pathManual, 'roms/4/1/manual/1.pdf');
    expect(game.hasManual, isTrue);
    expect(Game.fromJson(game.toJson()).pathManual, 'roms/4/1/manual/1.pdf');
    expect(withManual(2, '').pathManual, isNull);
    expect(withManual(3, null).hasManual, isFalse);
    expect(withManual(4, 'roms/4/4/manual/4.md').hasManual, isFalse);
  });

  test("fetched once from RomM into the profile's cache, then read from there", () async {
    final asked = <String>[];
    final manuals = GameManuals(
      guard: guard,
      dir: dir,
      download: (path) async {
        asked.add(path);
        return pdf;
      },
    );
    final game = withManual(7, 'roms/4/7/manual/7.pdf');
    expect(manuals.isKept(game), isFalse);
    final file = await manuals.open(game);
    expect(file, p.join(dir, '7.pdf'));
    expect(io.File(file).readAsBytesSync(), pdf);
    expect(await manuals.open(game), file);
    expect(asked, ['roms/4/7/manual/7.pdf']);
    // Offline, the kept copy still opens.
    expect(await GameManuals(guard: guard, dir: dir).open(game), file);
  });

  test("what isn't a PDF (a login page) is never kept; why is said", () async {
    final page = GameManuals(guard: guard, dir: dir, download: (_) async => Uint8List.fromList(utf8.encode('<html>')));
    final game = withManual(8, 'roms/4/8/manual/8.pdf');
    await expectLater(page.open(game), throwsA(isA<ManualUnavailable>()));
    expect(page.isKept(game), isFalse);
    final failing = GameManuals(guard: guard, dir: dir, download: (_) async => throw StateError('404'));
    await expectLater(failing.open(game), throwsA(isA<ManualUnavailable>()));
    await expectLater(GameManuals(guard: guard, dir: dir).open(game), throwsA(isA<ManualUnavailable>()));
    await expectLater(GameManuals(guard: guard, dir: dir).open(withManual(9, null)), throwsA(isA<ManualUnavailable>()));
    // keep() with the download only logs.
    await failing.keep(game);
    expect(failing.isKept(game), isFalse);
  });

  test('written only through the guard: never outside the profile', () async {
    final other = p.join(ProfilePaths(root, 'bbb').cache, 'manuals');
    final manuals = GameManuals(guard: guard, dir: other, download: (_) async => pdf);
    await expectLater(manuals.open(withManual(1, 'roms/1.pdf')), throwsA(isA<PathGuardException>()));
    expect(io.Directory(other).existsSync(), isFalse);
  });

  test("RomM's copy is asked for under its resources, with the token", () async {
    final server = FakeDioAdapter((r) => (status: 200, body: pdf.toList()));
    final romm = RommService(RomMConfig(baseUrl: 'http://romm', username: '', password: '', token: 'tok'))
      ..dio.httpClientAdapter = server;
    expect(await romm.downloadManual('roms/4/7/manual/7.pdf'), pdf);
    expect(server.requests.single.uri.path, '/assets/romm/resources/roms/4/7/manual/7.pdf');
    expect('${server.requests.single.headers['Authorization']}', contains('tok'));
    final missing = RommService(RomMConfig(baseUrl: 'http://romm', username: '', password: ''))
      ..dio.httpClientAdapter = FakeDioAdapter((r) => (status: 404, body: const <int>[]));
    await expectLater(missing.downloadManual('/roms/x.pdf'), throwsA(anything));
  });

  test('a PDF by its first bytes', () {
    expect(isPdf(pdf), isTrue);
    expect(isPdf(utf8.encode('%PDF')), isFalse);
    expect(isPdf(utf8.encode('<!doctype html>')), isFalse);
  });
}
