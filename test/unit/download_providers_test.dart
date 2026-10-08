import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/download_providers.dart';

import '../helpers/fake_download_service.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  test('switching profile cancels the old profile\'s downloads and forgets their progress', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final fake = FakeDownloadService(RomFiles(root), PathGuard(root))..hold = Completer<void>();
    final c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root),
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
      downloadServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    final store = c.read(profileStoreProvider);
    final anna = await store.create(name: 'Anna', colorIndex: 0, serverUrl: 'https://a', rommUserId: 7, rommUsername: 'anna');
    final bob = await store.create(name: 'Bob', colorIndex: 0, serverUrl: 'https://b', rommUserId: 8, rommUsername: 'bob');
    await c.read(activeProfileProvider.notifier).activate(anna, const ProfileLogin(token: 'a', kind: 'device'));

    final sub = c.listen(downloadsProvider, (_, _) {});
    addTearDown(sub.close);
    final running = c.read(downloadsProvider.notifier).start(game(7564, 'Burnout 3'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(downloadsProvider).keys, ['7564']);

    await c.read(activeProfileProvider.notifier).activate(bob, const ProfileLogin(token: 'b', kind: 'device'));
    await running;
    expect(c.read(downloadsProvider), isEmpty);
    expect(RomFiles(root).isDownloaded(game(7564, 'Burnout 3')), isFalse);
  });
}
