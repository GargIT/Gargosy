import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/platform_covers.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

Platform _p(int count) =>
    Platform.fromJson({'id': 3, 'name': 'PS2', 'slug': 'ps2', 'fs_slug': 'ps2', 'display_name': 'PS2', 'rom_count': count});

void main() {
  final games = [for (var i = 1; i <= 60; i++) Game.fromJson(gameJson(i, 'Game $i'))];

  test('Top rated: rating, highest first, five, for that platform', () async {
    final api = FakeLibraryApi(games);
    final got = await coversFor(api, _p(60), PlatformCovers.topRated, Random(1));
    expect(got, hasLength(5));
    final (q, offset) = api.queries.single;
    expect((q.platformId, q.sort, q.descending, offset), (3, GallerySort.rating, true, 0));
  });

  test('Recently added: newest first', () async {
    final api = FakeLibraryApi(games);
    await coversFor(api, _p(60), PlatformCovers.recentlyAdded, Random(1));
    expect((api.queries.single.$1.sort, api.queries.single.$1.descending), (GallerySort.recentlyAdded, true));
  });

  test('Random: five different games from a page at an offset inside the platform', () async {
    final api = FakeLibraryApi(games);
    final got = await coversFor(api, _p(60), PlatformCovers.random, Random(7));
    expect(got.map((g) => g.id).toSet(), hasLength(5));
    expect(api.queries.single.$2, inInclusiveRange(0, 20)); // 60 games, pages of 40
  });

  test('Random on a small platform starts at 0 and shows what there is', () async {
    final api = FakeLibraryApi(games.take(3).toList());
    final got = await coversFor(api, _p(3), PlatformCovers.random, Random(7));
    expect(api.queries.single.$2, 0);
    expect(got, hasLength(3));
  });

  test('Last played: played games first, filled up with top rated, no game twice', () async {
    final api = _LastPlayedApi(played: games.take(2).toList(), all: games);
    final got = await coversFor(api, _p(60), PlatformCovers.lastPlayed, Random(1));
    expect(got.take(2).map((g) => g.id), ['1', '2']);
    expect(got, hasLength(5));
    expect(got.map((g) => g.id).toSet(), hasLength(5));
    expect(api.queries.first.$1.lastPlayedOnly, isTrue);
  });

  test('Last played with nothing played is top rated', () async {
    final api = _LastPlayedApi(played: const [], all: games);
    final got = await coversFor(api, _p(60), PlatformCovers.lastPlayed, Random(1));
    expect(got, hasLength(5));
    expect(api.queries.last.$1.sort, GallerySort.rating);
  });

  test("Logo only: no games, and RomM isn't asked", () async {
    final api = FakeLibraryApi(games);
    expect(await coversFor(api, _p(60), PlatformCovers.logoOnly, Random(1)), isEmpty);
    expect(api.queries, isEmpty);
    expect(PlatformCovers.logoOnly.label, 'Logo only');
  });

  test('the choice is kept per profile; Top rated until picked', () async {
    final prefs = MemoryPrefs();
    final a = PlatformCoversChoice(prefs);
    expect(a.state, PlatformCovers.topRated);
    await a.pick(PlatformCovers.random);
    expect(PlatformCoversChoice(prefs).state, PlatformCovers.random);
    expect(PlatformCoversChoice(null).state, PlatformCovers.topRated);
  });

  test('the cache key is one platform (by id) and one choice', () {
    expect(PlatformCoversKey(_p(60), PlatformCovers.random), PlatformCoversKey(_p(61), PlatformCovers.random));
    expect(PlatformCoversKey(_p(60), PlatformCovers.random), isNot(PlatformCoversKey(_p(60), PlatformCovers.topRated)));
  });

  group('the session cache', () {
    late FakeLibraryApi api;
    late ProviderContainer c;
    final offline = StateProvider<bool>((ref) => false);
    final key = PlatformCoversKey(_p(60), PlatformCovers.topRated);

    setUp(() {
      api = FakeLibraryApi(games);
      c = ProviderContainer(overrides: [
        libraryApiProvider.overrideWithValue(api),
        rommOfflineProvider.overrideWith((ref) => ref.watch(offline)),
      ]);
      addTearDown(c.dispose);
    });

    test('a failed fetch is tried again when RomM is back', () async {
      api.failWith = Exception('SocketException: timed out');
      c.listen(platformCoversProvider(key), (_, _) {});
      expect(await c.read(platformCoversProvider(key).future), isEmpty);
      api.failWith = null;
      c.read(offline.notifier).state = true;
      await Future<void>.delayed(Duration.zero); // the heartbeat is seconds apart
      c.read(offline.notifier).state = false;
      await Future<void>.delayed(Duration.zero);
      expect(await c.read(platformCoversProvider(key).future), hasLength(5));
    });

    test("covers that loaded aren't fetched again when RomM comes back (Random stays put)", () async {
      c.listen(platformCoversProvider(key), (_, _) {});
      await c.read(platformCoversProvider(key).future);
      c.read(offline.notifier).state = true;
      await Future<void>.delayed(Duration.zero); // the heartbeat is seconds apart
      c.read(offline.notifier).state = false;
      await Future<void>.delayed(Duration.zero);
      await c.read(platformCoversProvider(key).future);
      expect(api.queries, hasLength(1));
    });
  });
}

/// Returns [played] for last-played queries, else the whole library.
class _LastPlayedApi extends FakeLibraryApi {
  _LastPlayedApi({required this.played, required List<Game> all}) : super(all);
  final List<Game> played;

  @override
  Future<GalleryPage> page(GalleryQuery q,
      {int offset = 0, int limit = RommLibraryApi.pageSize, bool withFilterValues = false}) {
    if (!q.lastPlayedOnly) return super.page(q, offset: offset, limit: limit);
    queries.add((q, offset));
    return Future.value(GalleryPage(games: played.take(limit).toList(), total: played.length));
  }

}
