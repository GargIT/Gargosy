import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/save/backup_repository.dart';
import 'json_file.dart';
import 'profile_paths.dart';

/// A profile's backup list: `backups\index.json`, beside the zips it lists,
/// written whole through the profile's guard (a `.tmp` renamed into place).
/// A zip is stored by its name alone, so the list still finds it after the
/// Gargosy folder moves.
class JsonBackupStore extends BackupStore {
  JsonBackupStore(this.paths);

  final ProfilePaths paths;

  String get file => p.join(paths.backups, 'index.json');

  /// A damaged list is kept aside as `index.damaged.json` (the backups
  /// stay listed nowhere, but their zips stay), and the list starts empty.
  @override
  Map<String, dynamic>? read() {
    try {
      return readJsonObjectSync(file);
    } on FormatException catch (e) {
      debugPrint('[Backups] $file is damaged ($e); kept aside, starting empty');
      try {
        io.File(file).renameSync(paths.guard.check(p.join(paths.backups, 'index.damaged.json')));
      } on io.FileSystemException catch (e) {
        debugPrint('[Backups] could not keep the damaged list aside: $e');
      }
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> data) => writeJsonObject(paths.guard, file, data);

  // Every backup zip is in backups\ (BackupService writes them there): the
  // list keeps the name alone, and a name read back never leads out of the
  // folder, so an edited list can't make a rotation delete anything else.
  @override
  String toStored(String localZipPath) => p.basename(localZipPath);

  @override
  String? fromStored(String zip) {
    final full = p.join(paths.backups, p.basename(zip));
    return p.isWithin(paths.backups, full) ? full : null;
  }
}
