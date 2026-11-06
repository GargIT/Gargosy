import 'dart:async';

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

/// Games sent to this PC from RomM's web page (#288): RomM's requests are
/// claimed every [every] while the profile is open and RomM reachable, each
/// game goes into the download queue (its space check, hours and the age
/// limit apply), and RomM is told how it ended: done, already on this PC, or
/// failed with why. A request RomM gives again (Gargosy restarted, a report
/// that didn't reach it) is looked at afresh, so nothing is lost.
class RemoteInstalls {
  RemoteInstalls({
    required this.api,
    required this.gameOf,
    required this.download,
    required this.isOnPc,
    required this.installedAt,
    required this.errorOf,
    required this.allows,
    this.onStarted,
    this.isOffline,
    this.every = const Duration(seconds: 60),
  });

  final RemoteInstallApi api;

  /// RomM's game by id; null when RomM doesn't have it (or won't show it).
  final Future<Game?> Function(String romId) gameOf;

  /// Queues the game; completes when its download has ended.
  final Future<void> Function(Game game) download;
  final bool Function(Game game) isOnPc;
  final DateTime? Function(Game game) installedAt;

  /// Why the game's download failed, when it did.
  final String? Function(Game game) errorOf;

  /// Whether the profile may have the game (its age limit).
  final bool Function(Game game) allows;

  /// Told when a sent game goes into the queue.
  final void Function(Game game)? onStarted;
  final bool Function()? isOffline;
  final Duration every;

  /// How the last claim went.
  final state = ValueNotifier(RemoteInstallState.unknown);

  final _working = <String>{};

  /// Requests whose game this run downloaded: done, whatever the file's time.
  final _downloaded = <String>{};
  Timer? _timer;
  Future<void>? _checking;
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
      final game = await gameOf(r.romId);
      if (game == null) {
        return await _report(r, InstallOutcome.failed, tr('RomM didn\'t give the game to this PC.'));
      }
      if (isOnPc(game)) {
        // On this PC since the request came: Gargosy got it (before a
        // restart, or the player did); else it was here already.
        final at = installedAt(game);
        final sent = r.createdAt;
        final ours = _downloaded.contains(r.id) || (at != null && sent != null && !at.isBefore(sent));
        return await _report(r, ours ? InstallOutcome.done : InstallOutcome.alreadyInstalled);
      }
      if (!allows(game)) {
        return await _report(r, InstallOutcome.failed, tr('The game is above this profile\'s age limit.'));
      }
      debugPrint('[Install] request ${r.id}: downloading ${game.id}');
      onStarted?.call(game);
      await download(game);
      if (_disposed) return;
      if (isOnPc(game)) {
        _downloaded.add(r.id);
        return await _report(r, InstallOutcome.done);
      }
      await _report(r, InstallOutcome.failed, errorOf(game) ?? tr('The download was cancelled on this PC.'));
    } catch (e) {
      debugPrint('[Install] request ${r.id} failed: $e');
    }
  }

  Future<void> _report(InstallRequest r, InstallOutcome outcome, [String? reason]) async {
    if (_disposed) return;
    debugPrint('[Install] request ${r.id}: ${outcome.name}${reason == null ? '' : ' ($reason)'}');
    try {
      await api.report(r.id, outcome, reason: reason);
    } catch (e) {
      // RomM gives the request again at the next claim, and it's looked at afresh.
      debugPrint('[Install] RomM was not told about request ${r.id}: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    state.dispose();
  }
}
