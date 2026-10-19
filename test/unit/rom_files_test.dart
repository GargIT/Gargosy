import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  test('a game lives at roms\\<platform>\\<fs_name>, names made safe (! included)', () {
    final files = RomFiles(root);
    expect(
      files.pathFor(game(1, 'Burnout 3', fsName: 'Burnout 3 (USA).chd')),
      p.join(root.roms, 'ps2', 'Burnout 3 (USA).chd'),
    );
    expect(RomFiles.safeName('Zelda: A Link [!]?.zip'), 'Zelda_ A Link [_]_.zip');
    expect(RomFiles.safeName(r'..\..\x'), '.._.._x');
    expect(RomFiles.safeName('name. '), 'name');
    expect(RomFiles.safeName('...'), '_');
  });

  test('downloaded? is a file or a folder at that path; delete removes only it', () async {
    final files = RomFiles(root);
    final single = game(1, 'A', fsName: 'A.iso');
    final multi = game(2, 'B', fsName: 'B', multi: true);
    expect(files.isDownloaded(single), isFalse);
    io.File(files.pathFor(single))
      ..createSync(recursive: true)
      ..writeAsStringSync('rom');
    io.File(p.join(files.pathFor(multi), 'B (Disc 1).chd'))
      ..createSync(recursive: true)
      ..writeAsStringSync('rom');
    final other = io.File(p.join(root.roms, 'ps2', 'C.iso'))..writeAsStringSync('rom');
    expect(files.isDownloaded(single), isTrue);
    expect(files.isDownloaded(multi), isTrue);
    await files.delete(single, PathGuard(root));
    await files.delete(multi, PathGuard(root));
    expect(files.isDownloaded(single), isFalse);
    expect(files.isDownloaded(multi), isFalse);
    expect(other.existsSync(), isTrue);
  });
}
