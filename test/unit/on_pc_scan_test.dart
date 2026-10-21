import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/library/on_pc_scan.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late LibrarySnapshot snapshot;
  setUp(() async {
    root = await tempAppRoot();
    final paths = ProfilePaths(root, 'aaa');
    io.Directory(paths.cache).createSync(recursive: true);
    snapshot = LibrarySnapshot(p.join(paths.cache, 'library.json'), paths.guard);
  });
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  test("the platform's games in the roms folder that the list lacks are added in one go; the rest left alone", () async {
    final games = [for (var i = 1; i <= 7; i++) game(i, 'Game $i')];
    io.Directory(p.join(root.roms, 'ps2')).createSync(recursive: true);
    for (final i in [2, 5, 7]) {
      io.File(p.join(root.roms, 'ps2', 'Game $i.chd')).writeAsBytesSync([1]);
    }
    await snapshot.remember(games[1]); // Game 2: already on the list
    final api = FakeLibraryApi(games);
    final n = await scanPlatformOnPc(api: api, platformId: 1, files: RomFiles(root), snapshot: snapshot, pageSize: 3);
    expect(n, 2);
    expect([for (final g in snapshot.read()) g.name], ['Game 2', 'Game 5', 'Game 7']);
    expect(api.queries.map((q) => q.$2), [0, 3, 6]);
    expect(api.queries.every((q) => q.$1.platformId == 1), isTrue);
    expect(await scanPlatformOnPc(api: api, platformId: 1, files: RomFiles(root), snapshot: snapshot), 0);
  });

  test("RomM away: it throws, and the list isn't touched", () async {
    final api = FakeLibraryApi([game(1, 'Game 1')])..failWith = Exception('SocketException');
    await expectLater(
      scanPlatformOnPc(api: api, platformId: 1, files: RomFiles(root), snapshot: snapshot),
      throwsException,
    );
    expect(snapshot.read(), isEmpty);
  });
}
