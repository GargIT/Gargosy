import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/core/save/backup_repository.dart';
import 'package:gargosy/profiles/backups_index.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late ProfilePaths anna;
  late ProfilePaths bert;

  setUp(() async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    anna = ProfilePaths(root, 'anna-1');
    bert = ProfilePaths(root, 'bert-2');
    // A profile's folder exists while it's in use: the list is never written without it.
    for (final x in [anna, bert]) {
      io.Directory(x.dir).createSync(recursive: true);
    }
  });

  BackupEntry entry(ProfilePaths of, String name, {DateTime? at, String? emulator, String? core}) => BackupEntry(
      timestamp: at ?? DateTime(2026, 10, 14, 9, 30, 15, 250),
      md5Hash: 'md5-$name',
      localZipPath: p.join(of.backups, '$name.zip'),
      emulatorId: emulator,
      coreId: core);

  test("a profile's list is backups/index.json, and reads back as it was written", () async {
    final repo = BackupRepository(store: JsonBackupStore(anna));
    final a = entry(anna, 'a', emulator: 'retroarch', core: 'mgba');
    await repo.addEntry('12', a);
    await repo.markAsSynced('12', a);
    await repo.addEntry('12', entry(anna, 'b', at: DateTime(2026, 10, 14, 10)));

    expect(io.File(p.join(anna.backups, 'index.json')).existsSync(), isTrue);
    expect(io.Directory(anna.dir).listSync().whereType<io.File>(), isEmpty, reason: 'nothing in the profile root');
    final again = BackupRepository(store: JsonBackupStore(anna)).getEntries('12');
    expect(again.map((e) => e.md5Hash), ['md5-b', 'md5-a']);
    final read = again.last;
    expect(read.timestamp, a.timestamp);
    expect(read.isSynced, isTrue);
    expect(read.emulatorId, 'retroarch');
    expect(read.coreId, 'mgba');
    expect(read.localZipPath, a.localZipPath);
    expect(again.first.isSynced, isFalse);
  });

  test("each profile has its own list", () async {
    await BackupRepository(store: JsonBackupStore(anna)).addEntry('12', entry(anna, 'a'));
    expect(BackupRepository(store: JsonBackupStore(bert)).getEntries('12'), isEmpty);
  });

  test('zips are stored by name, so the list follows a moved Gargosy folder', () async {
    await BackupRepository(store: JsonBackupStore(anna)).addEntry('12', entry(anna, 'a'));
    final text = io.File(p.join(anna.backups, 'index.json')).readAsStringSync();
    expect(text, contains('"zip": "a.zip"'));
    expect(text, isNot(contains(r'\\')), reason: 'no path at all, only the name');
  });

  test("a stored name never leads out of backups/, so a rotation can't delete anything else", () {
    final store = JsonBackupStore(anna);
    expect(store.fromStored(r'..\..\x.zip'), p.join(anna.backups, 'x.zip'));
    expect(store.fromStored('..'), isNull);
    expect(store.fromStored('index.json'), isNull, reason: 'only zips');
    expect(store.fromStored('index.json.tmp'), isNull);
    expect(store.fromStored(r'C:\Windows\x.zip'), p.join(anna.backups, 'x.zip'));
  });

  test('a damaged list is kept aside and the list starts empty', () {
    io.Directory(anna.backups).createSync(recursive: true);
    io.File(p.join(anna.backups, 'index.json')).writeAsStringSync('{not json');
    expect(BackupRepository(store: JsonBackupStore(anna)).getEntries('12'), isEmpty);
    final aside = io.Directory(anna.backups).listSync().where((e) => p.basename(e.path).startsWith('index.damaged-'));
    expect(io.File(aside.single.path).readAsStringSync(), '{not json');
  });

  test('an entry that makes no sense is skipped, the rest still read', () {
    io.Directory(anna.backups).createSync(recursive: true);
    io.File(p.join(anna.backups, 'index.json')).writeAsStringSync('{"version": 1, "games": {"12": ['
        '{"time": "nope", "md5": "x", "zip": "x.zip"},'
        '{"time": "2026-10-14T09:00:00.000", "md5": "ok", "zip": "ok.zip", "synced": true}]}}');
    final read = BackupRepository(store: JsonBackupStore(anna)).getEntries('12');
    expect(read.single.md5Hash, 'ok');
    expect(read.single.emulatorId, isNull);
  });

  test("a list that can't be read is never written over; once readable, its games are kept", () async {
    io.Directory(anna.backups).createSync(recursive: true);
    final index = io.File(p.join(anna.backups, 'index.json'));
    await BackupRepository(store: JsonBackupStore(anna)).addEntry('12', entry(anna, 'a'));
    final locked = index.openSync(mode: io.FileMode.append)..lockSync();
    final repo = BackupRepository(store: JsonBackupStore(anna));
    expect(repo.getEntries('12'), isEmpty);
    await repo.addEntry('34', entry(anna, 'b'));
    locked
      ..unlockSync()
      ..closeSync();
    expect(BackupRepository(store: JsonBackupStore(anna)).getEntries('12'), hasLength(1), reason: 'not written over');
    await repo.addEntry('34', entry(anna, 'c', at: DateTime(2026, 10, 15)));
    final again = BackupRepository(store: JsonBackupStore(anna));
    expect(again.getEntries('12').single.md5Hash, 'md5-a');
    expect(again.getEntries('34').map((e) => e.md5Hash), ['md5-c', 'md5-b']);
  });

  test('a list in a newer format is left as it is', () async {
    io.Directory(anna.backups).createSync(recursive: true);
    final index = io.File(p.join(anna.backups, 'index.json'))..writeAsStringSync('{"version": 2, "games": {}}');
    await BackupRepository(store: JsonBackupStore(anna)).addEntry('12', entry(anna, 'a'));
    expect(index.readAsStringSync(), '{"version": 2, "games": {}}');
  });

  test("a profile deleted while a write waited isn't made again", () async {
    final repo = BackupRepository(store: JsonBackupStore(anna));
    await repo.addEntry('12', entry(anna, 'a'));
    io.Directory(anna.dir).deleteSync(recursive: true);
    await repo.addEntry('12', entry(anna, 'b'));
    expect(io.Directory(anna.dir).existsSync(), isFalse);
  });

  test('an entry with no synced mark counts as synced, as the Hive list read it', () {
    io.Directory(anna.backups).createSync(recursive: true);
    io.File(p.join(anna.backups, 'index.json'))
        .writeAsStringSync('{"version": 1, "games": {"12": [{"time": "2026-10-14T09:00:00.000", "md5": "m", "zip": "m.zip"}]}}');
    expect(BackupRepository(store: JsonBackupStore(anna)).getEntries('12').single.isSynced, isTrue);
  });
}
