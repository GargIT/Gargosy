import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/retroachievements/retroachievements_game_models.dart';
import '../core/romm/romm_models.dart';
import '../providers/library_providers.dart';
import '../providers/romm_providers.dart';
import '../retroachievements/ra_account.dart';
import '../l10n/tr.dart';

/// RomM's RetroAchievements progress, as a session needs it (#189). The
/// real one asks `RommService`; tests fake it.
abstract class AchievementProgress {
  /// The user's progress by RA game id; null when RomM couldn't say.
  Future<Map<int, Map<String, dynamic>>?> progression();

  /// Asks RomM to read the user's newest unlocks from RetroAchievements.
  Future<bool> refresh(int userId);
}

/// What a session earned: the achievements, and whether the profile plays
/// in hardcore.
class SessionAchievements {
  const SessionAchievements(this.gameId, this.earned, {required this.hardcore});

  /// RomM's id of the game played.
  final String gameId;
  final List<RetroAchievement> earned;
  final bool hardcore;

  int get points => earned.fold(0, (sum, a) => sum + a.points);

  /// For the session's end: "2 achievements earned · 15 points (hardcore)".
  String get line {
    final n = earned.length;
    final what = n == 1 ? tr('1 achievement earned') : tr('{0} achievements earned', [n]);
    final pts = points == 1 ? tr('1 point') : tr('{0} points', [points]);
    return '$what · $pts (${hardcore ? 'hardcore' : 'softcore'})';
  }
}

Map<String, Map<String, dynamic>> _earnedById(Map<String, dynamic>? entry) => {
  for (final e in (entry?['earned_achievements'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
    if (e['id'] != null) e['id'].toString(): e,
};

bool _set(Object? date) => date != null && '$date'.isNotEmpty;

/// The achievements of [all] earned between RomM's progress entries [before]
/// and [after] for one game. RomM's earned ids are badge names. In
/// [hardcore], one earned in softcore before and in hardcore now counts too.
List<RetroAchievement> earnedBetween(
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
  List<RetroAchievement> all, {
  bool hardcore = false,
}) {
  final was = _earnedById(before);
  final now = _earnedById(after);
  final fresh = {
    for (final key in now.keys)
      if (!was.containsKey(key) || (hardcore && _set(now[key]!['date_hardcore']) && !_set(was[key]!['date_hardcore'])))
        key,
  };
  return [
    for (final a in all)
      if (fresh.contains(a.badgeName)) a,
  ];
}

/// Watches one session's achievements: [start] before launch, [finish] once
/// the emulator exited. Nothing for a game without RetroAchievements, a
/// profile without an RA login, or when RomM can't say.
class SessionAchievementsWatch {
  SessionAchievementsWatch._(this._game, this._progress, this._userId, this._hardcore, this._before);

  final Game _game;
  final AchievementProgress _progress;
  final int _userId;
  final bool _hardcore;
  final Future<Map<int, Map<String, dynamic>>?> _before;

  /// How long RomM may take to read RetroAchievements again.
  static const timeout = Duration(minutes: 2);

  /// Null when this session has nothing to watch.
  static SessionAchievementsWatch? start(
    Game game, {
    required AchievementProgress? progress,
    required int? userId,
    required RaAccount? account,
  }) {
    if (game.raId == null || game.raAchievements.isEmpty || progress == null || userId == null) return null;
    if (account?.username == null) return null;
    return SessionAchievementsWatch._(game, progress, userId, account!.hardcore, progress.progression());
  }

  /// The session's achievements; null when RomM couldn't say, or none.
  Future<SessionAchievements?> finish() async {
    try {
      final before = await _before;
      if (before == null) return null;
      await _progress.refresh(_userId).timeout(timeout);
      final after = await _progress.progression().timeout(timeout);
      if (after == null) return null;
      final raId = _game.raId!;
      final earned = earnedBetween(before[raId], after[raId], _game.raAchievements, hardcore: _hardcore);
      debugPrint('[RA] ${_game.displayName}: ${earned.length} earned this session');
      return earned.isEmpty ? null : SessionAchievements(_game.id, earned, hardcore: _hardcore);
    } on Object catch (e) {
      debugPrint('[RA] session achievements not read: $e');
      return null;
    }
  }
}

class _RommAchievementProgress implements AchievementProgress {
  _RommAchievementProgress(this._ref);
  final Ref _ref;

  @override
  Future<Map<int, Map<String, dynamic>>?> progression() async =>
      _ref.read(rommServiceProvider)?.getRetroAchievementsProgressionOrNull();

  @override
  Future<bool> refresh(int userId) async =>
      await _ref.read(rommServiceProvider)?.refreshNewRetroAchievements(userId) ?? false;
}

/// RomM's progress for sessions; null offline.
final achievementProgressProvider = Provider<AchievementProgress?>((ref) {
  if (ref.watch(rommServiceProvider) == null) return null;
  return _RommAchievementProgress(ref);
});

/// The last session's achievements (#189), for the game page to say; the
/// game's Achievements tab reads RomM's progress again with it.
final sessionAchievementsProvider = StateProvider<SessionAchievements?>((ref) => null);

/// Starts watching [game]'s session from [ref]'s profile.
SessionAchievementsWatch? watchSessionAchievements(Ref ref, Game game) => SessionAchievementsWatch.start(
  game,
  progress: ref.read(achievementProgressProvider),
  userId: ref.read(rommUserIdProvider),
  account: ref.read(raAccountProvider),
);
