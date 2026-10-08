import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_providers.dart';

import '../helpers/fake_romm_auth.dart';
import '../helpers/profile_test_env.dart';

void main() {
  test('activate sets the context and remembers the profile; signOut clears it', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final prefs = MemoryPrefs();
    final c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root),
      appPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);
    final store = c.read(profileStoreProvider);
    final anna = await store.create(name: 'Anna', colorIndex: 0, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna');

    await c.read(activeProfileProvider.notifier).activate(anna, const ProfileLogin(token: 't', kind: 'device'));
    final ctx = c.read(activeProfileProvider)!;
    expect(ctx.profile.id, anna.id);
    expect(ctx.guard.activeProfileId, anna.id);
    expect(ctx.paths.dir, contains(anna.id));
    expect(store.lastUsedId, anna.id);

    c.read(activeProfileProvider.notifier).signOut();
    expect(c.read(activeProfileProvider), isNull);
  });

  test('opening a profile picks up an avatar added in RomM since, and shows it', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1]);
    final c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root),
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
      rommAuthFactoryProvider.overrideWithValue((url, trust) => FakeRommAuth(avatar: png)),
    ]);
    addTearDown(c.dispose);
    final anna = await c.read(profileStoreProvider)
        .create(name: 'Anna', colorIndex: 0, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna');
    expect(anna.hasAvatar, isFalse);

    final notifier = c.read(activeProfileProvider.notifier);
    await notifier.activate(anna, const ProfileLogin(token: 't', kind: 'device'));
    await notifier.avatarRefresh;
    expect(c.read(activeProfileProvider)!.profile.hasAvatar, isTrue);
    expect((await c.read(profileStoreProvider).list()).single.hasAvatar, isTrue);
  });
}
