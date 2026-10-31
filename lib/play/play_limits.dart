import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_play_sessions.dart';
import '../profiles/play_limit.dart';
import '../profiles/profile_providers.dart';
import '../providers/romm_providers.dart';
import '../l10n/tr.dart';
import 'play_time.dart';

/// The time now; tests give their own.
final playClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// What says the time is nearly up while a game is in front: Windows' alert
/// sound (Gargosy can't show anything over the emulator); tests give their
/// own.
final playLimitWarningProvider = Provider<void Function()>(
  (ref) =>
      () => SystemSound.play(SystemSoundType.alert),
);

/// Two records of one session (this PC's log and RomM's copy of it): the
/// same start and end, give or take RomM's rounding.
bool _sameSession((DateTime, DateTime) a, (DateTime, DateTime) b) =>
    a.$1.difference(b.$1).abs() < const Duration(seconds: 5) &&
    a.$2.difference(b.$2).abs() < const Duration(seconds: 5);

/// What the profile played since [from] (#235): this PC's sessions, and
/// RomM's from its other devices. One RomM has from this PC (by device id,
/// or by its times: sent before this PC had a device id, or by the PC the
/// profile folder came from) counts once. RomM away or unreachable: this
/// PC's only.
Future<Duration> playedSince(
  DateTime from, {
  required PlayTimeLog? log,
  required PlaySessionsApi? api,
  required String? deviceId,
  required DateTime now,
}) async {
  final local = <(DateTime, DateTime)>[
    for (final s in log?.all ?? const <PlaySessionRecord>[])
      if (s.end.toLocal().isAfter(from)) (s.start.toLocal(), s.end.toLocal()),
  ];
  final sessions = [...local];
  if (api != null) {
    try {
      // From a day before: a session that started then may run into [from].
      final remote = await api.sessionsSince(DateTime(from.year, from.month, from.day - 1));
      for (final r in remote ?? const <RemoteSession>[]) {
        final s = (r.start, r.end);
        if (deviceId != null && r.deviceId == deviceId) continue;
        if (local.any((l) => _sameSession(l, s))) continue;
        sessions.add(s);
      }
    } on Object catch (e) {
      debugPrint('[PlayLimit] RomM\'s sessions not read, this PC\'s only: $e');
    }
  }
  return playedBetween(from, now, sessions);
}

/// A play time check: whether a game may start, with what it was counted
/// from, so a running game's end can be worked out again as time passes or
/// the limit changes.
class PlayCheck {
  const PlayCheck(this.allowance, {required this.used, required this.at});

  final PlayAllowance allowance;

  /// Played this play day when checked, and when that was.
  final Duration used;
  final DateTime at;

  /// When a game started at [at] has to end at [now] under [limit] (it
  /// counts as played since); null: no end. Past [now]: it's up.
  DateTime? untilAt(PlayLimit limit, DateTime now) {
    if (!limit.isOn) return null;
    final window = limit.window;
    if (window != null && !window.allows(now)) return now;
    DateTime? until;
    if (limit.minutesPerDay case final minutes?) {
      until = now.add(Duration(minutes: minutes) - used - now.difference(at));
    }
    if (window != null) {
      final closes = windowClosesAt(window, now);
      if (until == null || closes.isBefore(until)) until = closes;
    }
    return until;
  }
}

/// Whether the active profile may start a game now (#235), and until when.
/// A limit that can't be counted refuses: it never lets a game past it.
Future<PlayCheck> checkPlayTime(Ref ref) async {
  final limit = ref.read(playLimitProvider);
  final now = ref.read(playClockProvider)();
  if (!limit.isOn) return PlayCheck(const PlayAllowed(null), used: Duration.zero, at: now);
  try {
    final used = limit.minutesPerDay == null
        ? Duration.zero
        : await playedSince(
            playDayStart(limit, now),
            log: ref.read(playTimeLogProvider),
            api: ref.read(rommOfflineProvider) ? null : ref.read(playSessionsApiProvider),
            deviceId: ref.read(activeProfileProvider)?.login.deviceId,
            now: now,
          );
    return PlayCheck(allowanceFor(limit, used, now), used: used, at: now);
  } on Object catch (e) {
    debugPrint('[PlayLimit] not counted: $e');
    return PlayCheck(PlayRefused(tr('Play time couldn\'t be counted: {0}', [e]), now), used: Duration.zero, at: now);
  }
}

/// A running game's time limit, looked at every [every] against the clock
/// (a sleep or a clock change doesn't move it): [onWarn] once,
/// [PlayLimit.warnBefore] before the end; [onEnd] at it and at each look
/// after, until cancelled (a close that didn't work is tried again). The
/// end is asked again each time ([until]), so a changed limit counts.
class PlayLimitTimer {
  PlayLimitTimer({
    required this.until,
    required this.clock,
    required this.onWarn,
    required this.onEnd,
    Duration every = const Duration(seconds: 15),
  }) {
    _tick();
    _timer = Timer.periodic(every, (_) => _tick());
  }

  final DateTime? Function() until;
  final DateTime Function() clock;
  final void Function() onWarn;
  final void Function() onEnd;
  late final Timer _timer;
  var _warned = false;

  void _tick() {
    final end = until();
    if (end == null) return;
    final now = clock();
    if (!_warned && !now.isBefore(end.subtract(PlayLimit.warnBefore))) {
      _warned = true;
      onWarn();
    }
    if (!now.isBefore(end)) onEnd();
  }

  void cancel() => _timer.cancel();
}
