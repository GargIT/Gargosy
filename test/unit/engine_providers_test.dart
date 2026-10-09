import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/engine_providers.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  setUpAll(() {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(BackupEntryAdapter());
  });

  test('every engine part belongs to the active profile', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root),
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
    ]);
    addTearDown(c.dispose);
    expect(c.read(saveSyncServiceProvider), isNull);

    final anna = await c.read(profileStoreProvider).create(name: 'Anna', colorIndex: 0, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna');
    await c.read(activeProfileProvider.notifier).activate(anna, const ProfileLogin(token: 't', kind: 'device'));
    final paths = ProfilePaths(root, anna.id);

    // A new profile: Gargosy makes PCSX2's folders before the first save goes in.
    EmulatorLayout.of('pcsx2').ensureFolders(paths.emulatorDir('pcsx2'));
    final sync = c.read(saveSyncServiceProvider)!;
    final pcsx2 = sync.getStrategyForGame(game(1, 'G', platform: 'ps2'), emulatorId: 'pcsx2');
    expect(pcsx2, isNotNull);
    final dir = await pcsx2!.getSaveDir(game(1, 'G', platform: 'ps2'), p.join(root.roms, 'ps2', 'G.chd'));
    expect(p.isWithin(paths.emulatorsDir, dir!), isTrue, reason: dir);

    final repo = await c.read(backupRepositoryProvider.future);
    expect(repo, isNotNull);
    expect(io.Directory(paths.dir).listSync().any((e) => p.basename(e.path).startsWith('backups_')), isTrue);

    final launch = await c.read(gameLaunchServiceProvider.future);
    expect(launch, isNotNull);
    // Save states sync through the same profile's RomM account and prefs.
    expect(c.read(stateSyncServiceProvider), isNotNull);
    expect(launch!.stateSyncService, same(c.read(stateSyncServiceProvider)));
    expect(c.read(resumeServiceProvider), isNotNull);
    expect(c.read(strategyRegistryProvider)!.getStrategyForSlug('ps2')?.emulatorId, isNotNull);

    c.read(activeProfileProvider.notifier).signOut();
    expect(c.read(saveSyncServiceProvider), isNull);
  });
}
