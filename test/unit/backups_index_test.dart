import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/backups_index.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late ProfilePaths paths;
  late String name;

  setUp(() async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    paths = ProfilePaths(root, 'anna-1');
    io.Directory(paths.dir).createSync(recursive: true);
    name = backupsBoxName(paths.id);
  });

  io.File inRoot(String ext) => io.File(p.join(paths.dir, '$name.$ext'));
  io.File inBackups(String ext) => io.File(p.join(paths.backups, '$name.$ext'));

  test('a new profile gets backups\\ and nothing in its root', () {
    expect(moveBackupsIndex(paths), paths.backups);
    expect(io.Directory(paths.backups).existsSync(), isTrue);
    expect(inRoot('hive').existsSync(), isFalse);
  });

  test("the box in the profile's root moves into backups\\, with a crash's lock gone", () {
    inRoot('hive').writeAsStringSync('index');
    inRoot('lock').writeAsStringSync('');
    expect(moveBackupsIndex(paths), paths.backups);
    expect(inBackups('hive').readAsStringSync(), 'index');
    expect(inRoot('hive').existsSync(), isFalse);
    expect(inRoot('lock').existsSync(), isFalse);
  });

  test('a box already in backups\\ is never replaced', () {
    io.Directory(paths.backups).createSync();
    inBackups('hive').writeAsStringSync('new');
    inRoot('hive').writeAsStringSync('old');
    moveBackupsIndex(paths);
    expect(inBackups('hive').readAsStringSync(), 'new');
    expect(inRoot('hive').readAsStringSync(), 'old', reason: 'left alone, not deleted');
  });

  test("a crash's compaction copy moves with the box, so Hive can still recover it", () {
    inRoot('hivec').writeAsStringSync('compacted');
    expect(moveBackupsIndex(paths), paths.backups);
    expect(inBackups('hivec').readAsStringSync(), 'compacted');
    expect(inRoot('hivec').existsSync(), isFalse);
  });

  test("a box that can't move opens where it is", () {
    inRoot('hive').writeAsStringSync('index');
    // backups\ can't be made: a file has its name.
    io.File(paths.backups).writeAsStringSync('');
    expect(moveBackupsIndex(paths), paths.dir);
    expect(inRoot('hive').readAsStringSync(), 'index');
  });
}
