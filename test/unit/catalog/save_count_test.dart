import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/core/save/catalog/save_count.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';

void main() {
  final t = DateTime(2026, 10, 16, 17, 47);
  SaveEntry local({Set<String> hashes = const {}, String? sameAs}) =>
      SaveEntry(source: SaveSource.local, fileName: 'l', savedAt: t, contentHashes: hashes, sameAsRommId: sameAs);
  SaveEntry backup(String hash) => SaveEntry(
    source: SaveSource.backup,
    fileName: 'b',
    savedAt: t,
    contentHashes: {hash},
    backup: BackupEntry(timestamp: t, md5Hash: hash, localZipPath: '/b.zip'),
  );
  SaveEntry romm(String id, {String? hash}) => SaveEntry(
    source: SaveSource.romm,
    fileName: 'r',
    savedAt: t,
    slot: 'autosave',
    rommSave: {'id': id, 'content_hash': ?hash},
  );

  test('one save on this PC, on RomM and in a backup is 1', () {
    expect(
      distinctSaveCount([
        local(hashes: {'h'}),
        backup('h'),
        romm('9', hash: 'h'),
      ]),
      1,
    );
  });

  test('a save last synced with a RomM save is that save, whatever its hash', () {
    expect(distinctSaveCount([local(sameAs: '9'), romm('9')]), 1);
  });

  test('copies joined through a third count once', () {
    // The backup matches RomM's hash, RomM's id matches the save on this PC.
    expect(distinctSaveCount([backup('h'), local(sameAs: '9'), romm('9', hash: 'h')]), 1);
  });

  test('different contents are different saves', () {
    expect(
      distinctSaveCount([
        local(hashes: {'new'}),
        backup('old'),
        romm('9', hash: 'new'),
        romm('8', hash: 'older'),
      ]),
      3,
    );
  });

  test('a row with nothing to compare counts on its own', () {
    expect(distinctSaveCount([local(), local(), romm('9')]), 3);
    expect(distinctSaveCount(const []), 0);
  });
}
