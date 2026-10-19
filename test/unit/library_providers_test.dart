import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/library_providers.dart';

import '../helpers/profile_test_env.dart';

void main() {
  test('favourite ids are the user\'s own favourites collection only', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final c = ProviderContainer(
      overrides: [
        appRootProvider.overrideWithValue(root),
        appPreferencesProvider.overrideWithValue(MemoryPrefs()),
        collectionsProvider.overrideWith(
          (ref) async => const [
            RommCollection(id: 1, name: 'Favorites', isFavorite: true, userId: 7, romIds: {4, 5}),
            RommCollection(id: 2, name: 'Favorites', isFavorite: true, userId: 8, romIds: {9}),
            RommCollection(id: 3, name: 'RPGs', userId: 7, romIds: {6}),
          ],
        ),
      ],
    );
    addTearDown(c.dispose);
    final anna = await c
        .read(profileStoreProvider)
        .create(name: 'Anna', colorIndex: 0, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna');
    await c.read(activeProfileProvider.notifier).activate(anna, const ProfileLogin(token: 't', kind: 'device'));
    await c.read(collectionsProvider.future);
    expect(c.read(favouriteIdsProvider), {'4', '5'});
  });
}
