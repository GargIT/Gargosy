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
    moveBackupsIndex(paths);
    expect(io.Directory(paths.backups).existsSync(), isTrue);
    expect(inRoot('hive').existsSync(), isFalse);
  });

  test("the box in the profile's root moves into backups\\, with a crash's lock gone", () {
    inRoot('hive').writeAsStringSync('index');
    inRoot('lock').writeAsStringSync('');
    moveBackupsIndex(paths);
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
}
