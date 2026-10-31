import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../library/profile_stats.dart';
import '../../providers/library_providers.dart';
import '../../providers/stats_providers.dart';
import '../shell/backdrop.dart';
import '../shell/page_top_bar.dart';
import '../theme/tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/error_retry.dart';
import '../widgets/format.dart';
import '../widgets/g_focusable.dart';
import '../widgets/hint_bar.dart';
import 'game/open_game.dart';
import '../../l10n/tr.dart';

/// #236: the profile's play in numbers, from the user menu: time this week,
/// month and ever, longest session, days in a row, games finished and
/// achievements this month; then the most played games (A opens one) and
/// time by platform. Offline, this PC's sessions only, and it says so.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  /// How many games the Most played list shows.
  static const mostShown = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(profileStatsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTopBar(scrolled: false),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: view.when(
                    data: (v) => _Body(view: v),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorRetry(message: '$e', onRetry: () => ref.invalidate(profileStatsProvider)),
                  ),
                ),
              ),
            ),
            HintBar(hints: [Hint(GameAction.confirm, tr('Open')), Hint(GameAction.back, tr('Back'))]),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.view});

  final StatsView view;

  static Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: GSpace.s8, bottom: GSpace.s3),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: GFont.sm,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: GColors.fgMuted,
      ),
    ),
  );

  Widget _tile(String key, String label, String value) => Container(
    key: ValueKey('stat-$key'),
    width: 220,
    padding: const EdgeInsets.all(GSpace.s4),
    decoration: BoxDecoration(
      color: GColors.card,
      borderRadius: BorderRadius.circular(GRadius.card),
      border: Border.all(color: GColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
        ),
        const SizedBox(height: GSpace.s2),
        Text(
          value,
          style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = view.stats;
    final longest = s.longest;
    final most = s.mostPlayed.take(StatsScreen.mostShown).toList();
    final platforms = s.byPlatform((id) => view.games[id]?.platformDisplayName, tr('Other'));
    final top = platforms.isEmpty ? Duration.zero : platforms.first.time;
    return ListView(
      key: const Key('page-Stats'),
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s8, vertical: GSpace.s6),
      children: [
        Text(
          tr('Stats'),
          style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800),
        ),
        if (view.thisPcOnly)
          Padding(
            padding: const EdgeInsets.only(top: GSpace.s2),
            child: Text(
              tr('RomM can\'t be reached: this PC\'s play only.'),
              key: const ValueKey('stats-this-pc'),
              style: const TextStyle(color: GColors.gargosyGold),
            ),
          ),
        const SizedBox(height: GSpace.s5),
        Wrap(
          spacing: GSpace.s3,
          runSpacing: GSpace.s3,
          children: [
            _tile('week', tr('This week'), formatPlayTime(s.week)),
            _tile('month', tr('This month'), formatPlayTime(s.month)),
            _tile('all', tr('All time'), formatPlayTime(s.all)),
            _tile(
              'longest',
              tr('Longest session'),
              longest == null ? '–' : formatPlayTime(longest.end.difference(longest.start)),
            ),
            _tile('streak', tr('Days in a row'), '${s.daysInARow}'),
            _tile('finished', tr('Games finished'), view.finished == null ? '–' : '${view.finished}'),
            _tile(
              'achievements',
              tr('Achievements this month'),
              view.achievementsThisMonth == null ? '–' : '${view.achievementsThisMonth}',
            ),
          ],
        ),
        _heading(tr('MOST PLAYED')),
        if (most.isEmpty)
          Text(tr('Nothing played yet.'), style: const TextStyle(color: GColors.fgMuted))
        else
          for (var i = 0; i < most.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: GSpace.s2),
              child: _GameRow(rank: i + 1, time: most[i].time, gameId: most[i].gameId, view: view, autofocus: i == 0),
            ),
        if (platforms.isNotEmpty) ...[
          _heading(tr('BY PLATFORM')),
          for (final p in platforms)
            Padding(
              padding: const EdgeInsets.only(bottom: GSpace.s2),
              child: Row(
                children: [
                  SizedBox(width: 220, child: Text(p.platform, overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: top == Duration.zero ? 0 : p.time.inSeconds / top.inSeconds,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(GRadius.pill),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      formatPlayTime(p.time),
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: GColors.fgSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// One of the most played games: rank, cover, name, platform and time; A
/// opens its page (a game RomM can't name isn't focusable).
class _GameRow extends ConsumerWidget {
  const _GameRow({
    required this.rank,
    required this.time,
    required this.gameId,
    required this.view,
    this.autofocus = false,
  });

  final int rank;
  final Duration time;
  final String gameId;
  final StatsView view;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = view.games[gameId];
    final row = Container(
      padding: const EdgeInsets.all(GSpace.s3),
      decoration: BoxDecoration(
        color: GColors.card,
        borderRadius: BorderRadius.circular(GRadius.card),
        border: Border.all(color: GColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              style: const TextStyle(fontSize: GFont.lg, color: GColors.fgMuted),
            ),
          ),
          CoverImage(
            url: game == null ? null : coverUrlFor(ref, game, small: true),
            title: game?.displayName ?? gameId,
            width: 45,
            height: 60,
          ),
          const SizedBox(width: GSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game?.displayName ?? tr('Game {0}', [gameId]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
                ),
                if (game?.platformDisplayName case final platform?)
                  Text(platform, style: const TextStyle(color: GColors.fgSecondary)),
              ],
            ),
          ),
          Text(
            formatPlayTime(time),
            style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return GFocusable(
      key: ValueKey('stats-game-$gameId'),
      autofocus: autofocus,
      borderRadius: GRadius.card,
      onActivate: game == null ? null : () => openGame(context, game),
      child: row,
    );
  }
}
