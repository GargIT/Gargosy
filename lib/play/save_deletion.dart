import 'dart:io' as io;

import 'package:flutter/foundation.dart';

import '../core/romm/romm_models.dart';
import '../core/romm/romm_service.dart';
import '../core/save/backup_repository.dart';
import '../core/save/catalog/play_preparer.dart';
import '../core/save/catalog/save_entry.dart';
import '../core/save/resume_service.dart';
import '../core/save/save_sync_service.dart';
import '../profiles/path_guard.dart';

/// A save of the game page's Saves tab deleted: on RomM ([romm]), a backup
/// (its zip and its place in [backups]), or this PC's own ([deleteLocal]).
Future<void> deleteSaveEntry(
  Game game,
  SaveEntry save, {
  required RommService? romm,
  required BackupRepository? backups,
  required Future<void> Function() deleteLocal,
}) async {
  switch (save.source) {
    case SaveSource.romm:
      final id = save.rommSave?['id'];
      if (id is! int || romm == null) throw StateError('RomM has no id for this save');
      if (save.owner != null) throw StateError("another player's save isn't yours to delete");
      if (!await romm.deleteSaves([id])) throw StateError('RomM refused');
    case SaveSource.backup:
      final entry = save.backup;
      if (entry == null || backups == null) throw StateError('the backup is gone');
      await backups.removeEntry(game.id, entry);
      final zip = io.File(entry.localZipPath);
      if (zip.existsSync()) zip.deleteSync();
    case SaveSource.local:
      await deleteLocal();
  }
}

/// Gargosy (#94): this PC's save of the emulator that made [save], backed
/// up first (listed among the backups), then its files deleted through the
/// profile's [guard], under the save lock. A save other games share (a
/// memory card, sigil's cards) is refused with why
/// (`SaveStrategy.deletableSaveFiles`), before anything is backed up.
Future<void> deleteLocalSave(
  Game game,
  String romPath,
  SaveEntry save, {
  required SaveSyncService sync,
  required PlayPreparer preparer,
  required PathGuard guard,
}) async {
  final who = save.maker ?? (throw StateError("it isn't known which emulator made this save"));
  final core = who.coreId == null ? null : '${who.coreId}_libretro';
  final files = await sync.withStrategy(
    game,
    (s) => s.deletableSaveFiles(game, romPath),
    emulatorId: who.emulatorId,
    coreOverride: core,
  );
  if (files == null) throw StateError("${who.emulatorId}'s saves can't be deleted from here");
  for (final f in files) {
    guard.check(f.path);
  }
  await preparer.backUp(game, romPath, who);
  await sync.withStrategy(
    game,
    (s) async {
      for (final f in await s.deletableSaveFiles(game, romPath)) {
        await io.File(guard.check(f.path)).delete();
      }
      await s.afterSaveDeleted(game, romPath);
    },
    emulatorId: who.emulatorId,
    coreOverride: core,
  );
  debugPrint("[Saves] ${game.displayName}: $who's save on this PC deleted (backed up first)");
}

/// Gargosy (#94): the player's own state [entry] deleted: its file on this
/// PC with what belongs to it (through [guard]), its sync record, and its
/// copy on RomM. Null when done, else what couldn't be.
Future<String?> deleteOwnState(
  Game game,
  ResumeEntry entry, {
  required ResumeService resume,
  required PathGuard guard,
  required RommService? romm,
}) async {
  if (entry.owner != null) throw StateError("another player's state isn't yours to delete");
  for (final f in resume.localFilesOf(entry)) {
    if (await f.exists()) await io.File(guard.check(f.path)).delete();
  }
  await resume.forgetState(game, entry.fileName);
  final id = entry.remoteId;
  if (id == null) return null;
  if (romm == null || romm.isOffline.value || !await romm.deleteStates([id])) {
    return entry.localFile == null ? "RomM can't be reached" : "it's deleted on this PC, but RomM can't be reached";
  }
  return null;
}
