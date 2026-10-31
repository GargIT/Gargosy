import '../core/romm/romm_models.dart';

/// One session of a game, from this PC's log or RomM's.
typedef StatSession = ({String gameId, DateTime start, DateTime end});

/// Two records of one session (this PC's log and RomM's copy of it): the
/// same game, start and end, give or take RomM's rounding.
bool sameSession(StatSession a, StatSession b) =>
    a.gameId == b.gameId &&
    a.start.difference(b.start).abs() < const Duration(seconds: 5) &&
    a.end.difference(b.end).abs() < const Duration(seconds: 5);

/// This PC's sessions with RomM's from every device, each once: RomM's copy
/// of one of this PC's is left out.
List<StatSession> mergeSessions(List<StatSession> local, List<StatSession> remote) => [
  ...local,
  for (final r in remote)
    if (!local.any((l) => sameSession(l, r))) r,
];

/// #236: what a profile's play adds up to, from its sessions.
class ProfileStats {
  const ProfileStats({
    required this.week,
    required this.month,
    required this.all,
    required this.sessions,
    required this.mostPlayed,
    required this.longest,
    required this.daysInARow,
  });

  /// Played since Monday, since the 1st, and ever.
  final Duration week, month, all;
  final int sessions;

  /// Games by time played, most first.
  final List<({String gameId, Duration time})> mostPlayed;

  final StatSession? longest;

  /// Days in a row with play, up to today (or yesterday, when today has
  /// none yet).
  final int daysInARow;

  static const empty = ProfileStats(
    week: Duration.zero,
    month: Duration.zero,
    all: Duration.zero,
    sessions: 0,
    mostPlayed: [],
    longest: null,
    daysInARow: 0,
  );

  static ProfileStats of(List<StatSession> sessions, DateTime now) {
    if (sessions.isEmpty) return empty;
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final first = DateTime(today.year, today.month);
    Duration since(DateTime from) {
      var total = Duration.zero;
      for (final s in sessions) {
        final start = s.start.isBefore(from) ? from : s.start;
        if (s.end.isAfter(start)) total += s.end.difference(start);
      }
      return total;
    }

    final perGame = <String, Duration>{};
    StatSession? longest;
    final days = <DateTime>{};
    var all = Duration.zero;
    for (final s in sessions) {
      final length = s.end.difference(s.start);
      if (length.isNegative) continue;
      all += length;
      perGame[s.gameId] = (perGame[s.gameId] ?? Duration.zero) + length;
      if (longest == null || length > longest.end.difference(longest.start)) longest = s;
      days.add(DateTime(s.start.year, s.start.month, s.start.day));
    }
    var day = days.contains(today) ? today : DateTime(today.year, today.month, today.day - 1);
    var streak = 0;
    while (days.contains(day)) {
      streak++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    final most = [for (final e in perGame.entries) (gameId: e.key, time: e.value)]
      ..sort((a, b) => b.time.compareTo(a.time));
    return ProfileStats(
      week: since(monday),
      month: since(first),
      all: all,
      sessions: sessions.length,
      mostPlayed: most,
      longest: longest,
      daysInARow: streak,
    );
  }

  /// Time played per platform, most first; [platformOf] names a game's
  /// platform, null when it isn't known (counted as [other]).
  List<({String platform, Duration time})> byPlatform(String? Function(String gameId) platformOf, String other) {
    final per = <String, Duration>{};
    for (final g in mostPlayed) {
      final name = platformOf(g.gameId) ?? other;
      per[name] = (per[name] ?? Duration.zero) + g.time;
    }
    return [for (final e in per.entries) (platform: e.key, time: e.value)]..sort((a, b) => b.time.compareTo(a.time));
  }
}

/// The RetroAchievements earned since [from], from RomM's `ra_progression`
/// (by game): each counted once, by its hardcore or softcore unlock date.
int achievementsEarnedSince(Map<int, Map<String, dynamic>> progression, DateTime from) {
  var n = 0;
  for (final game in progression.values) {
    for (final e in (game['earned_achievements'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>()) {
      final dates = [
        for (final key in const ['date', 'date_hardcore']) ?_raDate(e[key]),
      ];
      if (dates.any((d) => !d.isBefore(from))) n++;
    }
  }
  return n;
}

/// RetroAchievements' `2026-10-31 18:22:05` (UTC) or an ISO time.
DateTime? _raDate(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final iso = v.contains('T') ? v : '${v.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(iso)?.toLocal();
}

/// The Stats page's numbers (#236), with the games they name.
class StatsView {
  const StatsView({
    required this.stats,
    required this.games,
    required this.thisPcOnly,
    this.finished,
    this.achievementsThisMonth,
  });

  final ProfileStats stats;

  /// The most played games RomM or this PC could name.
  final Map<String, Game> games;

  /// RomM couldn't be asked: this PC's sessions only.
  final bool thisPcOnly;

  /// Games marked finished or completed on RomM; null when it couldn't say.
  final int? finished;

  /// RetroAchievements earned since the 1st; null without RomM's progress.
  final int? achievementsThisMonth;
}

/// How many of the most played games are looked up by name and platform.
const statsGamesNamed = 30;

/// Gathers [StatsView] from this PC's [local] sessions and, when RomM can be
/// asked ([remote] etc. not null), its sessions from every device, the
/// finished count and the RetroAchievements progress. A RomM call that
/// fails counts as not asked. [gameOf] names a game (this PC's library
/// first, then RomM).
Future<StatsView> loadStatsView({
  required List<StatSession> local,
  required DateTime now,
  required Future<Game?> Function(String gameId) gameOf,
  Future<List<StatSession>?> Function()? remote,
  Future<int?> Function()? finished,
  Future<Map<int, Map<String, dynamic>>?> Function()? progression,
}) async {
  Future<T?> ask<T>(Future<T?> Function()? call) async {
    if (call == null) return null;
    try {
      return await call();
    } on Object {
      return null;
    }
  }

  final fromRomm = await ask(remote);
  final stats = ProfileStats.of(fromRomm == null ? local : mergeSessions(local, fromRomm), now);
  final games = <String, Game>{};
  for (final g in stats.mostPlayed.take(statsGamesNamed)) {
    if (await ask(() => gameOf(g.gameId)) case final game?) games[g.gameId] = game;
  }
  final ra = await ask(progression);
  return StatsView(
    stats: stats,
    games: games,
    thisPcOnly: fromRomm == null,
    finished: await ask(finished),
    achievementsThisMonth: ra == null ? null : achievementsEarnedSince(ra, DateTime(now.year, now.month)),
  );
}
