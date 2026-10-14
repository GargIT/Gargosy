import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../sigil/sigil_profile.dart';
import '../core/emulator/game_launch_service.dart';
import '../core/emulator/strategy_registry.dart';
import '../core/save/backup_repository.dart';
import '../core/save/backup_service.dart';
import '../core/save/resume_service.dart';
import '../core/save/save_sync_service.dart';
import '../core/save/state_sync_service.dart';
import '../emulators/profile_directories.dart';
import '../profiles/backups_index.dart';
import '../profiles/profile_paths.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_providers.dart';
import 'romm_providers.dart';

/// Freegosy's save and launch engine, built for the active profile: its own
/// settings, folders, backups and RomM account (spec §4). Null without one.
final _profilePathsProvider = Provider<ProfilePaths?>((ref) {
  final id = ref.watch(activeProfileProvider.select((c) => c?.profile.id));
  return id == null ? null : ProfilePaths(ref.watch(appRootProvider), id);
});

final profilePrefsProvider = Provider<ProfilePreferences?>((ref) {
  final paths = ref.watch(_profilePathsProvider);
  if (paths == null) return null;
  final prefs = ProfilePreferences.open(paths);
  // The old per-emulator state-sync switches become the one (state-sync plan S0.4).
  migrateStateSyncPref(prefs).catchError((Object e) => debugPrint('[StateSync] switch migration failed: $e'));
  return prefs;
});

final saveDirectoriesProvider = Provider<ProfileSaveDirectories?>((ref) {
  final paths = ref.watch(_profilePathsProvider);
  final prefs = ref.watch(profilePrefsProvider);
  if (paths == null || prefs == null) return null;
  return ProfileSaveDirectories(root: ref.watch(appRootProvider), paths: paths, prefs: prefs);
});

final launchDirectoriesProvider = Provider<ProfileLaunchDirectories?>((ref) {
  final paths = ref.watch(_profilePathsProvider);
  final prefs = ref.watch(profilePrefsProvider);
  if (paths == null || prefs == null) return null;
  return ProfileLaunchDirectories(root: ref.watch(appRootProvider), paths: paths, prefs: prefs);
});

/// The emulator strategies, seeing the profile's folders as Windows' user
/// folders (as the save code does): no copied code can reach the PC's own
/// Documents or AppData.
final strategyRegistryProvider = Provider<StrategyRegistry?>((ref) {
  final dirs = ref.watch(launchDirectoriesProvider);
  final prefs = ref.watch(profilePrefsProvider);
  final paths = ref.watch(_profilePathsProvider);
  return dirs == null || prefs == null || paths == null
      ? null
      : StrategyRegistry(dirs, prefs, platform: sandboxedPlatform(paths));
});

final saveSyncServiceProvider = Provider<SaveSyncService?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  final dirs = ref.watch(saveDirectoriesProvider);
  final registry = ref.watch(strategyRegistryProvider);
  final prefs = ref.watch(profilePrefsProvider);
  final paths = ref.watch(_profilePathsProvider);
  if (romm == null || dirs == null || registry == null || prefs == null || paths == null) return null;
  return SaveSyncService(
    romm,
    dirs,
    registry,
    prefs,
    platform: sandboxedPlatform(paths),
    wrapSaves: sigilSavesFor(paths),
  );
});

/// What the profile's save sync is busy with ("Uploading Okami's save"),
/// null when idle.
final syncActivityProvider = Provider<ValueListenable<String?>?>((ref) => ref.watch(saveSyncServiceProvider)?.activity);

final backupRepositoryProvider = FutureProvider<BackupRepository?>((ref) async {
  final paths = ref.watch(_profilePathsProvider);
  if (paths == null) return null;
  final name = backupsBoxName(paths.id);
  moveBackupsIndex(paths);
  final box = await Hive.openBox<List>(name, path: paths.backups);
  ref.onDispose(box.close);
  return BackupRepository(boxName: name)..initBox();
});

final backupServiceProvider = Provider<BackupService?>((ref) {
  final paths = ref.watch(_profilePathsProvider);
  return paths == null ? null : BackupService(backupsDir: () async => paths.backups);
});

/// Save states on the profile's RomM account (one switch in Settings → Emulator settings).
final stateSyncServiceProvider = Provider<StateSyncService?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  final sync = ref.watch(saveSyncServiceProvider);
  final prefs = ref.watch(profilePrefsProvider);
  if (romm == null || sync == null || prefs == null) return null;
  return StateSyncService(
    romm,
    prefs,
    sync.strategyForGame,
    exclusive: <T>(Future<T> Function() body) => sync.exclusive(body, doing: 'Syncing save states'),
    emulatorSyncs: (id) => ref.read(strategyRegistryProvider)?.getStrategyById(id)?.supportsStateSync ?? false,
  );
});

/// The states a game can be resumed from (this PC and RomM).
final resumeServiceProvider = Provider<ResumeService?>((ref) {
  final registry = ref.watch(strategyRegistryProvider);
  final sync = ref.watch(saveSyncServiceProvider);
  final prefs = ref.watch(profilePrefsProvider);
  if (registry == null || sync == null || prefs == null) return null;
  final romm = ref.watch(rommServiceProvider);
  return ResumeService(
    emulatorsFor: registry.getAllStrategiesForSlug,
    resolveSaveStrategy: sync.strategyForGame,
    exclusive: sync.exclusive,
    prefs: prefs,
    api: romm,
    isOffline: () => romm?.isOffline.value == true,
  );
});

final gameLaunchServiceProvider = FutureProvider<GameLaunchService?>((ref) async {
  final dirs = ref.watch(launchDirectoriesProvider);
  final registry = ref.watch(strategyRegistryProvider);
  final sync = ref.watch(saveSyncServiceProvider);
  final backups = ref.watch(backupServiceProvider);
  final prefs = ref.watch(profilePrefsProvider);
  final repo = await ref.watch(backupRepositoryProvider.future);
  if (dirs == null || registry == null || sync == null || backups == null || prefs == null || repo == null) return null;
  return GameLaunchService(
    directoryService: dirs,
    strategyRegistry: registry,
    saveSyncService: sync,
    backupService: backups,
    backupRepository: repo,
    prefs: prefs,
    rommService: ref.watch(rommServiceProvider),
    stateSyncService: ref.watch(stateSyncServiceProvider),
  );
});
