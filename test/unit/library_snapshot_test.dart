import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late LibrarySnapshot snap;
  setUp(() async {
    root = await tempAppRoot();
    final paths = ProfilePaths(root, 'aaa');
    snap = LibrarySnapshot(p.join(paths.cache, 'library.json'), paths.guard);
  });
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  test('keeps the games it was told about, as they were', () async {
    await snap.remember(game(1, 'Okami', platform: 'ps2'));
    await snap.remember(game(2, 'Ico', platform: 'ps2'));
    await snap.remember(game(1, 'Okami HD', platform: 'ps2')); // newer details replace older
    final games = snap.read();
    expect(games.map((g) => g.displayName), ['Ico', 'Okami HD']);
    expect(snap.find('2')?.platformSlug, 'ps2');
  });

  test('forgets a deleted game', () async {
    await snap.remember(game(1, 'Okami'));
    await snap.forget('1');
    expect(snap.read(), isEmpty);
  });

  test('a damaged file reads as empty and is replaced on the next write', () async {
    final file = io.File(p.join(ProfilePaths(root, 'aaa').cache, 'library.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{not json');
    expect(snap.read(), isEmpty);
    await snap.remember(game(3, 'Rez'));
    expect(file.readAsStringSync(), contains('Rez'));
  });
}
