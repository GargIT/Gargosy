import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_play_sessions.dart';
import '../profiles/play_limit.dart';
import '../profiles/profile_providers.dart';
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

/// What the profile played today (#235): this PC's sessions, and RomM's
/// from its other devices (sessions started since yesterday, cut to
/// today). RomM unreachable, or this PC not known to it as a device: this
/// PC's only, never this PC's twice.
Future<Duration> playedToday({
  required PlayTimeLog? log,
  required PlaySessionsApi? api,
  required String? deviceId,
  required DateTime now,
}) async {
  final day = startOfDay(now);
  final sessions = <(DateTime, DateTime)>[for (final s in log?.all ?? const []) (s.start.toLocal(), s.end.toLocal())];
  if (api != null && deviceId != null) {
    try {
      final remote = await api.sessionsSince(DateTime(day.year, day.month, day.day - 1));
      for (final r in remote ?? const <RemoteSession>[]) {
        if (r.deviceId != deviceId) sessions.add((r.start, r.end));
      }
    } on Object catch (e) {
      debugPrint('[PlayLimit] RomM\'s sessions not read, this PC\'s only: $e');
    }
  }
  return playedOn(day, sessions);
}

/// Whether the active profile may start a game now (#235), and until when.
Future<PlayAllowance> playAllowance(Ref ref) async {
  final limit = ref.read(playLimitProvider);
  final now = ref.read(playClockProvider)();
  if (!limit.isOn) return const PlayAllowed(null);
  final used = limit.minutesPerDay == null
      ? Duration.zero
      : await playedToday(
          log: ref.read(playTimeLogProvider),
          api: ref.read(playSessionsApiProvider),
          deviceId: ref.read(activeProfileProvider)?.login.deviceId,
          now: now,
        );
  return allowanceFor(limit, used, now);
}

/// A running game's time limit: [onWarn] [PlayLimit.warnBefore] before
/// [until], [onEnd] at it. Timers, so a fake clock moves them in tests.
class PlayLimitTimer {
  PlayLimitTimer(DateTime until, DateTime now, {required void Function() onWarn, required void Function() onEnd}) {
    final left = until.difference(now);
    final warnIn = left - PlayLimit.warnBefore;
    if (warnIn > Duration.zero) {
      _warn = Timer(warnIn, onWarn);
    } else {
      onWarn();
    }
    _end = Timer(left.isNegative ? Duration.zero : left, onEnd);
  }

  Timer? _warn;
  late final Timer _end;

  void cancel() {
    _warn?.cancel();
    _end.cancel();
  }
}
