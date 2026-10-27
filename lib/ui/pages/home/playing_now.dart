import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_activity.dart';
import '../../../core/save/catalog/save_entry.dart';
import '../../../library/home_layout.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../screens/game/open_game.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/save_list/player_avatar.dart';
import '../../widgets/shelf.dart';

/// Home's Playing now (#180): one card a player on RomM, as RomM's Activity
/// board; nothing while nobody plays.
class PlayingNowRow extends ConsumerWidget {
  const PlayingNowRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(playingNowProvider).valueOrNull ?? const <ActivityEntry>[];
    return Shelf(
      key: const ValueKey('home-playingNow'),
      title: HomeRow.playingNow.label,
      count: entries.length,
      itemCount: entries.length,
      height: PlayingNowCard.height,
      itemBuilder: (context, i) => PlayingNowCard(entries[i]),
    );
  }
}

/// A player's game now: where they are (their latest screenshot, else the
/// cover), who, what, where and for how long. A opens the game.
class PlayingNowCard extends ConsumerWidget {
  const PlayingNowCard(this.entry, {super.key});

  final ActivityEntry entry;

  static const width = 300.0;
  static const imageHeight = 169.0;
  static const height = imageHeight + 76;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final you = ref.watch(rommUserIdProvider) == entry.userId;
    final deviceId = ref.watch(activeProfileProvider.select((c) => c?.login.deviceId));
    final image = entry.screenshotPath.isNotEmpty ? entry.screenshotPath : entry.coverPath;
    return SizedBox(
      width: width,
      height: height,
      child: GFocusable(
        borderRadius: GRadius.card,
        semanticLabel: '${you ? 'You' : entry.username}, ${entry.gameName}',
        onActivate: () async {
          final game = await ref.read(gameProvider(entry.gameId).future);
          if (game != null && context.mounted) await openGame(context, game);
        },
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: GColors.bgElevated,
            border: Border.all(color: GColors.border),
            borderRadius: BorderRadius.circular(GRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CoverImage(url: assetUrl(ref, image), title: entry.gameName, height: imageHeight, radius: 0),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    PlayerAvatar(SaveOwner(userId: entry.userId, username: entry.username), size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.gameName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [
                              you ? 'You' : entry.username,
                              if (entry.platformName.isNotEmpty) entry.platformName,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
                          ),
                          Text(
                            '${activityWhere(entry, thisDeviceId: deviceId)} · ${activityFor(entry, DateTime.now())}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: GFont.xs, color: GColors.fgMuted),
                          ),
                        ],
                      ),
                    ),
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
