import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';

import '../helpers/profile_test_env.dart';

void main() {
  test('no active profile, no RomM client; a profile gets one with its server and token', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root),
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
    ]);
    addTearDown(c.dispose);
    expect(c.read(rommServiceProvider), isNull);

    final anna = await c.read(profileStoreProvider).create(
        name: 'Anna', colorIndex: 0, serverUrl: 'https://romm.example', rommUserId: 7, rommUsername: 'anna');
    await c.read(activeProfileProvider.notifier).activate(anna, const ProfileLogin(token: 'rmm_t', kind: 'device'));
    final romm = c.read(rommServiceProvider)!;
    expect(romm.config.baseUrl, 'https://romm.example');
    expect(romm.authOptions.headers!['Authorization'], 'Bearer rmm_t');

    c.read(activeProfileProvider.notifier).signOut();
    expect(c.read(rommServiceProvider), isNull);
  });
}
