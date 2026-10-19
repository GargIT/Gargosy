import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_models.dart';
import '../core/save/backup_entry.dart';
import '../play/play_engine.dart';
import '../providers/engine_providers.dart';
import '../providers/romm_providers.dart';

/// The profile's saves that didn't reach RomM (played offline, or the
/// upload failed): every session's backup that RomM didn't answer is
/// waiting here (spec §8). A run uploads, for each game, the save as it is
/// now, through the normal push, oldest game first. A game that fails keeps
/// waiting without holding up the others; the run stops only when RomM
/// can't be reached.
class UploadQueue {
  UploadQueue({
    required this.isOffline,
    required this.pending,
    required this.markSynced,
    required this.gameById,
    required this.romPathFor,
    required this.push,
  });

  /// RomM can't be reached (its heartbeat).
  final bool Function() isOffline;
  final List<({String romId, BackupEntry entry})> Function() pending;
  final Future<void> Function(String romId, BackupEntry entry) markSynced;

  /// Null when RomM can't be reached.
  final Future<Game?> Function(String id) gameById;

  /// Null when the game isn't on this PC any more.
  final Future<String?> Function(Game game) romPathFor;

  /// Uploads [game]'s save; [newest] is its newest waiting session (which
  /// emulator made it). True when RomM took it.
  final Future<bool> Function(Game game, String romPath, BackupEntry newest) push;

  /// True while a run goes on (a profile switch waits for it).
  final ValueNotifier<bool> running = ValueNotifier(false);

  /// [gameId]'s save just reached RomM in a session: what waited for it is
  /// older, and must never be pushed over it.
  Future<void> settle(String gameId) async {
    for (final w in pending()) {
      if (w.romId == gameId) await markSynced(w.romId, w.entry);
    }
  }

  /// What waits for [gameId].
  List<BackupEntry> waitingFor(String gameId) => [
    for (final w in pending())
      if (w.romId == gameId) w.entry,
  ];

  /// Uploads what waits; returns how many games went up. A run already
  /// going makes this one do nothing.
  Future<int> run() async {
    if (running.value) return 0;
    running.value = true;
    var done = 0;
    try {
      final byGame = <String, List<BackupEntry>>{};
      for (final w in pending()) {
        (byGame[w.romId] ??= []).add(w.entry);
      }
      final order = byGame.entries.toList()
        ..forEach((e) => e.value.sort((a, b) => b.timestamp.compareTo(a.timestamp)))
        ..sort((a, b) => a.value.first.timestamp.compareTo(b.value.first.timestamp));
      for (final e in order) {
        if (isOffline()) break;
        try {
          final game = await gameById(e.key);
          if (game == null) {
            if (isOffline()) break;
            continue; // gone from RomM: it keeps waiting, the rest go up
          }
          final romPath = await romPathFor(game);
          if (romPath == null) continue; // deleted from this PC: nothing to upload
          if (!await push(game, romPath, e.value.first)) continue;
          for (final entry in e.value) {
            await markSynced(e.key, entry);
          }
          done++;
        } on Object {
          // this game keeps waiting (a conflict, a blocked sync, …); the next goes on
        }
      }
    } finally {
      running.value = false;
    }
    return done;
  }
}

/// The active profile's queue; null without a profile.
final uploadQueueProvider = FutureProvider<UploadQueue?>((ref) async {
  final repo = await ref.watch(backupRepositoryProvider.future);
  final sync = ref.watch(saveSyncServiceProvider);
  final romm = ref.watch(rommServiceProvider);
  final engine = ref.watch(playEngineProvider);
  if (repo == null || sync == null || romm == null || engine == null) return null;
  return UploadQueue(
    isOffline: () => romm.isOffline.value,
    pending: repo.getUnsyncedEntries,
    markSynced: repo.markAsSynced,
    gameById: romm.getGame,
    romPathFor: engine.romPathFor,
    push: (game, romPath, newest) => sync.pushSaves(
      game,
      romPath,
      emulatorId: newest.emulatorId,
      coreOverride: newest.coreId == null ? null : '${newest.coreId}_libretro',
    ),
  );
});

/// What waits to upload for a game (shown on its Save Data tab).
final uploadsWaitingProvider = Provider.family<List<BackupEntry>, String>((ref, gameId) {
  ref.watch(uploadQueueVersionProvider);
  return ref.watch(uploadQueueProvider).valueOrNull?.waitingFor(gameId) ?? const [];
});

/// Bumped after a run or a session, so the waiting lists are read again.
final uploadQueueVersionProvider = StateProvider<int>((ref) => 0);
