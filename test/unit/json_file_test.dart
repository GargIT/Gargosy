import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/json_file.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

void main() {
  late io.Directory tmp;
  late AppRoot root;
  setUp(() async {
    tmp = await io.Directory.systemTemp.createTemp('jsonfile');
    root = AppRoot(tmp.path);
    await root.ensureLayout();
  });
  tearDown(() => tmp.delete(recursive: true));

  test('writes through a .tmp file and reads it back', () async {
    final path = p.join(root.profiles, 'aaa', 'profile.json');
    await writeJsonObject(PathGuard(root, activeProfileId: 'aaa'), path, {'name': 'Anna'});
    expect(io.File('$path.tmp').existsSync(), isFalse);
    expect(await readJsonObject(path), {'name': 'Anna'});
  });

  test('a missing file reads as null; a damaged one throws FormatException', () async {
    expect(await readJsonObject(p.join(tmp.path, 'none.json')), isNull);
    final bad = io.File(p.join(tmp.path, 'bad.json'))..writeAsStringSync('[1');
    expect(() => readJsonObject(bad.path), throwsFormatException);
    final list = io.File(p.join(tmp.path, 'list.json'))..writeAsStringSync('[1]');
    expect(() => readJsonObject(list.path), throwsFormatException);
  });

  test('a write outside the guard is refused and nothing is written', () async {
    final path = p.join(root.profiles, 'bbb', 'profile.json');
    expect(() => writeJsonObject(PathGuard(root, activeProfileId: 'aaa'), path, {}), throwsA(isA<PathGuardException>()));
    expect(io.File(path).existsSync(), isFalse);
  });

  test('writeBytesAtomic writes bytes through the guard', () async {
    final path = p.join(root.profiles, 'aaa', 'avatar.png');
    await writeBytesAtomic(PathGuard(root, activeProfileId: 'aaa'), path, [1, 2, 3]);
    expect(io.File(path).readAsBytesSync(), [1, 2, 3]);
  });
}
