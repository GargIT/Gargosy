import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/game_overview.dart';
import '../../../core/romm/romm_models.dart';
import '../../../providers/download_providers.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/game_card.dart';
import 'open_game.dart';

/// The Overview's related games (#179), one row a kind as on RomM's page:
/// IGDB's expansions, DLC, remakes, remasters and ports, then the
/// library's similar games. Rows without games aren't shown.
class RelatedGames extends ConsumerWidget {
  const RelatedGames({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similar = ref.watch(similarGamesProvider(game.id)).valueOrNull ?? const <Game>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final kind in game.overview.related.keys)
          _Row(
            title: kind.label,
            itemCount: game.overview.related[kind]!.length,
            itemBuilder: (context, i) => RelatedGameCard(game.overview.related[kind]![i]),
          ),
        if (similar.isNotEmpty)
          _Row(
            title: 'Similar games in your library',
            itemCount: similar.length,
            itemBuilder: (context, i) => GameCard(
              game: similar[i],
              coverUrl: coverUrlFor(ref, similar[i], small: true),
              downloaded: watchDownloaded(ref, similar[i]),
              onOpen: () => openGame(context, similar[i]),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.itemCount, required this.itemBuilder});

  final String title;
  final int itemCount;
  final Widget Function(BuildContext context, int i) itemBuilder;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: GSpace.s5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GSpace.s3),
        SizedBox(
          height: GameCard.height + GSpace.s3,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: GSpace.s3),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    ),
  );
}

/// A game IGDB relates to this one: RomM's own when the library has it
/// (A opens it), else IGDB's cover dimmed, "Not on RomM".
class RelatedGameCard extends ConsumerWidget {
  const RelatedGameCard(this.related, {super.key});

  final RelatedGame related;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inLibrary = ref.watch(gameByIgdbProvider(related.igdbId)).valueOrNull;
    if (inLibrary != null) {
      return GameCard(
        game: inLibrary,
        coverUrl: coverUrlFor(ref, inLibrary, small: true),
        downloaded: watchDownloaded(ref, inLibrary),
        onOpen: () => openGame(context, inLibrary),
      );
    }
    return SizedBox(
      width: GameCard.width,
      height: GameCard.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GFocusable(
            semanticLabel: '${related.name}, not on RomM',
            child: Opacity(
              opacity: 0.55,
              child: CoverImage(
                url: related.coverUrl,
                title: related.name,
                width: GameCard.width,
                height: GameCard.coverHeight,
              ),
            ),
          ),
          const SizedBox(height: GSpace.s2),
          Text(
            related.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: GFont.md, color: GColors.fgSecondary),
          ),
          const Text(
            'NOT ON ROMM',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: GColors.fgMuted),
          ),
        ],
      ),
    );
  }
}
