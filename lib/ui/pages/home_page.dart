import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_models.dart';
import '../../library/library_snapshot.dart';
import '../../providers/romm_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/library_providers.dart';
import '../screens/game/open_game.dart';
import '../theme/tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/error_retry.dart';
import '../widgets/g_focusable.dart';
import '../widgets/shelf.dart';
import '../widgets/favourite.dart';

/// Home, after v2's: a random pick, then rows of games.
class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final played = ref.watch(recentlyPlayedProvider);
    final added = ref.watch(recentlyAddedProvider);
    final favourites = ref.watch(favouriteGamesProvider);
    final random = ref.watch(randomGameProvider).valueOrNull;
    final favIds = ref.watch(favouriteIdsProvider);
    final offline = ref.watch(rommOfflineProvider);
    final installed = ref.watch(gamesOnThisPcProvider);
    final loading = played.isLoading || added.isLoading;
    final error = played.error ?? added.error;

    Widget shelf(String title, List<Game> games, {bool first = false}) => Shelf(
      title: title,
      games: games,
      coverUrl: (g) => coverUrlFor(ref, g, small: true),
      onOpen: (g) => openGame(context, g),
      onFavorite: (g) => favourite(context, ref, g),
      isFavourite: (g) => favIds.contains(g.id),
      isDownloaded: (g) => watchDownloaded(ref, g),
      autofocusFirst: first,
    );

    final playedList = played.valueOrNull ?? const <Game>[];
    final addedList = added.valueOrNull ?? const <Game>[];
    final favList = favourites.valueOrNull ?? const <Game>[];
    final empty =
        !loading &&
        error == null &&
        playedList.isEmpty &&
        installed.isEmpty &&
        addedList.isEmpty &&
        favList.isEmpty &&
        random == null;

    return ListView(
      key: const Key('page-Home'),
      padding: const EdgeInsets.only(top: GLayout.navHeight + GSpace.s6, bottom: GSpace.s14),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad),
          child: Text(
            'Welcome, $name',
            style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800),
          ),
        ),
        // RomM unreachable: what's on this PC still plays (spec §8), first.
        if (offline) shelf('Installed games', installed, first: true),
        if (loading) const Padding(padding: EdgeInsets.all(GSpace.rowPad), child: LinearProgressIndicator()),
        if (error != null)
          SizedBox(
            height: 260,
            child: ErrorRetry(
              message: describeLoadError(error),
              onRetry: () {
                ref.invalidate(recentlyPlayedProvider);
                ref.invalidate(recentlyAddedProvider);
                ref.invalidate(favouriteGamesProvider);
                ref.invalidate(randomGameProvider);
              },
            ),
          ),
        if (empty)
          const Padding(
            padding: EdgeInsets.all(GSpace.rowPad),
            child: Text(
              'No games yet. Add some to RomM and they show up here.',
              style: TextStyle(fontSize: GFont.lg, color: GColors.fgMuted),
            ),
          ),
        if (random != null) _RandomPick(game: random, autofocus: playedList.isEmpty),
        shelf('Continue playing', playedList, first: !offline),
        if (!offline) shelf('Installed games', installed),
        shelf('Recently added', addedList),
        shelf('Favourites', favList),
      ],
    );
  }
}

class _RandomPick extends ConsumerWidget {
  const _RandomPick({required this.game, this.autofocus = false});

  final Game game;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s6, GSpace.rowPad, 0),
      child: GFocusable(
        autofocus: autofocus,
        onActivate: () => openGame(context, game),
        child: Container(
          height: 169,
          decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.card)),
          child: Row(
            children: [
              CoverImage(url: coverUrlFor(ref, game, small: true), title: game.displayName, width: 126, height: 169),
              const SizedBox(width: GSpace.s5),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RANDOM PICK',
                      style: TextStyle(fontSize: GFont.xs, letterSpacing: 1.5, color: GColors.accent),
                    ),
                    const SizedBox(height: GSpace.s1),
                    Text(
                      game.displayName,
                      style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w800),
                    ),
                    Text(game.platformDisplayName ?? '', style: const TextStyle(color: GColors.fgSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
