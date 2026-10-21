// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter/foundation.dart';

import '../backup_entry.dart';
import 'save_maker.dart';

/// Where a save row comes from.
enum SaveSource { local, backup, romm }

/// The RomM user another player's shared save belongs to (#92).
@immutable
class SaveOwner {
  const SaveOwner({required this.userId, required this.username, this.avatarPath});
  final int userId;
  final String username;

  /// RomM's `user_avatar_path`; null when they have none.
  final String? avatarPath;

  @override
  bool operator ==(Object other) => other is SaveOwner && other.userId == userId;
  @override
  int get hashCode => userId.hashCode;
}

/// One save the user can look at, restore or play.
@immutable
class SaveEntry {
  const SaveEntry({
    required this.source,
    required this.fileName,
    required this.savedAt,
    this.maker,
    this.tag,
    this.sizeBytes,
    this.slot,
    this.rommSave,
    this.backup,
    this.sameAsRommId,
    this.contentHashes = const {},
    this.sharedFile = false,
    this.owner,
  });

  /// A save from RomM's save list ([save] is the list item as RomM sent it).
  /// [shared]: another player's public save (the game's `all_user_saves`),
  /// its owner read from the item.
  factory SaveEntry.fromRomm(Map<String, dynamic> save, {required Set<String> emulatorIds, bool shared = false}) {
    final tag = save['emulator']?.toString();
    final time =
        DateTime.tryParse(save['updated_at']?.toString() ?? '') ??
        DateTime.tryParse(save['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final size = save['file_size_bytes'];
    return SaveEntry(
      source: SaveSource.romm,
      fileName: save['file_name']?.toString() ?? '',
      savedAt: time.toLocal(),
      maker: resolveSaveMaker(tag, emulatorIds: emulatorIds),
      tag: tag,
      sizeBytes: size is int ? size : int.tryParse(size?.toString() ?? ''),
      slot: save['slot']?.toString(),
      rommSave: save,
      owner: shared
          ? SaveOwner(
              userId: (save['user_id'] as num?)?.toInt() ?? -1,
              username: save['username']?.toString() ?? '?',
              avatarPath: (save['user_avatar_path']?.toString() ?? '').isEmpty
                  ? null
                  : save['user_avatar_path'].toString(),
            )
          : null,
    );
  }

  final SaveSource source;
  final String fileName;
  final DateTime savedAt;

  /// Who made it; null when that can't be told.
  final SaveMaker? maker;

  /// The tag shown on the row: RomM's `emulator`, or the maker's tag for a
  /// save on this PC.
  final String? tag;
  final int? sizeBytes;

  /// RomM's slot (RomM rows only).
  final String? slot;

  /// The RomM list item, for downloading (RomM rows only).
  final Map<String, dynamic>? rommSave;

  /// The backup (backup rows only).
  final BackupEntry? backup;

  /// The id of the RomM save that holds exactly this save, as this PC last
  /// synced it (local rows only); null when it changed since.
  final String? sameAsRommId;

  /// The `content_hash` RomM would give this save as each sync mode uploads
  /// it (local rows; see SaveSyncService.rommHashOfLocal), or the backup's
  /// hash (backup rows; BackupService.createImmediate makes it the same).
  final Set<String> contentHashes;

  /// The save is in a file other games share (a memory card): its time is
  /// the file's, which any game on it changes (local rows only).
  final bool sharedFile;

  /// Another player's save, shared on RomM (#92); null for the player's own.
  /// Never synced with: playing it makes a copy that is the player's own.
  final SaveOwner? owner;

  /// RomM rows with the same key are versions of one save.
  String get groupKey => '${slot ?? ''}|${tag ?? ''}';
}
