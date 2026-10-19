import 'package:flutter/material.dart';

import '../../core/romm/romm_models.dart';
import '../theme/tokens.dart';
import 'game_card.dart';

/// A titled row of game cards (v2's home rows).
class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.games,
    required this.coverUrl,
    required this.onOpen,
    this.onFavorite,
    this.isFavourite,
    this.isDownloaded,
    this.autofocusFirst = false,
  });

  final String title;
  final List<Game> games;
  final String? Function(Game) coverUrl;
  final void Function(Game) onOpen;
  final void Function(Game)? onFavorite;
  final bool Function(Game)? isFavourite;
  final bool Function(Game)? isDownloaded;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s6, GSpace.rowPad, GSpace.s3),
          child: Text(
            title,
            style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: GameCard.height + GSpace.s3,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad),
            itemCount: games.length,
            separatorBuilder: (_, _) => const SizedBox(width: GSpace.s4),
            itemBuilder: (context, i) => GameCard(
              game: games[i],
              coverUrl: coverUrl(games[i]),
              autofocus: autofocusFirst && i == 0,
              favourite: isFavourite?.call(games[i]) ?? false,
              downloaded: isDownloaded?.call(games[i]) ?? false,
              onOpen: () => onOpen(games[i]),
              onFavorite: onFavorite == null ? null : () => onFavorite!(games[i]),
            ),
          ),
        ),
      ],
    );
  }
}
