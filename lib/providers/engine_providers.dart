import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../core/emulator/game_launch_service.dart';
import '../core/emulator/strategy_registry.dart';
import '../core/save/backup_repository.dart';
import '../core/save/backup_service.dart';
import '../core/save/save_sync_service.dart';
import '../emulators/profile_directories.dart';
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
  return paths == null ? null : ProfilePreferences.open(paths);
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

final strategyRegistryProvider = Provider<StrategyRegistry?>((ref) {
  final dirs = ref.watch(launchDirectoriesProvider);
  final prefs = ref.watch(profilePrefsProvider);
  return dirs == null || prefs == null ? null : StrategyRegistry(dirs, prefs);
});

final saveSyncServiceProvider = Provider<SaveSyncService?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  final dirs = ref.watch(saveDirectoriesProvider);
  final registry = ref.watch(strategyRegistryProvider);
  final prefs = ref.watch(profilePrefsProvider);
  final paths = ref.watch(_profilePathsProvider);
  if (romm == null || dirs == null || registry == null || prefs == null || paths == null) return null;
  return SaveSyncService(romm, dirs, registry, prefs, platform: sandboxedPlatform(paths));
});

final backupRepositoryProvider = FutureProvider<BackupRepository?>((ref) async {
  final paths = ref.watch(_profilePathsProvider);
  if (paths == null) return null;
  final name = 'backups_${paths.id.replaceAll('-', '_')}';
  final box = await Hive.openBox<List>(name, path: paths.dir);
  ref.onDispose(box.close);
  return BackupRepository(boxName: name)..initBox();
});

final backupServiceProvider = Provider<BackupService?>((ref) {
  final paths = ref.watch(_profilePathsProvider);
  return paths == null ? null : BackupService(backupsDir: () async => paths.backups);
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
  );
});
