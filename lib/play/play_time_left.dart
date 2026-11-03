import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../profiles/play_limit.dart';
import '../profiles/profile_providers.dart';
import 'play_controller.dart';
import 'play_limits.dart';

/// What the open profile's play time limit allows now (#235), for the top
/// bar and the play screen: the time left, or when play is back. Null
/// without a limit, or before it's counted.
///
/// Counted once ([count], what a game's start asks), then worked out
/// against the clock every [tick], the running game's time taken off as it
/// plays; counted again when a session ends, after [recountEvery] (another
/// PC's play), when the play day turns, and when a refusal's time comes.
/// Until a count is done the last one stays shown.
class PlayTimeLeftNotifier extends StateNotifier<PlayAllowance?> {
  PlayTimeLeftNotifier({
    required this.limit,
    required this.count,
    required this.clock,
    required this.playingSince,
    Duration tick = const Duration(seconds: 15),
    this.recountEvery = const Duration(minutes: 10),
  }) : super(null) {
    if (!limit.isOn) return;
    recount();
    _timer = Timer.periodic(tick, (_) => _tick());
  }

  final PlayLimit limit;
  final Future<PlayCheck> Function() count;
  final DateTime Function() clock;
  final DateTime? Function() playingSince;
  final Duration recountEvery;

  Timer? _timer;
  PlayCheck? _check;
  Future<void>? _counting;
  var _again = false;

  /// Counts the time played again; one count at a time, another asked
  /// meanwhile runs after it.
  Future<void> recount() {
    if (!limit.isOn) return Future.value();
    if (_counting case final running?) {
      _again = true;
      return running;
    }
    final counting = _countLoop();
    _counting = counting;
    return counting;
  }

  Future<void> _countLoop() async {
    try {
      do {
        _again = false;
        final PlayCheck check;
        try {
          check = await count();
        } on Object catch (e) {
          debugPrint('[PlayLimit] time left not counted: $e');
          return;
        }
        if (!mounted) return;
        _check = check;
        _show();
      } while (_again);
    } finally {
      _counting = null;
    }
  }

  /// A game started (shown at once) or ended ([ended]: counted again, its
  /// session now logged).
  void sessionChanged({required bool ended}) => ended ? recount() : _show();

  void _show() {
    final check = _check;
    if (check == null || !mounted) return;
    state = check.allowanceAt(limit, clock(), playingSince: playingSince());
  }

  void _tick() {
    final check = _check;
    if (check == null || _counting != null) return;
    final now = clock();
    final shown = state;
    final stale =
        now.difference(check.at) >= recountEvery ||
        playDayStart(limit, now) != playDayStart(limit, check.at) ||
        (shown is PlayRefused && !now.isBefore(shown.backAt) && now.difference(check.at) >= const Duration(minutes: 1));
    if (stale) {
      recount();
    } else {
      _show();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// How play time is counted; tests give their own.
final playTimeCounterProvider = Provider<Future<PlayCheck> Function()>(
  (ref) =>
      () => checkPlayTime(ref),
);

/// [PlayTimeLeftNotifier] for the open profile and its limit; kept while
/// they last, so a page that shows it again doesn't count again.
final playTimeLeftProvider = StateNotifierProvider<PlayTimeLeftNotifier, PlayAllowance?>((ref) {
  ref.watch(activeProfileProvider.select((c) => c?.profile.id));
  final limit = ref.watch(playLimitProvider);
  final notifier = PlayTimeLeftNotifier(
    limit: limit,
    count: ref.read(playTimeCounterProvider),
    clock: ref.read(playClockProvider),
    playingSince: () => ref.read(playControllerProvider).playingSince,
  );
  if (limit.isOn) {
    ref.listen(
      playControllerProvider.select((s) => s.playingSince),
      (before, now) => notifier.sessionChanged(ended: before != null && now == null),
    );
  }
  return notifier;
});
