import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_play_sessions.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_providers.dart';
import '../providers/engine_providers.dart';
import '../providers/romm_providers.dart';

/// The profile's play sessions on this PC (#146), in its `prefs.json`: each
/// game played, kept until RomM has it, and the time played of a RomM
/// without play sessions. The newest [keep] are kept.
class PlayTimeLog {
  PlayTimeLog(this._prefs);

  final ProfilePreferences _prefs;

  static const key = 'playtime.sessions';
  static const keep = 1000;

  List<PlaySessionRecord> get all {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      return [
        if (list is List)
          for (final e in list) ?PlaySessionRecord.fromJson(e),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _save(List<PlaySessionRecord> list) {
    final kept = list.length > keep ? list.sublist(list.length - keep) : list;
    return _prefs.setString(key, jsonEncode([for (final s in kept) s.toJson()]));
  }

  Future<void> add(PlaySessionRecord s) => _save([...all, s]);

  /// The sessions RomM doesn't have yet, oldest first.
  List<PlaySessionRecord> get unsent => [
    for (final s in all)
      if (!s.sent) s,
  ];

  /// [gameId]'s time from this PC's sessions; [unsentOnly] counts only those
  /// RomM doesn't have yet.
  PlayTime timeFor(String gameId, {bool unsentOnly = false}) {
    var total = Duration.zero;
    var n = 0;
    for (final s in all) {
      if (s.gameId != gameId || (unsentOnly && s.sent)) continue;
      total += s.length;
      n++;
    }
    return PlayTime(total, n, thisPcOnly: true);
  }

  /// Sends what RomM hasn't got, a batch at a time; stops at the first
  /// failure (tried again after the next game). Never throws.
  Future<void> sendUnsent(PlaySessionsApi api) async {
    while (true) {
      final batch = unsent.take(PlaySessionsApi.batch).toList();
      if (batch.isEmpty) return;
      try {
        await api.record(batch);
      } on Object {
        return;
      }
      final sent = {for (final s in batch) s.toJson().toString()};
      await _save([for (final s in all) sent.contains(s.toJson().toString()) ? s.asSent() : s]);
    }
  }
}

/// RomM's play sessions for the active profile; null with no RomM.
final playSessionsApiProvider = Provider<PlaySessionsApi?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  // Watched: built again once this PC gets its device id.
  final device = ref.watch(activeProfileProvider.select((c) => c?.login.deviceId));
  return romm == null ? null : RommPlaySessions(romm.dio, () => romm.authOptions, deviceId: () => device);
});

final playTimeLogProvider = Provider<PlayTimeLog?>((ref) {
  final prefs = ref.watch(profilePrefsProvider);
  return prefs == null ? null : PlayTimeLog(prefs);
});

/// A game's time played: RomM's sessions from every device, with this PC's
/// that haven't reached it yet; this PC's alone when RomM has none or can't
/// be asked. Null when nothing has been played.
final playTimeProvider = FutureProvider.autoDispose.family<PlayTime?, String>((ref, gameId) async {
  final log = ref.watch(playTimeLogProvider);
  final api = ref.watch(playSessionsApiProvider);
  final local = log?.timeFor(gameId);
  PlayTime? remote;
  if (api != null) {
    try {
      remote = await api.timeFor(gameId);
    } on Object {
      remote = null;
    }
  }
  final PlayTime? time;
  if (remote == null) {
    time = local;
  } else {
    final waiting = log?.timeFor(gameId, unsentOnly: true);
    time = PlayTime(remote.total + (waiting?.total ?? Duration.zero), remote.sessions + (waiting?.sessions ?? 0));
  }
  return time == null || time.sessions == 0 ? null : time;
});
