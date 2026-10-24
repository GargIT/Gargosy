import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/retroachievements/retroachievements_game_models.dart';
import '../../../core/romm/romm_models.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';

/// RomM's RetroAchievements set for the game, with the unlocks RomM synced
/// for the user when it has them.
class AchievementsTab extends ConsumerWidget {
  const AchievementsTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (game.raId == null || game.raAchievements.isEmpty) {
      return const Center(
        child: Text(
          'RomM has no RetroAchievements for this game.',
          style: TextStyle(fontSize: GFont.lg, color: GColors.fgMuted),
        ),
      );
    }
    final progression = ref.watch(raProgressionProvider).valueOrNull?[game.raId];
    final progress = progression == null
        ? null
        : RetroAchievementsGameProgress.fromRomm(
            gameId: game.raId!,
            achievements: game.raAchievements,
            progression: progression,
          );
    final list = progress?.achievements ?? game.raAchievements;
    return ListView(
      padding: const EdgeInsets.only(bottom: GSpace.s14),
      children: [
        Text(
          progress == null
              ? '${list.length} achievements (no progress synced to RomM)'
              : '${progress.unlockedCount} / ${progress.totalCount} unlocked  ·  ${progress.earnedPoints} / ${progress.totalPoints} points',
          style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary),
        ),
        if (progress != null && progress.totalCount > 0) ...[
          const SizedBox(height: GSpace.s2),
          LinearProgressIndicator(value: progress.unlockedCount / progress.totalCount),
        ],
        const SizedBox(height: GSpace.s4),
        for (final a in list)
          GFocusable(
            borderRadius: GRadius.md,
            child: Container(
              margin: const EdgeInsets.only(bottom: GSpace.s2),
              padding: const EdgeInsets.all(GSpace.s3),
              decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.md)),
              child: Row(
                children: [
                  Icon(
                    a.isUnlocked ? Icons.emoji_events : Icons.lock_outline,
                    color: a.isUnlocked ? GColors.gargosyGold : GColors.fgFaint,
                  ),
                  const SizedBox(width: GSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          a.description,
                          style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                        ),
                      ],
                    ),
                  ),
                  Text('${a.points}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
