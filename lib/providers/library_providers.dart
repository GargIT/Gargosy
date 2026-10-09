import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_snapshot.dart';
import 'download_providers.dart';
import '../core/romm/romm_library_api.dart';
import '../core/romm/romm_models.dart';
import '../core/romm/romm_state.dart';
import '../profiles/profile_providers.dart';
import 'romm_providers.dart';

/// Platforms that have games, by name.
final platformsProvider = FutureProvider<List<Platform>>((ref) async {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return const [];
  final list = (await romm.getPlatforms()).where((p) => p.gamesCount > 0).toList()
    ..sort((a, b) => a.nameForDisplay.toLowerCase().compareTo(b.nameForDisplay.toLowerCase()));
  return list;
});

final collectionsProvider = FutureProvider<List<RommCollection>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  return api == null ? const [] : api.collections();
});

/// The active profile's RomM user id.
final rommUserIdProvider = Provider<int?>((ref) => ref.watch(activeProfileProvider.select((c) => c?.profile.rommUserId)));

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
  final page = await api.page(const GalleryQuery(lastPlayedOnly: true, sort: GallerySort.lastPlayed, descending: true), limit: 20);
  return page.games;
});

final recentlyAddedProvider = FutureProvider<List<Game>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  if (api == null) return const [];
  return (await api.page(const GalleryQuery(sort: GallerySort.recentlyAdded, descending: true), limit: 20)).games;
});

final favouriteGamesProvider = FutureProvider<List<Game>>((ref) async {
  final api = ref.watch(libraryApiProvider);
  if (api == null) return const [];
  final page = await api.page(const GalleryQuery(favourites: true, sort: GallerySort.lastPlayed, descending: true), limit: 20);
  return page.games;
});

final randomGameProvider = FutureProvider<Game?>((ref) async => ref.watch(libraryApiProvider)?.randomGame());

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
  if (list == null) throw StateError('RomM did not answer');
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

String? coverUrlFor(WidgetRef ref, Game g) => ref.read(rommServiceProvider)?.resolveCoverUrl(g);

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
    return "Couldn't update favourites: ${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}";
  } finally {
    busy.state = {...busy.state}..remove(g.id);
  }
}
