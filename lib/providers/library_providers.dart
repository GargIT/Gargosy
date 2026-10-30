import 'dart:typed_data';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_snapshot.dart';
import '../library/home_layout.dart';
import '../library/platform_covers.dart';
import '../library/recent_searches.dart';
import 'engine_providers.dart';
import 'download_providers.dart';
import '../core/romm/romm_library_api.dart';
import '../core/romm/romm_models.dart';
import '../core/romm/romm_state.dart';
import '../profiles/profile_providers.dart';
import 'romm_providers.dart';
import '../l10n/tr.dart';

/// Platforms that have games, by name.
final platformsProvider = FutureProvider<List<Platform>>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return const [];
  final list = (await romm.getPlatforms()).where((p) => p.gamesCount > 0).toList()
    ..sort((a, b) => a.nameForDisplay.toLowerCase().compareTo(b.nameForDisplay.toLowerCase()));
  return list;
});

/// What a gallery's scope holds: how many games (versions folded, as the
/// gallery shows them) and the platforms they're on.
class GalleryScope {
  const GalleryScope({required this.total, required this.platforms});

  final int total;
  final List<Platform> platforms;
}

/// A collection's or a search's scope (#128, #132): its scope and search term
/// only, without the bar's filters. The platforms are RomM's filter values
/// for it, named from [platformsProvider].
final galleryScopeProvider = FutureProvider.autoDispose.family<GalleryScope, GalleryQuery>((ref, query) async {
  final api = ref.watch(libraryApiProvider);
  if (api == null) return const GalleryScope(total: 0, platforms: []);
  final scope = query.scopeOnly.withSearch(query.search);
  final page = await api.page(scope, limit: 1, withFilterValues: true, foldVersions: true);
  final ids = {...?page.filters?.platforms};
  return GalleryScope(
    total: page.total,
    platforms: [
      for (final p in await ref.watch(platformsProvider.future))
        if (ids.contains(p.id)) p,
    ],
  );
});

final collectionsProvider = FutureProvider<List<RommCollection>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  return api == null ? const [] : api.collections();
});

/// The smart collections the user can see; none from a RomM without them.
final smartCollectionsProvider = FutureProvider<List<RommCollection>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  return api == null ? const [] : _orNoneIfMissing(api.smartCollections());
});

/// RomM's virtual collections of one type (`virtualCollectionTypes`); none
/// from a RomM without them.
final virtualCollectionsProvider = FutureProvider.family<List<RommCollection>, String>((ref, type) async {
  final api = ref.watch(libraryApiProvider);
  return api == null ? const [] : _orNoneIfMissing(api.virtualCollections(type));
});

/// An older RomM answers 404 (or 422 for a type it doesn't know): nothing to show.
Future<List<RommCollection>> _orNoneIfMissing(Future<List<RommCollection>> call) async {
  try {
    return await call;
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    if (status == 404 || status == 422) return const [];
    rethrow;
  }
}

/// The collection, of any kind, whose games [q] is the gallery of, from the
/// lists loaded so far; null when none is.
RommCollection? collectionOf(WidgetRef ref, GalleryQuery q) {
  if (!q.inCollection) return null;
  final all = [
    ...?ref.watch(collectionsProvider).valueOrNull,
    ...?ref.watch(smartCollectionsProvider).valueOrNull,
    for (final type in virtualCollectionTypes.keys) ...?ref.watch(virtualCollectionsProvider(type)).valueOrNull,
  ];
  return all.where((c) => c.query == q.scopeOnly).firstOrNull;
}

/// The active profile's RomM user id.
final rommUserIdProvider = Provider<int?>(
  (ref) => ref.watch(activeProfileProvider.select((c) => c?.profile.rommUserId)),
);

/// Ids of the games in the user's own favourites.
final favouriteIdsProvider = Provider<Set<String>>((ref) {
  final userId = ref.watch(rommUserIdProvider);
  final collections = ref.watch(collectionsProvider).valueOrNull ?? const [];
  return {
    for (final c in collections)
      if (c.isFavorite && c.userId == userId)
        for (final id in c.romIds) '$id',
  };
});

// Home's shelves read through LibraryApi, which throws when RomM can't be
// reached (the copied RommService calls return [] instead), so Home can say so.
final recentlyPlayedProvider = FutureProvider<List<Game>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  if (api == null) return const [];
  final page = await api.page(
    const GalleryQuery(lastPlayedOnly: true, sort: GallerySort.lastPlayed, descending: true),
    limit: 20,
  );
  // Unrated games with Hide unrated (#224): RomM's filter leaves out only
  // the rated ones above the limit.
  return ref.watch(ageLimitProvider).only(page.games);
});

final recentlyAddedProvider = FutureProvider<List<Game>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  if (api == null) return const [];
  final page = await api.page(const GalleryQuery(sort: GallerySort.recentlyAdded, descending: true), limit: 20);
  return ref.watch(ageLimitProvider).only(page.games);
});

final favouriteGamesProvider = FutureProvider<List<Game>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  if (api == null) return const [];
  final page = await api.page(
    const GalleryQuery(favourites: true, sort: GallerySort.lastPlayed, descending: true),
    limit: 20,
  );
  return ref.watch(ageLimitProvider).only(page.games);
});

final randomGameProvider = FutureProvider<Game?>((ref) async => ref.watch(libraryApiProvider)?.randomGame());

/// Home's For you (#139): RomM's recommendations; none from an older RomM.
final recommendedGamesProvider = FutureProvider<List<Game>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  return api == null ? const [] : api.recommended();
});

