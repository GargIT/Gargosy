// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';

import 'backup_entry.dart';

/// Where a [BackupRepository] keeps its list (Gargosy: the profile's
/// `backups\index.json`, `JsonBackupStore`). Freegosy used a Hive box.
abstract class BackupStore {
  /// The list as written last; null when there is none yet.
  Map<String, dynamic>? read();

  /// Replaces the stored list with [data].
  Future<void> write(Map<String, dynamic> data);

  /// How [localZipPath] is stored, and back: the store may keep it shorter,
  /// and refuse (null) a stored path it won't hand out.
  String toStored(String localZipPath) => localZipPath;
  String? fromStored(String zip) => zip;
}

/// Repository that persists up to [_maxBackups] local backup entries per
/// game ROM. Business logic (rotation, disk cleanup) lives here so that
/// providers stay thin.
class BackupRepository {
  // Gargosy: one list per profile, so profiles never see each other's
  // backups. Kept in memory and written whole after each change, one write
  // at a time; without a [store] (tests) it lives in memory only.
  BackupRepository({this.store}) {
    _games.addAll(_read() ?? const {});
  }

  /// Where the list is kept; null keeps it in memory only.
  final BackupStore? store;
  static const int _maxBackups = 8;
  static const int _formatVersion = 1;

  final Map<String, List<BackupEntry>> _games = {};
  Future<void> _writing = Future.value();

  /// True while the stored list couldn't be read (locked, or a newer
  /// format): nothing is written over it then.
  bool _unread = false;

  /// The stored list, or null when it can't be read ([_unread] is set).
  Map<String, List<BackupEntry>>? _read() {
    final store = this.store;
    if (store == null) return const {};
    final Map<String, dynamic>? data;
    try {
      data = store.read();
    } on Object catch (e) {
      debugPrint('[BackupRepository] the backup list could not be read ($e); it is left as it is');
      _unread = true;
      return null;
    }
    if (data == null) {
      _unread = false;
      return const {};
    }
    final version = data['version'];
    final games = data['games'];
    if (games is! Map || (version is int && version > _formatVersion)) {
      debugPrint('[BackupRepository] the backup list is in a format this Gargosy does not know; it is left as it is');
      _unread = true;
      return null;
    }
    _unread = false;
    return {
      for (final e in games.entries)
        if (e.value case final List list)
          '${e.key}': [for (final j in list) ?BackupEntry.fromJson(j, zipPath: store.fromStored)],
    };
  }

  /// Writes the whole list, after any write still running. A list that
  /// couldn't be read at start is read again first, and the games it holds
  /// that this session hasn't changed are kept; while it still can't be
  /// read nothing is written. A failed write is logged, and the next one
  /// writes everything again.
  Future<void> _save() {
    final store = this.store;
    if (store == null) return Future.value();
    final done = _writing
        .then((_) async {
          if (_unread) {
            final stored = _read();
            if (stored == null) return;
            for (final e in stored.entries) {
              _games.putIfAbsent(e.key, () => e.value);
            }
          }
          await store.write({
            'version': _formatVersion,
            'games': {
              for (final e in _games.entries)
                if (e.value.isNotEmpty) e.key: [for (final b in e.value) b.toJson(zip: store.toStored(b.localZipPath))],
            },
          });
        })
        .catchError((Object e) => debugPrint('[BackupRepository] write failed: $e'));
    return _writing = done;
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the backup list for [romId], newest-first.
  List<BackupEntry> getEntries(String romId) => [...?_games[romId]];

  /// Returns all unsynced entries across all games, along with their romId.
  List<({String romId, BackupEntry entry})> getUnsyncedEntries() {
    final unsynced = <({String romId, BackupEntry entry})>[];
    for (final romId in _games.keys) {
      final entries = getEntries(romId);
      for (final entry in entries) {
        if (!entry.isSynced) {
          unsynced.add((romId: romId, entry: entry));
        }
      }
    }
    // Sort oldest first so they get processed in order of creation
    unsynced.sort((a, b) => a.entry.timestamp.compareTo(b.entry.timestamp));
    return unsynced;
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Appends [entry] for [romId]. If the list would exceed [_maxBackups], the
  /// oldest entry is silently deleted from disk and removed from the list.
  Future<void> addEntry(String romId, BackupEntry entry) async {
    final entries = getEntries(romId);
    entries.insert(0, entry); // newest first

    final overflow = entries.length > _maxBackups ? entries.sublist(_maxBackups) : const <BackupEntry>[];
    if (overflow.isNotEmpty) entries.removeRange(_maxBackups, entries.length);
    _games[romId] = entries;
    await _save();
    for (final old in overflow) {
      await _deleteFile(old.localZipPath);
    }
  }

  /// Adds [entry] unless it holds the same files as the newest backup of
  /// [romId] (same [BackupEntry.md5Hash]); then its zip is deleted instead.
  /// Whether it was added.
  Future<bool> addUnlessSameAsNewest(String romId, BackupEntry entry) async {
    final newest = getEntries(romId).firstOrNull;
    if (newest != null && newest.md5Hash == entry.md5Hash) {
      await _deleteFile(entry.localZipPath);
      return false;
    }
    await addEntry(romId, entry);
    return true;
  }

  /// Removes a specific [entry] for [romId] and deletes its physical ZIP.
  Future<void> removeEntry(String romId, BackupEntry entry) async {
    final entries = getEntries(romId);
    entries.removeWhere((e) => e.localZipPath == entry.localZipPath && e.timestamp == entry.timestamp);
    _games[romId] = entries;
    await _save();
    await _deleteFile(entry.localZipPath);
  }

  /// Marks a specific [entry] as synced.
  Future<void> markAsSynced(String romId, BackupEntry entry) async {
    final entries = getEntries(romId);
    final index = entries.indexWhere((e) => e.localZipPath == entry.localZipPath && e.timestamp == entry.timestamp);
    if (index != -1) {
      final old = entries[index];
      entries[index] = BackupEntry(
        timestamp: old.timestamp,
        md5Hash: old.md5Hash,
        localZipPath: old.localZipPath,
        isSynced: true,
        emulatorId: old.emulatorId,
        coreId: old.coreId,
      );
      _games[romId] = entries;
      await _save();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _deleteFile(String path) async {
    try {
      final file = io.File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[BackupRepository] Could not delete backup file: $path ($e)');
    }
  }
}
