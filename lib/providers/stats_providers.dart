import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_snapshot.dart';
import '../library/profile_stats.dart';
import '../play/play_limits.dart';
import '../play/play_time.dart';
import '../profiles/profile_providers.dart';
import 'romm_providers.dart';

/// The Stats page's numbers for the active profile (#236): this PC's
/// sessions, and RomM's from every device while it can be reached.
final profileStatsProvider = FutureProvider.autoDispose<StatsView>((ref) async {
  final log = ref.watch(playTimeLogProvider);
  final api = ref.watch(playSessionsApiProvider);
  final romm = ref.watch(rommServiceProvider);
  final online = romm != null && !ref.watch(rommOfflineProvider);
  final mine = {for (final g in ref.watch(gamesOnThisPcProvider)) g.id: g};
  final limit = ref.watch(ageLimitProvider);
  return loadStatsView(
    local: [for (final s in log?.all ?? const []) (gameId: s.gameId, start: s.start.toLocal(), end: s.end.toLocal())],
    now: ref.read(playClockProvider)(),
    // A game above the profile's age limit isn't named (#224).
    gameOf: (id) async {
      final game = mine[id] ?? (online ? await romm.getGame(id) : null);
      return game == null || !limit.allows(game) ? null : game;
    },
    remote: online && api != null
        ? () async {
            final list = await api.sessionsSince(DateTime(2000));
            return list == null
                ? null
                : [
                    for (final r in list)
                      if (r.gameId case final id?) (gameId: id, start: r.start, end: r.end),
                  ];
          }
        : null,
    finished: online ? () => romm.countGamesWithStatuses(const ['finished', 'completed_100']) : null,
    progression: online ? romm.getRetroAchievementsProgressionOrNull : null,
  );
});
