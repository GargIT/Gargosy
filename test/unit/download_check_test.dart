import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/download_check.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

List<int> zipOf(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((name, bytes) => a.addFile(ArchiveFile.bytes(name, bytes)));
  return ZipEncoder().encode(a);
}

String sha1Of(List<int> b) => '${sha1.convert(b)}';

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  final good = List<int>.generate(3000, (i) => i % 251);

  DownloadService service(List<int> body, {bool check = true}) => DownloadService(
    dio: fakeDio(FakeDioAdapter((r) => (status: 200, body: body))),
    auth: Options.new,
    files: RomFiles(root),
    guard: PathGuard(root),
    tempDir: p.join(root.appData, 'temp'),
    urlFor: (g) => '/api/roms/${g.id}/content/${g.fsName}',
    checkHashes: () => check,
  );

  /// A one-file game RomM describes with [hashes] (`sha1_hash` …).
  Game single(Map<String, String> hashes) => Game.fromJson({
    ...gameJson(1, 'A', fsName: 'A.iso'),
    'files': [
      {'file_name': 'A.iso', ...hashes},
    ],
  });

  String rom() => p.join(root.roms, 'ps2', 'A.iso');

  group('fileMatches', () {
    late String path;
    setUp(() {
      path = p.join(root.appData, 'f.bin');
      io.File(path).writeAsBytesSync(good);
    });

    test('SHA-1 first, else MD5, else CRC32; none: nothing to check', () async {
      expect(await fileMatches(path, RomFileHashes('f', sha1: sha1Of(good))), isTrue);
      expect(await fileMatches(path, RomFileHashes('f', sha1: sha1Of([1]), md5: '${md5.convert(good)}')), isFalse);
      expect(await fileMatches(path, RomFileHashes('f', md5: '${md5.convert(good)}')), isTrue);
      final crc = getCrc32(good).toRadixString(16);
      expect(await fileMatches(path, RomFileHashes('f', crc: crc)), isTrue);
      expect(await fileMatches(path, const RomFileHashes('f', crc: '00000001')), isFalse);
      expect(await fileMatches(path, const RomFileHashes('f')), isTrue);
    });
  });

  test("a file with RomM's hash lands, after Checking…", () async {
    final seen = <DownloadPhase>[];
    await service(good).download(single({'sha1_hash': sha1Of(good)}), onProgress: (pr) => seen.add(pr.phase));
    expect(io.File(rom()).existsSync(), isTrue);
    expect(seen, contains(DownloadPhase.checking));
  });

  test('a damaged file never reaches roms, and temp is left empty', () async {
    final damaged = [...good]..[5] = 0;
    await expectLater(
      service(damaged).download(single({'sha1_hash': sha1Of(good)})),
      throwsA(isA<DownloadDamaged>().having((e) => e.files, 'files', ['A.iso'])),
    );
    expect(io.File(rom()).existsSync(), isFalse);
    expect(io.Directory(p.join(root.appData, 'temp')).listSync(), isEmpty);
  });

  test('Check downloads off, or no hash from RomM: it lands unchecked', () async {
    final damaged = [...good]..[5] = 0;
    await service(damaged, check: false).download(single({'sha1_hash': sha1Of(good)}));
    expect(io.File(rom()).existsSync(), isTrue);
    io.File(rom()).deleteSync();
    await service(damaged).download(single(const {}));
    expect(io.File(rom()).existsSync(), isTrue);
  });

  test("several files: each checked once unpacked; a damaged one is named and nothing moves", () async {
    final two = [...good]..[0] = 9;
    final game = Game.fromJson({
      ...gameJson(2, 'B', fsName: 'B', multi: true),
      'files': [
        {'file_name': 'B (Disc 1).chd', 'sha1_hash': sha1Of(good)},
        {'file_name': 'B (Disc 2).chd', 'sha1_hash': sha1Of(good)},
      ],
    });
    await expectLater(
      service(zipOf({'B (Disc 1).chd': good, 'B (Disc 2).chd': two})).download(game),
      throwsA(isA<DownloadDamaged>().having((e) => e.files, 'files', ['B (Disc 2).chd'])),
    );
    expect(io.Directory(p.join(root.roms, 'ps2', 'B')).existsSync(), isFalse);
    await service(zipOf({'B (Disc 1).chd': good, 'B (Disc 2).chd': good})).download(game);
    expect(io.Directory(p.join(root.roms, 'ps2', 'B')).listSync(), hasLength(2));
  });

  test("a ROM that is an archive (an arcade set) isn't checked: RomM hashes what's inside", () async {
    final game = Game.fromJson({
      ...gameJson(3, 'sf2', fsName: 'sf2.zip'),
      'files': [
        {
          'file_name': 'sf2.zip',
          'sha1_hash': sha1Of([1, 2, 3]),
        },
      ],
    });
    await service(good).download(game);
    expect(io.File(p.join(root.roms, 'ps2', 'sf2.zip')).existsSync(), isTrue);
  });

  test('files of one name in two folders are each checked at their own path', () async {
    final two = [...good]..[0] = 9;
    final game = Game.fromJson({
      ...gameJson(4, 'C', fsName: 'C', multi: true),
      'files': [
        {'file_name': 'track01.bin', 'full_path': 'ps2/C/Disc 1/track01.bin', 'sha1_hash': sha1Of(good)},
        {'file_name': 'track01.bin', 'full_path': 'ps2/C/Disc 2/track01.bin', 'sha1_hash': sha1Of(two)},
      ],
    });
    await service(zipOf({'Disc 1/track01.bin': good, 'Disc 2/track01.bin': two})).download(game);
    expect(io.Directory(p.join(root.roms, 'ps2', 'C')).listSync(recursive: true).whereType<io.File>(), hasLength(2));
  });

  test("a file RomM lists that didn't come is damaged too", () async {
    final game = Game.fromJson({
      ...gameJson(5, 'D', fsName: 'D', multi: true),
      'files': [
        {'file_name': 'D (Disc 1).chd', 'sha1_hash': sha1Of(good)},
        {'file_name': 'D (Disc 2).chd', 'sha1_hash': sha1Of(good)},
      ],
    });
    await expectLater(
      service(zipOf({'D (Disc 1).chd': good})).download(game),
      throwsA(isA<DownloadDamaged>().having((e) => e.files, 'files', ['D (Disc 2).chd'])),
    );
  });

  test('a game being checked is an active download (never queued twice)', () {
    expect(DownloadPhase.checking.active, isTrue);
  });
}
