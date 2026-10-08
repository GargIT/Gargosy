import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

List<int> zipOf(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, content) => a.addFile(ArchiveFile.string(name, content)));
  return ZipEncoder().encode(a);
}

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  DownloadService service(FakeDioAdapter a, {Game? detail}) => DownloadService(
        dio: fakeDio(a),
        auth: () => Options(headers: {'Authorization': 'Bearer t'}),
        files: RomFiles(root),
        guard: PathGuard(root),
        tempDir: p.join(root.appData, 'temp'),
        urlFor: (g) => '/api/roms/${g.id}/content/${g.fsName}',
        detail: (id) async => detail,
      );

  Game withFiles(int id, String fsName, List<String> fullPaths) => Game.fromJson({
        ...gameJson(id, fsName, fsName: fsName, multi: fullPaths.where((f) => !f.contains('/')).length > 1),
        'files': [for (final f in fullPaths) {'file_name': p.posix.basename(f), 'full_path': 'ps2/$fsName/$f'}],
      });

  List<String> romsTree() => [
        for (final e in io.Directory(root.roms).listSync(recursive: true))
          if (e is io.File) p.relative(e.path, from: root.roms),
      ];

  test('a single-file game lands at its path, with progress, and nothing else is left', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: List<int>.filled(1000, 7)));
    final seen = <DownloadPhase>[];
    await service(a).download(game(1, 'A', fsName: 'A.iso'), onProgress: (pr) => seen.add(pr.phase));
    expect(romsTree(), [p.join('ps2', 'A.iso')]);
    expect(io.File(p.join(root.roms, 'ps2', 'A.iso')).lengthSync(), 1000);
    expect(seen.first, DownloadPhase.downloading);
    expect(seen.last, DownloadPhase.done);
    expect(io.Directory(p.join(root.appData, 'temp')).listSync(), isEmpty);
    expect(a.requests.single.headers['Authorization'], 'Bearer t');
  });

  test('a multi-file game is unpacked into its folder and the zip is removed', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: zipOf({'B (Disc 1).chd': 'one', 'B (Disc 2).chd': 'two', 'B.m3u': 'list'})));
    await service(a).download(game(2, 'B', fsName: 'B', multi: true));
    expect(romsTree()..sort(), [p.join('ps2', 'B', 'B (Disc 1).chd'), p.join('ps2', 'B', 'B (Disc 2).chd'), p.join('ps2', 'B', 'B.m3u')]);
    expect(io.Directory(p.join(root.appData, 'temp')).listSync(), isEmpty);
  });

  test('a zip that is the ROM itself is kept as is', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: zipOf({'sf2.bin': 'x'})));
    await service(a).download(game(3, 'sf2', platform: 'arcade', fsName: 'sf2.zip'));
    expect(romsTree(), [p.join('arcade', 'sf2.zip')]);
  });

  test('a zip entry that escapes the game folder is refused and nothing is written', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: zipOf({'ok.chd': 'x', '../../userdata/evil.txt': 'x'})));
    await expectLater(service(a).download(game(4, 'C', fsName: 'C', multi: true)), throwsA(isA<PathGuardException>()));
    expect(romsTree(), isEmpty);
    expect(io.File(p.join(root.userdata, 'evil.txt')).existsSync(), isFalse);
    expect(io.Directory(p.join(root.appData, 'temp')).listSync(), isEmpty);
  });

  test('a failed download leaves nothing in roms', () async {
    final a = FakeDioAdapter((r) => (status: 500, body: {'detail': 'boom'}));
    await expectLater(service(a).download(game(5, 'D', fsName: 'D.iso')), throwsA(isA<DioException>()));
    expect(romsTree(), isEmpty);
    expect(io.Directory(p.join(root.appData, 'temp')).listSync(), isEmpty);
  });

  test('downloading again replaces the old copy', () async {
    io.File(p.join(root.roms, 'ps2', 'A.iso'))..createSync(recursive: true)..writeAsStringSync('old');
    final a = FakeDioAdapter((r) => (status: 200, body: List<int>.filled(10, 1)));
    await service(a).download(game(1, 'A', fsName: 'A.iso'));
    expect(io.File(p.join(root.roms, 'ps2', 'A.iso')).lengthSync(), 10);
  });

  test('one file inside its own folder is stored in that folder, under its own name', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: List<int>.filled(10, 3)));
    await service(a).download(withFiles(6, 'Game', ['Game.chd']));
    expect(romsTree(), [p.join('ps2', 'Game', 'Game.chd')]);
  });

  test('one top-level file plus files in a subfolder come as a zip and are unpacked', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: zipOf({'Game.iso': 'x', 'extras/manual.pdf': 'y'})));
    await service(a).download(withFiles(7, 'Game', ['Game.iso', 'extras/manual.pdf']));
    expect(romsTree()..sort(), [p.join('ps2', 'Game', 'Game.iso'), p.join('ps2', 'Game', 'extras', 'manual.pdf')]);
  });

  test('a game from a list page (no file list) is looked up first', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: List<int>.filled(10, 3)));
    final listGame = game(8, 'Game', fsName: 'Game');
    await service(a, detail: withFiles(8, 'Game', ['Game.chd'])).download(listGame);
    expect(romsTree(), [p.join('ps2', 'Game', 'Game.chd')]);
  });
}
