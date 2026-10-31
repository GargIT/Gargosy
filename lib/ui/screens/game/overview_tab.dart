import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/save_list/save_labels.dart';
import '../../../core/romm/romm_models.dart';
import '../../../play/play_time.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/format.dart';
import '../../widgets/g_focusable.dart';
import 'overview_facts.dart';
import 'similar_games.dart';
import '../../../l10n/tr.dart';

/// The game page's Overview (#179), in RomM's order: the description and
/// genres, the facts (last played, players, age rating), How long to beat,
/// screenshots, and similar games in the library.
class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = ref.watch(playTimeProvider(game.id)).value;
    final shots = [for (final s in game.mergedScreenshots) assetUrl(ref, s)].whereType<String>().toList();
    // The player's own first (#233), then RomM's scraped ones.
    final own = game.userScreenshots;
    final count = own.length + shots.length;
    final played = [if (game.lastPlayed case final last?) formatSaveTime(last), if (time != null) playTimeLine(time)];
    final summary = game.summary?.trim() ?? '';
    return ListView(
      padding: const EdgeInsets.only(bottom: GSpace.s14),
      children: [
        if (summary.isNotEmpty)
          Text(
            summary,
            style: const TextStyle(fontSize: GFont.lg, height: 1.6, color: GColors.fgSecondary),
          ),
        if (game.genres.isNotEmpty) ...[
          const SizedBox(height: GSpace.s4),
          Wrap(
            spacing: GSpace.s2,
            runSpacing: GSpace.s2,
            children: [
              for (final g in game.genres)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s1),
                  decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.chip)),
                  child: Text(g, style: const TextStyle(fontSize: GFont.sm)),
                ),
            ],
          ),
        ],
        const SizedBox(height: GSpace.s6),
        OverviewFacts(game: game, played: played.isEmpty ? null : played.join(' · ')),
        if (game.overview.hltb case final hltb?) ...[const SizedBox(height: GSpace.s3), HltbStrip(hltb)],
        if (count > 0) ...[
          const SizedBox(height: GSpace.s6),
          Text(
            tr('Screenshots'),
            style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: GSpace.s3),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: GSpace.s3),
              itemBuilder: (context, i) => GFocusable(
                borderRadius: GRadius.md,
                child: i < own.length
                    ? _OwnScreenshot(own[i])
                    : CoverImage(url: shots[i - own.length], width: 320, height: 180, radius: GRadius.md),
              ),
            ),
          ),
        ],
        SimilarGames(game: game),
      ],
    );
  }
}

/// One of the player's own screenshots: private on RomM, read with the token.
class _OwnScreenshot extends ConsumerWidget {
  const _OwnScreenshot(this.path);

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(userScreenshotProvider(path)).value;
    return ClipRRect(
      key: ValueKey('own-shot:$path'),
      borderRadius: BorderRadius.circular(GRadius.md),
      child: SizedBox(
        width: 320,
        height: 180,
        child: bytes == null
            ? const ColoredBox(color: GColors.surface)
            // Decoded at the strip's size, not the screenshot's.
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: (320 * MediaQuery.devicePixelRatioOf(context)).round(),
              ),
      ),
    );
  }
}