/// The Overview's Similar games (#179); none offline or when RomM can't say.
final similarGamesProvider = FutureProvider.family<List<Game>, String>((ref, gameId) async {
  final api = ref.watch(libraryApiProvider);
  if (api == null) return const [];
  try {
    return await api.similar(gameId);
  } catch (_) {
    return const [];
  }
});

/// Home's On this day (#139): the games released on today's date in an
/// earlier year, and how many.
final onThisDayProvider = FutureProvider<GalleryPage>((ref) async {
  final api = ref.watch(libraryApiProvider);
  return api == null ? const GalleryPage(games: [], total: 0) : api.releasedOn(DateTime.now());
});

/// The profile's Home: what's at the top, its widgets and rows (#139).
final homeLayoutProvider = StateNotifierProvider<HomeLayoutNotifier, HomeLayout>(
  (ref) => HomeLayoutNotifier(ref.watch(profilePrefsProvider)),
);

final gameProvider = FutureProvider.family<Game?, String>((ref, id) async {
  final snap = ref.watch(librarySnapshotProvider);
  Game? game;
  try {
    game = await ref.watch(rommServiceProvider)?.getGame(id);
  } on Object {
    game = null;
  }
  if (game == null) return snap?.find(id); // RomM unreachable: as it was when downloaded
  if (snap != null && ref.read(romFilesProvider).isDownloaded(game)) await snap.remember(game);
  return game;
});

/// RomM's saves of a game, newest first. Throws when they can't be read.
final romSavesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return const [];
  final list = await romm.getSavesListOrNull(id);
  if (list == null) throw StateError(tr('RomM did not answer'));
  return list;
});

final romStatesProvider = FutureProvider.family<List<RommState>, String>((ref, id) async {
  final romm = ref.watch(rommServiceProvider);
  return romm == null ? const [] : romm.listStates(id);
});

final romNotesProvider = FutureProvider.family<List<RomNote>, String>((ref, id) async {
  final api = ref.watch(libraryApiProvider);
  return api == null ? const [] : api.notes(id);
});

/// RomM's RetroAchievements progress for the user, by RA game id.
final raProgressionProvider = FutureProvider<Map<int, Map<String, dynamic>>>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  return romm == null ? const {} : romm.getRetroAchievementsProgression();
});

String? coverUrlFor(WidgetRef ref, Game g, {bool small = false}) =>
    ref.read(rommServiceProvider)?.resolveCoverUrl(g, small: small);

/// A RomM player's avatar (#180), read once a session; null without one.
final userAvatarProvider = FutureProvider.family<Uint8List?, int>(
  (ref, userId) async => ref.watch(rommServiceProvider)?.userAvatar(userId),
);

/// [path] (e.g. `/assets/romm/...`) on the active profile's server.
String? assetUrl(WidgetRef ref, String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return path;
  final base = ref.read(rommServiceProvider)?.config.baseUrl;
  if (base == null) return null;
  return '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}$path';
}

/// Games whose favourite change is on its way to RomM; Y on them waits.
final favouriteBusyProvider = StateProvider<Set<String>>((ref) => const {});

/// Y on a game: add it to the user's favourites, or take it out. Returns why
/// it failed, or null. A second Y while the first is on its way does nothing.
Future<String?> toggleFavourite(WidgetRef ref, Game g) async {
  final api = ref.read(libraryApiProvider);
  final userId = ref.read(rommUserIdProvider);
  if (api == null || userId == null) return null;
  final busy = ref.read(favouriteBusyProvider.notifier);
  if (busy.state.contains(g.id)) return null;
  busy.state = {...busy.state, g.id};
  try {
    final isFav = ref.read(favouriteIdsProvider).contains(g.id);
    await api.setFavourite(g.id, !isFav, userId: userId);
    ref.invalidate(collectionsProvider);
    ref.invalidate(favouriteGamesProvider);
    return null;
  } on Object catch (e) {
    return tr('Couldn\'t update favourites: {0}', [e is Exception ? e.toString().replaceFirst('Exception: ', '') : e]);
  } finally {
    busy.state = {...busy.state}..remove(g.id);
  }
}

/// The Platforms page's Covers setting, per profile.
final platformCoversChoiceProvider = StateNotifierProvider<PlatformCoversChoice, PlatformCovers>(
  (ref) => PlatformCoversChoice(ref.watch(profilePrefsProvider)),
);

/// Whether the profile's RomM user may delete games (RomM's own permission:
/// an admin or editor); false offline.
final canDeleteGamesProvider = FutureProvider<bool>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  return romm != null && await romm.canDeleteGames();
});

/// Games deleted from RomM this session, left out of galleries already loaded.
final deletedGameIdsProvider = StateProvider<Set<String>>((ref) => const {});

/// Search's recent terms (#132), the profile's own.
final recentSearchesProvider = StateNotifierProvider<RecentSearches, List<String>>(
  (ref) => RecentSearches(ref.watch(profilePrefsProvider)),
);

/// One Random per run: Random covers change each time Gargosy starts, not each time the page opens.
final _coversRandom = Random();

/// A card's covers, once per platform and choice for the session; none when
/// RomM can't give them, and then tried again once RomM is back.
final platformCoversProvider = FutureProvider.family<List<Game>, PlatformCoversKey>((ref, key) async {
  final api = ref.watch(libraryApiProvider);
  if (api == null) return const [];
  var failed = false;
  ref.listen<bool>(rommOfflineProvider, (was, now) {
    if (failed && was == true && !now) ref.invalidateSelf();
  });
  try {
    return await coversFor(api, key.platform, key.choice, _coversRandom);
  } catch (_) {
    failed = true;
    return const [];
  }
});
