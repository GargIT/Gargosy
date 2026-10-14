import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/backup_entry.dart';
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
}
