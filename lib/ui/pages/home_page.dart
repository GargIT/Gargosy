import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/romm/romm_models.dart';
import '../../library/collection_list.dart';
import '../../library/home_layout.dart';
import '../../library/library_snapshot.dart';
import '../../providers/download_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/romm_providers.dart';
import '../../providers/ui_provider.dart';
import '../input/gargosy_intents.dart';
import '../screens/collection/collection_screen.dart';
import '../screens/gallery_screen.dart';
import '../screens/game/open_game.dart';
import '../screens/platform/platform_screen.dart';
import '../shell/shell_menu.dart';
import '../theme/tokens.dart';
import '../widgets/collection_tile.dart';
import '../widgets/error_retry.dart';
import '../widgets/favourite.dart';
import '../widgets/g_focusable.dart';
import '../widgets/game_card.dart';
import '../widgets/shelf.dart';
import 'home/customize_home.dart';
import 'home/home_header.dart';
import 'home/home_widgets.dart';
import 'platform_card.dart';

/// Home (#139), after RomM v2's: the game played last (or a random pick) over
/// its art, the widgets, then the rows the profile chose, in its order
/// ([homeLayoutProvider]); Customize Home at the end. While RomM is offline:
/// the last game played on this PC, On this PC first, and no rows that need
/// RomM.
class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.name});

  final String name;

  static const _platformWidth = 280.0;

  /// The downloaded games played on this PC, last played first (offline).
  static List<Game> playedHere(List<Game> installed) => [
    for (final g in installed)
      if (g.lastPlayed != null) g,
  ]..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    final offline = ref.watch(rommOfflineProvider);
    final installed = ref.watch(gamesOnThisPcProvider);
    final played = ref.watch(recentlyPlayedProvider);
    final favIds = ref.watch(favouriteIdsProvider);
    final userId = ref.watch(rommUserIdProvider);
    final showRows = offline ? const [HomeRow.onThisPc, HomeRow.continuePlaying] : layout.shown;
    final random = layout.top == HomeTop.randomPick || layout.widgets.contains(HomeWidget.randomPick)
        ? ref.watch(randomGameProvider).valueOrNull
        : null;

    final playedList = offline ? playedHere(installed) : played.valueOrNull ?? const <Game>[];
    final last = playedList.firstOrNull;
    final (Game? headerGame, bool headerRandom) = switch (layout.top) {
      HomeTop.nothing => (null, false),
      HomeTop.randomPick when !offline && random != null => (random, true),
      // Nothing played yet: the random pick instead.
      _ when last != null => (last, false),
      _ when !offline && random != null => (random, true),
      _ => (null, false),
    };

    Widget gameShelf(HomeRow row, List<Game> games, {int? count, VoidCallback? onSeeAll}) => Shelf(
      key: ValueKey('home-${row.name}'),
      title: row.label,
      count: count,
      itemCount: games.length,
      onSeeAll: onSeeAll,
      itemBuilder: (context, i) => GameCard(
        game: games[i],
        coverUrl: coverUrlFor(ref, games[i], small: true),
        favourite: favIds.contains(games[i].id),
        downloaded: watchDownloaded(ref, games[i]),
        onOpen: () => openGame(context, games[i]),
        onFavorite: () => favourite(context, ref, games[i]),
      ),
    );

    void gallery(String title, GalleryQuery q, {bool thisPc = false}) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GalleryScreen(title: title, query: q, thisPc: thisPc),
      ),
    );
    void tab(String name) => ref.read(shellTabProvider.notifier).state = shellTabs.indexOf(name);

    Widget collectionShelf(HomeRow row, List<RommCollection> list) {
      final onPc = {for (final g in installed) ?int.tryParse(g.id)};
      return Shelf(
        key: ValueKey('home-${row.name}'),
        title: row.label,
        count: list.length,
        itemCount: list.length,
        height: GameCard.width / CollectionTile.coverAspect + 48,
        seeAllSize: Size(GameCard.width, GameCard.width / CollectionTile.coverAspect),
        onSeeAll: () => tab('Collections'),
        itemBuilder: (context, i) {
          final c = list[i];
          return SizedBox(
            width: GameCard.width,
            child: CollectionTile(
              collection: c,
              coverUrls: [for (final path in c.coverPaths.take(4)) assetUrl(ref, path)],
              line: '${c.romCount} ${c.romCount == 1 ? 'game' : 'games'}',
              onPc: onThisPc(c, onPc),
              onOpen: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CollectionScreen(collection: c))),
              onRandom: () async {
                final game = await ref.read(libraryApiProvider)?.randomGame(within: c.query);
                if (game != null && context.mounted) await openGame(context, game);
              },
            ),
          );
        },
      );
    }

    Widget rowOf(HomeRow row) {
      switch (row) {
        case HomeRow.continuePlaying:
          // The header's game isn't repeated first in the row.
          final rest = headerGame != null && !headerRandom ? playedList.skip(1).toList() : playedList;
          return gameShelf(
            row,
            rest,
            onSeeAll: offline
                ? null
                : () => gallery(
                    'Continue playing',
                    const GalleryQuery(lastPlayedOnly: true, sort: GallerySort.lastPlayed, descending: true),
                  ),
          );
        case HomeRow.recentlyAdded:
          return gameShelf(
            row,
            ref.watch(recentlyAddedProvider).valueOrNull ?? const [],
            onSeeAll: () =>
                gallery('Recently added', const GalleryQuery(sort: GallerySort.recentlyAdded, descending: true)),
          );
        case HomeRow.favourites:
          return gameShelf(
            row,
            ref.watch(favouriteGamesProvider).valueOrNull ?? const [],
            count: favIds.length,
            onSeeAll: () => gallery('Favourites', const GalleryQuery(favourites: true)),
          );
        case HomeRow.onThisPc:
          return gameShelf(
            row,
            installed.take(20).toList(),
            count: installed.length,
            onSeeAll: offline ? null : () => gallery('On this PC', const GalleryQuery(), thisPc: true),
          );
        case HomeRow.forYou:
          return gameShelf(row, ref.watch(recommendedGamesProvider).valueOrNull ?? const []);
        case HomeRow.platforms:
          final list = ref.watch(platformsProvider).valueOrNull ?? const <Platform>[];
          return Shelf(
            key: ValueKey('home-${row.name}'),
            title: row.label,
            count: list.length,
            itemCount: list.length,
            height: PlatformCard.height,
            seeAllSize: const Size(GameCard.width, PlatformCard.height),
            onSeeAll: () => tab('Platforms'),
            itemBuilder: (context, i) => SizedBox(
              width: _platformWidth,
              child: PlatformCard(
                platform: list[i],
                onOpen: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => PlatformScreen(platform: list[i]))),
              ),
            ),
          );
        case HomeRow.collections:
          final regular = ref.watch(collectionsProvider).valueOrNull ?? const <RommCollection>[];
          return collectionShelf(row, curatedCollections(regular, const [], userId: userId));
        case HomeRow.smartCollections:
          return collectionShelf(row, ref.watch(smartCollectionsProvider).valueOrNull ?? const []);
        case HomeRow.virtualCollections:
          return collectionShelf(row, ref.watch(virtualCollectionsProvider('collection')).valueOrNull ?? const []);
      }
    }

    final added = ref.watch(recentlyAddedProvider);
    final error = offline ? null : played.error ?? added.error;
    final loading = !offline && (played.isLoading || added.isLoading);
    final empty =
        !loading &&
        error == null &&
        headerGame == null &&
        installed.isEmpty &&
        (added.valueOrNull?.isEmpty ?? true) &&
        layout.top != HomeTop.nothing;

    return Actions(
      actions: {
        // Y: another random pick (a focused game's Y is its ♥).
        FavoriteIntent: CallbackAction<FavoriteIntent>(onInvoke: (_) => ref.invalidate(randomGameProvider)),
      },
      child: ListView(
        key: const Key('page-Home'),
        padding: EdgeInsets.only(top: headerGame == null ? GLayout.navHeight + GSpace.s6 : 0, bottom: GSpace.s14),
        children: [
          if (headerGame != null)
            _RevealOnFocus(
              child: HomeHeader(game: headerGame, random: headerRandom, autofocus: true),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad),
              child: Text(
                'Welcome, $name',
                style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800),
              ),
            ),
          if (!offline)
            _RevealOnFocus(
              child: HomeWidgets(
                // The random pick isn't shown twice.
                shown: {
                  for (final w in layout.widgets)
                    if (!(w == HomeWidget.randomPick && headerRandom)) w,
                },
              ),
            ),
          if (loading) const Padding(padding: EdgeInsets.all(GSpace.rowPad), child: LinearProgressIndicator()),
          if (error != null)
            SizedBox(
              height: 260,
              child: ErrorRetry(
                message: describeLoadError(error),
                onRetry: () {
                  for (final p in [recentlyPlayedProvider, recentlyAddedProvider, favouriteGamesProvider]) {
                    ref.invalidate(p);
                  }
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
          for (final row in showRows) _RevealOnFocus(child: rowOf(row)),
          Padding(
            padding: const EdgeInsets.only(top: GSpace.s8),
            child: Center(
              child: GFocusable(
                key: const ValueKey('customize-home'),
                borderRadius: GRadius.pill,
                onActivate: () => showCustomizeHome(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
                  decoration: BoxDecoration(
                    color: GColors.bgElevated,
                    borderRadius: BorderRadius.circular(GRadius.pill),
                    border: Border.all(color: GColors.borderStrong),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune, size: 18, color: GColors.fgSecondary),
                      SizedBox(width: GSpace.s2),
                      Text('Customize Home', style: TextStyle(color: GColors.fgSecondary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrolls Home so all of [child] shows below the top bar when the
/// controller or keyboard moves focus into it. Flutter's own scroll only
/// brings the focused button into view, which left the header's art and
/// title, and a row's title, above the top of the screen.
class _RevealOnFocus extends ConsumerWidget {
  const _RevealOnFocus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) {
      if (focused && ref.read(inputModeProvider) != InputMode.mouse) _reveal(context);
    },
    child: child,
  );

  static void _reveal(BuildContext context) {
    final box = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (box == null || !box.attached || position == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    // Its top just below the top bar, or its bottom at the bottom edge;
    // the top wins when it doesn't fit.
    final top = viewport.getOffsetToReveal(box, 0).offset - GLayout.navHeight;
    final bottom = viewport.getOffsetToReveal(box, 1).offset;
    final target = math.min(top, math.max(position.pixels, bottom));
    final clamped = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (clamped != position.pixels) position.jumpTo(clamped);
  }
}
