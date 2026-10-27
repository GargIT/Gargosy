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
import 'home_widgets.dart';

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
      itemWidth: PlayingNowCard.width,
      itemBuilder: (context, i) => PlayingNowCard(entries[i]),
    );
  }
}

/// A player's game now, as Home's Random pick: the cover on the left, then
/// what, on which platform, and who (their avatar), where and for how long.
/// A opens the game.
class PlayingNowCard extends ConsumerWidget {
  const PlayingNowCard(this.entry, {super.key});

  final ActivityEntry entry;

  static const width = 420.0;
  static const height = HomeWidgets.height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final you = ref.watch(rommUserIdProvider) == entry.userId;
    final deviceId = ref.watch(activeProfileProvider.select((c) => c?.login.deviceId));
    final owner = SaveOwner(
      userId: entry.userId,
      username: entry.username,
      avatarPath: entry.avatarPath.isEmpty ? null : entry.avatarPath,
    );
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
          padding: const EdgeInsets.all(GSpace.s4),
          decoration: BoxDecoration(
            color: GColors.card,
            border: Border.all(color: GColors.border),
            borderRadius: BorderRadius.circular(GRadius.card),
          ),
          child: Row(
            children: [
              CoverImage(url: assetUrl(ref, entry.coverPath), title: entry.gameName, width: 66, height: 88),
              const SizedBox(width: GSpace.s4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.gameName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
                    ),
                    if (entry.platformName.isNotEmpty)
                      Text(
                        entry.platformName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
                      ),
                    const SizedBox(height: GSpace.s2),
                    Row(
                      children: [
                        PlayerAvatar(owner, size: 24),
                        const SizedBox(width: GSpace.s2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                you ? 'You' : entry.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w600),
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
