import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/romm/install_request.dart';
import '../core/romm/romm_models.dart';
import '../core/storage/app_preferences.dart';
import '../l10n/tr.dart';

/// Whether the profile takes games sent to this PC from RomM's web page
/// (#288): its own pref `romm.remoteInstall`, on by default.
class RemoteInstallSetting {
  static const key = 'romm.remoteInstall';

  static bool of(AppPreferences? prefs) => prefs?.getBool(key) ?? true;
}

/// What [RemoteInstalls] needs of RomM, for one device; the seam tests fake.
abstract class RemoteInstallApi {
  Future<InstallClaim> claim();
  Future<void> report(String requestId, InstallOutcome outcome, {String? reason});
}

/// How the last look at RomM went, for Settings.
enum RemoteInstallState {
  /// Not looked yet, or RomM couldn't be reached.
  unknown,

  /// RomM takes requests for this PC.
  ready,

  /// RomM has installs turned off, or is older than 5.4.
  off,

  /// The profile's login isn't paired, so it can't take them.
  notPaired,
}

/// What happened to each request RomM sent this profile, kept in its prefs
/// (`romm.remoteInstall.requests`, the newest [max]): started, or how it
/// ended. A request RomM gives again (a report that didn't reach it, a
/// restart) is told the same, never downloaded again after it ended, and a
/// game on this PC is `done` only when Gargosy started it.
class RemoteInstallLog {
  RemoteInstallLog(this._prefs);

  static const key = 'romm.remoteInstall.requests';
  static const max = 200;
  static const started = 'started';
  final AppPreferences? _prefs;

  Map<String, Object?> _read() {
    final raw = _prefs?.getString(key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw);
      return map is Map<String, dynamic> ? Map.of(map) : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(String id, Object value) async {
    final all = _read()
      ..remove(id)
      ..[id] = value;
    final keep = all.length <= max ? all : Map.fromEntries(all.entries.skip(all.length - max));
    await _prefs?.setString(key, jsonEncode(keep));
  }

  bool wasStarted(String id) => _read()[id] == started;

  /// How [id] ended, with its reason; null while it hasn't.
  (InstallOutcome, String?)? outcomeOf(String id) {
    final v = _read()[id];
    if (v is! Map) return null;
    final outcome = InstallOutcome.values.where((o) => o.name == v['outcome']).firstOrNull;
    if (outcome == null) return null;
    final reason = v['reason'];
    return (outcome, reason is String ? reason : null);
  }

  Future<void> start(String id) => _write(id, started);

  Future<void> end(String id, InstallOutcome outcome, String? reason) =>
      _write(id, {'outcome': outcome.name, 'reason': ?reason});
}

/// Games sent to this PC from RomM's web page (#288): RomM's requests are
/// claimed every [every] while the profile is open and RomM reachable, each
/// game goes into the download queue (its space check, hours and the age
/// limit apply), and RomM is told how it ended: done, already on this PC, or
/// failed with why. What can't be decided now (RomM didn't give the game, the
/// queue didn't take it) waits for the next claim; RomM drops a request
/// nobody touched for two days.
class RemoteInstalls {
  RemoteInstalls({
    required this.api,
    required this.log,
    required this.gameOf,
    required this.download,
    required this.isOnPc,
    required this.isPending,
    required this.errorOf,
    required this.allows,
    this.remember,
    this.onStarted,
    this.advertise,
    this.isOffline,
    this.every = const Duration(seconds: 60),
  });

  final RemoteInstallApi api;
  final RemoteInstallLog log;

  /// RomM's game by id; null when it can't be had now.
  final Future<Game?> Function(String romId) gameOf;

  /// Queues the game; completes when its download has ended.
  final Future<void> Function(Game game) download;
  final bool Function(Game game) isOnPc;

  /// Whether the game waits or downloads in the queue now.
  final bool Function(Game game) isPending;

  /// Why the game's download failed, when it did.
  final String? Function(Game game) errorOf;

  /// Whether the profile may have the game (its age limit).
  final bool Function(Game game) allows;

