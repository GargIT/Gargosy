import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/romm/romm_models.dart';
import '../core/romm/romm_service.dart';
import '../core/save/backup_repository.dart';
import '../core/save/catalog/play_preparer.dart';
import '../core/save/catalog/save_entry.dart';
import '../core/save/local_save_deletion.dart';
import '../core/save/resume_service.dart';
import '../core/save/save_sync_service.dart';
import '../profiles/json_file.dart';
import '../profiles/path_guard.dart';
import '../l10n/tr.dart';

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
      if (id is! int || romm == null) throw StateError(tr('RomM has no id for this save'));
      if (save.owner != null) throw StateError(tr('another player\'s save isn\'t yours to delete'));
      if (!await romm.deleteSaves([id])) throw StateError(tr('RomM refused'));
    case SaveSource.backup:
      final entry = save.backup;
      if (entry == null || backups == null) throw StateError(tr('the backup is gone'));
      await backups.removeEntry(game.id, entry);
      final zip = io.File(entry.localZipPath);
      if (zip.existsSync()) zip.deleteSync();
    case SaveSource.local:
      await deleteLocal();
  }
}

/// Gargosy (#94): this PC's save of the emulator that made [save], backed
/// up first (listed among the backups), then deleted as its strategy plans
/// it (`SaveStrategy.saveDeletionFor`: its files, its save folders, or its
/// saves taken off a card other games share) through the profile's
/// [guard], under the save lock. A card or a save folder is first copied
/// whole into [profileDir]'s `backups\deleted\<time>\`, so the other games'
/// saves on it can be put back by hand if anything went wrong. What can't be
/// deleted is refused with why, before anything is backed up.
Future<void> deleteLocalSave(
  Game game,
  String romPath,
  SaveEntry save, {
  required SaveSyncService sync,
  required PlayPreparer preparer,
  required PathGuard guard,
  required String profileDir,
  DateTime Function() now = DateTime.now,
}) async {
  final who = save.maker ?? (throw StateError(tr('it isn\'t known which emulator made this save')));
  final core = who.coreId == null ? null : '${who.coreId}_libretro';
  final planned = await sync.withStrategy(
    game,
    (s) => s.saveDeletionFor(game, romPath),
    emulatorId: who.emulatorId,
    coreOverride: core,
  );
  if (planned == null) throw StateError(tr('{0}\'s saves can\'t be deleted from here', [who.emulatorId]));
  for (final path in planned.paths) {
    guard.check(path);
  }
  await preparer.backUp(game, romPath, who);
  await sync.withStrategy(
    game,
    (s) async {
      final plan = await s.saveDeletionFor(game, romPath);
      await _keepCopies(plan, guard: guard, profileDir: profileDir, at: now());
      for (final f in plan.files) {
        await io.File(guard.check(f.path)).delete();
      }
      for (final d in plan.folders) {
        await io.Directory(guard.check(d.path)).delete(recursive: true);
      }
      for (final card in plan.cards.entries) {
        await writeBytesAtomic(guard, card.key, card.value);
      }
      await s.afterSaveDeleted(game, romPath);
    },
    emulatorId: who.emulatorId,
    coreOverride: core,
  );
  debugPrint("[Saves] ${game.displayName}: $who's save on this PC deleted (backed up first)");
}

/// Every card and save folder [plan] changes, copied whole into
/// `<profile>/backups/deleted/<time>/`, under its path in the profile.
Future<void> _keepCopies(
  LocalSaveDeletion plan, {
  required PathGuard guard,
  required String profileDir,
  required DateTime at,
}) async {
  final shared = plan.shared.toList();
  if (shared.isEmpty) return;
  final stamp = at.toIso8601String().replaceAll(RegExp(r'[^0-9T]'), '').substring(0, 15);
  final into = p.join(profileDir, 'backups', 'deleted', stamp);
  // Inside the profile as the guard compares (any case on Windows and macOS):
  // the part after the profile's folder, which p.relative would get wrong
  // when only the case differs.
  final profile = p.normalize(p.absolute(profileDir));
  String target(String path) => p.join(
    into,
    guard.isWithin(profile, path) ? p.normalize(p.absolute(path)).substring(profile.length + 1) : p.basename(path),
  );
  for (final path in shared) {
    if (io.FileSystemEntity.isDirectorySync(path)) {
      await for (final e in io.Directory(path).list(recursive: true)) {
        if (e is! io.File) continue;
        final to = io.File(guard.check(target(e.path)));
        await to.parent.create(recursive: true);
        await e.copy(to.path);
      }
    } else {
      final to = io.File(guard.check(target(path)));
      await to.parent.create(recursive: true);
      await io.File(path).copy(to.path);
    }
  }
  debugPrint('[Saves] ${shared.length} card(s) or save folder(s) copied to $into before the delete');
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
  if (entry.owner != null) throw StateError(tr('another player\'s state isn\'t yours to delete'));
  for (final f in resume.localFilesOf(entry)) {
    if (await f.exists()) await io.File(guard.check(f.path)).delete();
  }
  await resume.forgetState(game, entry.fileName);
  final id = entry.remoteId;
  if (id == null) return null;
  if (romm == null || romm.isOffline.value || !await romm.deleteStates([id])) {
    return entry.localFile == null
        ? tr('RomM can\'t be reached')
        : tr('it\'s deleted on this PC, but RomM can\'t be reached');
  }
  return null;
}
