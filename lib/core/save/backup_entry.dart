// Adapted from Freegosy (MIT, © 2026 abduznik).

/// A single local save backup checkpoint for a game.
class BackupEntry {
  final DateTime timestamp;
  final String md5Hash;
  final String localZipPath;
  final bool isSynced;

  /// The emulator the backed-up save belongs to; null for backups made
  /// before this was recorded.
  final String? emulatorId;

  /// The RetroArch core (e.g. `mgba`) when [emulatorId] is RetroArch; null
  /// for another emulator, or a backup made before this was recorded.
  final String? coreId;

  BackupEntry({
    required this.timestamp,
    required this.md5Hash,
    required this.localZipPath,
    this.isSynced = false,
    this.emulatorId,
    this.coreId,
  });

  // Gargosy: the backup list is JSON (`backups\index.json`), not a Hive box.
  // [zip] is how the list stores [localZipPath] (the name alone for a zip
  // in the backups folder, so the list survives a moved Gargosy folder).
  Map<String, dynamic> toJson({String? zip}) => {
    'time': timestamp.toIso8601String(),
    'md5': md5Hash,
    'zip': zip ?? localZipPath,
    'synced': isSynced,
    'emulator': ?emulatorId,
    'core': ?coreId,
  };

  /// Null when [json] isn't a backup entry. [zipPath] turns the stored
  /// `zip` back into a full path, or refuses it (null).
  static BackupEntry? fromJson(Object? json, {String? Function(String zip)? zipPath}) {
    if (json is! Map) return null;
    final time = DateTime.tryParse('${json['time']}');
    final md5 = json['md5'];
    final zip = json['zip'];
    if (time == null || md5 is! String || zip is! String || zip.isEmpty) return null;
    final path = zipPath == null ? zip : zipPath(zip);
    if (path == null) return null;
    final emulator = json['emulator'];
    final core = json['core'];
    return BackupEntry(
      timestamp: time,
      md5Hash: md5,
      localZipPath: path,
      // As Freegosy's Hive adapter read it: a backup with no mark counts as synced.
      isSynced: json['synced'] != false,
      emulatorId: emulator is String ? emulator : null,
      coreId: core is String ? core : null,
    );
  }
}
