import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/save_list/save_labels.dart';
import '../../../core/romm/romm_models.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/g_focusable.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shots = [for (final s in game.mergedScreenshots) assetUrl(ref, s)].whereType<String>().toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: GSpace.s14),
      children: [
        if (game.lastPlayed case final played?) ...[
          Text('Last played ${formatSaveTime(played)}', style: const TextStyle(color: GColors.fgMuted)),
          const SizedBox(height: GSpace.s3),
        ],
        if (game.summary != null && game.summary!.isNotEmpty)
          Text(
            game.summary!,
            style: const TextStyle(fontSize: GFont.lg, height: 1.6, color: GColors.fgSecondary),
          ),
        const SizedBox(height: GSpace.s5),
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
        if (shots.isNotEmpty) ...[
          const SizedBox(height: GSpace.s6),
          const Text(
            'Screenshots',
            style: TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: GSpace.s3),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shots.length,
              separatorBuilder: (_, _) => const SizedBox(width: GSpace.s3),
              itemBuilder: (context, i) => GFocusable(
                borderRadius: GRadius.md,
                child: CoverImage(url: shots[i], width: 320, height: 180, radius: GRadius.md),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
