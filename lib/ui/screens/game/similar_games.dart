import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/g_focusable.dart';
import 'open_game.dart';
import '../../../l10n/tr.dart';

/// The Overview's Similar games in your library (#179), from RomM's
/// similarity index, as small covers; nothing when RomM has none.
class SimilarGames extends ConsumerWidget {
  const SimilarGames({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similar = ref.watch(similarGamesProvider(game.id)).valueOrNull ?? const <Game>[];
    if (similar.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: GSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Similar games in your library').toUpperCase(),
            style: const TextStyle(
              fontSize: GFont.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: GColors.fgMuted,
            ),
          ),
          const SizedBox(height: GSpace.s2),
          SizedBox(
            height: SmallGameCard.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: similar.length,
              separatorBuilder: (_, _) => const SizedBox(width: GSpace.s3),
              itemBuilder: (context, i) => SmallGameCard(
                title: similar[i].displayName,
                coverUrl: coverUrlFor(ref, similar[i], small: true),
                onOpen: () => openGame(context, similar[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small cover with its name under it; A opens the game.
class SmallGameCard extends StatelessWidget {
  const SmallGameCard({super.key, required this.title, this.coverUrl, required this.onOpen});

  final String title;
  final String? coverUrl;
  final VoidCallback onOpen;

  static const width = 120.0;
  static const coverHeight = 160.0;
  static const height = coverHeight + 34;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GFocusable(
          borderRadius: GRadius.md,
          onActivate: onOpen,
          semanticLabel: title,
          child: CoverImage(url: coverUrl, title: title, width: width, height: coverHeight, radius: GRadius.md),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: GFont.sm),
        ),
      ],
    ),
  );
}