  /// Puts a game already on this PC (another profile's download) in the
  /// profile's library.
  final Future<void> Function(Game game)? remember;

  /// Told when a sent game goes into the queue.
  final void Function(Game game)? onStarted;

  /// Tells RomM this PC takes requests; asked again until it says so.
  final Future<bool> Function()? advertise;
  final bool Function()? isOffline;
  final Duration every;

  /// How the last claim went.
  final state = ValueNotifier(RemoteInstallState.unknown);

  final _working = <String>{};
  Timer? _timer;
  Future<void>? _checking;
  bool _advertised = false;
  bool _disposed = false;

  /// Looks now, then every [every].
  void watch() {
    _timer ??= Timer.periodic(every, (_) => unawaited(check()));
    unawaited(check());
  }

  /// Claims RomM's requests and starts each one not already under way. One
  /// look at a time; never throws.
  Future<void> check() => _checking ??= _check().whenComplete(() => _checking = null);

  Future<void> _check() async {
    if (_disposed || (isOffline?.call() ?? false)) return;
    if (!_advertised && advertise != null) _advertised = await advertise!();
    if (_disposed) return;
    final InstallClaim claim;
    try {
      claim = await api.claim();
    } catch (e) {
      debugPrint('[Install] RomM could not be asked: $e');
      return;
    }
    if (_disposed) return;
    switch (claim) {
      case InstallsOff():
        state.value = RemoteInstallState.off;
      case InstallsNotBound():
        state.value = RemoteInstallState.notPaired;
      case InstallsTaken(:final requests):
        state.value = RemoteInstallState.ready;
        for (final r in requests) {
          if (_working.add(r.id)) unawaited(_handle(r).whenComplete(() => _working.remove(r.id)));
        }
    }
  }

  Future<void> _handle(InstallRequest r) async {
    try {
      if (log.outcomeOf(r.id) case (final outcome, final reason)) return await _report(r, outcome, reason);
      final game = await gameOf(r.romId);
      if (_disposed) return;
      if (game == null) {
        debugPrint('[Install] request ${r.id}: RomM gave no game ${r.romId} now; next claim');
        return;
      }
      if (isOnPc(game)) {
        if (log.wasStarted(r.id)) return await _end(r, InstallOutcome.done);
        await remember?.call(game);
        return await _end(r, InstallOutcome.alreadyInstalled);
      }
      if (!allows(game)) {
        return await _end(r, InstallOutcome.failed, tr('The game is above this profile\'s age limit.'));
      }
      final already = isPending(game);
      final done = download(game);
      if (!isPending(game)) {
        // Refused at once (no room), or no queue to take it now.
        await done;
        final error = errorOf(game);
        if (error != null) return await _end(r, InstallOutcome.failed, error);
        debugPrint('[Install] request ${r.id}: the queue didn\'t take ${game.id}; next claim');
        return;
      }
      debugPrint('[Install] request ${r.id}: downloading ${game.id}');
      await log.start(r.id);
      if (!already) onStarted?.call(game);
      await done;
      if (_disposed) return;
      if (isOnPc(game)) return await _end(r, InstallOutcome.done);
      await _end(r, InstallOutcome.failed, errorOf(game) ?? tr('The download was cancelled on this PC.'));
    } catch (e) {
      debugPrint('[Install] request ${r.id} failed: $e');
    }
  }

  /// Keeps how [r] ended, then tells RomM.
  Future<void> _end(InstallRequest r, InstallOutcome outcome, [String? reason]) async {
    if (_disposed) return;
    await log.end(r.id, outcome, reason);
    await _report(r, outcome, reason);
  }

  Future<void> _report(InstallRequest r, InstallOutcome outcome, String? reason) async {
    if (_disposed) return;
    debugPrint('[Install] request ${r.id}: ${outcome.name}${reason == null ? '' : ' ($reason)'}');
    try {
      await api.report(r.id, outcome, reason: reason);
    } catch (e) {
      // Kept: RomM gives the request again at the next claim and hears the same.
      debugPrint('[Install] RomM was not told about request ${r.id}: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    state.dispose();
  }
}
