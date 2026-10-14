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

  /// A damaged list is kept aside as `index.damaged-<time>.json` (its
  /// backups are listed nowhere then, but their zips stay) and the list
  /// starts empty. When it can't be kept aside, or the file can't be read at
  /// all, this throws, and the repository writes nothing over it.
  @override
  Map<String, dynamic>? read() {
    try {
      return readJsonObjectSync(file);
    } on FormatException catch (e) {
      final aside = p.join(paths.backups, 'index.damaged-${DateTime.now().millisecondsSinceEpoch}.json');
      io.File(file).renameSync(paths.guard.check(aside));
      debugPrint('[Backups] $file is damaged ($e); kept aside as $aside, starting empty');
      return null;
    }
  }

  /// Skipped when the profile's folder is gone (deleted while a write
  /// waited): writing would make the folder again.
  @override
  Future<void> write(Map<String, dynamic> data) async {
    if (!io.Directory(paths.dir).existsSync()) return;
    await writeJsonObject(paths.guard, file, data);
  }

  // Every backup zip is in backups\ (BackupService writes them there): the
  // list keeps the name alone, and a name read back is only ever a .zip in
  // that folder, so an edited list can't make a rotation delete anything
  // else (the list itself included).
  @override
  String toStored(String localZipPath) => p.basename(localZipPath);

  @override
  String? fromStored(String zip) {
    final full = p.join(paths.backups, p.basename(zip));
    return p.isWithin(paths.backups, full) && p.extension(full).toLowerCase() == '.zip' ? full : null;
  }
}
