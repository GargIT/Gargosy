import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/romm/romm_admin.dart';
import '../core/romm/romm_service.dart';
import '../l10n/tr.dart';
import '../providers/library_providers.dart';
import '../providers/romm_providers.dart';

/// A RomM scan Gargosy started (#245): Settings → RomM library's Scan
/// library, or after an upload. Followed until it ends, wherever the player
/// goes meanwhile.
@immutable
class LibraryScanState {
  const LibraryScanState({this.starting = false, this.taskId, this.progress, this.error, this.platformIds = const []});

  final bool starting;

  /// RomM's task, while it's followed.
  final String? taskId;
  final ScanProgress? progress;

  /// Why the last scan didn't start or was lost.
  final String? error;

  /// The platforms it scans; none: the whole library.
  final List<int> platformIds;

  bool get running => starting || (taskId != null && (progress?.running ?? true));
}

class LibraryScanNotifier extends StateNotifier<LibraryScanState> {
  LibraryScanNotifier(this._romm, this._onFinished, {this.every = const Duration(seconds: 2)})
    : super(const LibraryScanState());

  final RommService? _romm;
  final void Function() _onFinished;

  /// How often RomM is asked how the scan goes.
  final Duration every;
  Timer? _timer;

  /// Starts a [kind] scan of the library or of [platformIds]. Gives null
  /// once RomM took it, else why not (a scan already running among them).
  Future<String?> start(ScanKind kind, {List<int> platformIds = const []}) async {
    final romm = _romm;
    if (romm == null) return tr('RomM can\'t be reached.');
    if (state.running) return tr('A scan is running already.');
    state = LibraryScanState(starting: true, platformIds: platformIds);
    try {
      final id = await romm.startScan(kind, platformIds: platformIds);
      if (!mounted) return null;
      state = LibraryScanState(taskId: id, platformIds: platformIds);
      _timer?.cancel();
      _timer = Timer.periodic(every, (_) => _look());
      unawaited(_look());
      return null;
    } on Object catch (e) {
      // RomM's reason as it gave it; a network error in words, not Dio's.
      final why = e is RommAdminRefused ? e.message : tr("RomM can't be reached.");
      debugPrint('[Scan] not started: $e');
      if (mounted) state = LibraryScanState(error: why);
      return why;
    }
  }

  bool _looking = false;

  Future<void> _look() async {
    final romm = _romm;
    final id = state.taskId;
    if (romm == null || id == null || _looking) return;
    _looking = true;
    try {
      final p = await romm.scanProgress(id);
      if (!mounted || state.taskId != id) return;
      state = LibraryScanState(taskId: id, progress: p, platformIds: state.platformIds);
      if (!p.running) {
        _timer?.cancel();
        _onFinished();
      }
    } on Object catch (e) {
      if (e is RommAdminRefused && e.status == 404) {
        // RomM no longer has the task (a restart, its record expired).
        _timer?.cancel();
        if (mounted) state = LibraryScanState(error: e.message);
        return;
      }
      // A proxy's 502, a busy worker's 503, or out of reach for now: the
      // scan goes on on RomM, so it's asked again at the next look.
      debugPrint('[Scan] $id not read: $e');
    } finally {
      _looking = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The scan of the profile's RomM; the library is read again when it ends.
final libraryScanProvider = StateNotifierProvider<LibraryScanNotifier, LibraryScanState>((ref) {
  return LibraryScanNotifier(ref.watch(rommServiceProvider), () {
    // What a gallery already loaded holds stays until it's opened again.
    ref.invalidate(platformsProvider);
    ref.invalidate(galleryScopeProvider);
  });
});

/// A scan's progress in words ("Scanned 120 of 3 400 games · 12 new").
String scanLine(LibraryScanState s) {
  if (s.starting) return tr('Starting the scan…');
  final p = s.progress;
  if (s.taskId != null && p == null) return tr('Waiting for RomM…');
  if (p == null) return s.error ?? '';
  final counts = p.totalGames > 0
      ? tr('Scanned {0} of {1} games', [p.scannedGames, p.totalGames])
      : tr('Scanned {0} games', [p.scannedGames]);
  final news = p.newGames > 0 ? ' · ${tr('{0} new', [p.newGames])}' : '';
  return switch (p.status) {
    'queued' || 'deferred' || 'scheduled' => tr('Waiting for RomM to start the scan…'),
    'finished' => '${tr('Scan done.')} $counts$news',
    'failed' => tr('The scan failed on RomM. Its log says why.'),
    'stopped' || 'canceled' => tr('The scan was stopped.'),
    _ => '$counts$news',
  };
}
