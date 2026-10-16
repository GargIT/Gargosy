import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/library/rom_files.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  test('installed games: only those on this PC, newest download first, ties by name', () {
    final a = game(1, 'Alpha'), b = game(2, 'Beta'), c = game(3, 'Gamma'), d = game(4, 'Delta');
    final at = {a: DateTime(2026, 10, 1), b: DateTime(2026, 10, 16), c: DateTime(2026, 10, 1)};
    expect(installedNewestFirst([a, b, c, d], (g) => at[g]), [b, a, c]);
  });

  test("RomFiles.installedAt: the file's or the unpacked folder's time; null when it isn't here", () async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    final files = RomFiles(root);
    final iso = game(1, 'Okami', platform: 'ps2', fsName: 'Okami.iso');
    final zipped = game(2, 'Rez', platform: 'ps2', fsName: 'Rez.zip');
    expect(files.installedAt(iso), isNull);

    io.File(files.pathFor(iso))
      ..createSync(recursive: true)
      ..setLastModifiedSync(DateTime(2026, 10, 2));
    expect(files.installedAt(iso), DateTime(2026, 10, 2));

    io.Directory(files.unpackedDirFor(zipped)!).createSync(recursive: true);
    expect(files.installedAt(zipped), isNotNull, reason: 'an unpacked zip game is its folder');
  });
}
