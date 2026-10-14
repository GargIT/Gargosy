import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/core/save/backup_repository.dart';
import 'package:gargosy/profiles/backups_index.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late ProfilePaths anna;
  late ProfilePaths bert;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(BackupEntryAdapter());
  });

  setUp(() async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    anna = ProfilePaths(root, 'anna-1');
    bert = ProfilePaths(root, 'bert-2');
  });

  test("a profile's list is backups\\index.hive, and nothing lands in its root", () async {
    final box = await openBackupsBox(anna);
    expect(box.path, p.join(anna.backups, 'index.hive'));
    expect(io.Directory(anna.dir).listSync().whereType<io.File>(), isEmpty);
    await closeBackupsBox();
  });

  test("opening a profile's list closes the last profile's first, so it never gets that box", () async {
    final a = await openBackupsBox(anna);
    await a.put('1', ['anna']);
    final b = await openBackupsBox(bert);
    expect(a.isOpen, isFalse);
    expect(b.isOpen, isTrue);
    expect(b.get('1'), isNull, reason: "bert's own list, not anna's");
    expect(b.path, p.join(bert.backups, 'index.hive'));
    await closeBackupsBox(b);
    final again = await openBackupsBox(anna);
    expect(again.get('1'), ['anna']);
    await closeBackupsBox();
    expect(again.isOpen, isFalse);
  });

  test("an old provider closing its box late leaves the next profile's open", () async {
    final a = await openBackupsBox(anna);
    final b = await openBackupsBox(bert);
    await closeBackupsBox(a);
    expect(b.isOpen, isTrue);
    await closeBackupsBox(b);
  });

  test('two opens at once: each profile gets its own list, and only the last stays open', () async {
    final carl = ProfilePaths(anna.root, 'carl-3');
    await (await openBackupsBox(anna)).put('1', ['anna']);
    await closeBackupsBox();
    final boxes = await Future.wait([openBackupsBox(bert), openBackupsBox(anna), openBackupsBox(carl)]);
    expect(boxes.map((b) => b.path), [for (final x in [bert, anna, carl]) p.join(x.backups, 'index.hive')]);
    expect(boxes.map((b) => b.isOpen), [false, false, true]);
    await closeBackupsBox();
  });

  test('closing while a list is still opening closes it once it has opened', () async {
    final opening = openBackupsBox(anna);
    await closeBackupsBox();
    expect((await opening).isOpen, isFalse);
  });

  test('a repository on a closed box fails instead of finding the next profile\'s', () async {
    final a = await openBackupsBox(anna);
    final repo = BackupRepository.ofBox(a);
    final b = await openBackupsBox(bert);
    await b.put('7', ['bert']);
    repo.initBox();
    expect(() => repo.getEntries('7'), throwsA(anything));
    await closeBackupsBox();
  });
}
