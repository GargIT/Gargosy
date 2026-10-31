import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/platform/platform_info.dart';
import '../core/romm/romm_models.dart';
import '../library/disk_space.dart';
import '../library/download_check.dart';
import '../library/download_schedule.dart';
import '../library/download_service.dart';
import '../library/dsi_title.dart';
import '../library/game_manual.dart';
import '../library/library_snapshot.dart';
import '../library/rom_files.dart';
import '../library/throttled_download.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_providers.dart';
import 'romm_providers.dart';
import '../l10n/tr.dart';

final romFilesProvider = Provider<RomFiles>((ref) => RomFiles(ref.watch(appRootProvider)));

/// The time the download window is checked against (#228); tests set it.
final downloadClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The volumes and their free space (#142, #201); tests give their own.
final diskInfoProvider = Provider<DiskInfo>((ref) => diskInfoFor(PlatformInfo.current));

/// Bumped after a download or a delete, so "downloaded?" is read again.
final romFilesVersionProvider = StateProvider<int>((ref) => 0);

/// The volumes' free space for screens (#7 of the 2026-10-30 review): read
/// at most every [DiskUsageCache.refresh], not on every build, and afresh
/// after a download or a delete.
final diskUsageProvider = Provider<DiskUsageCache>((ref) {
  ref.watch(romFilesVersionProvider);
  return DiskUsageCache(ref.watch(diskInfoProvider));
});

bool watchDownloaded(WidgetRef ref, Game g) {
  ref.watch(romFilesVersionProvider);
  return ref.read(romFilesProvider).isDownloaded(g);
}

/// The DSi header of a game on this PC (#114), by its path.
final dsiTitleProvider = FutureProvider.autoDispose.family<DsiTitle?, String>((ref, path) => readDsiTitle(path));

final downloadServiceProvider = Provider<DownloadService?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return null;
  final root = ref.watch(appRootProvider);
  return DownloadService(
    // Paced to Settings' speed limit (#228), read for each chunk.
    dio: throttledDio(romm.dio, () => DownloadLimits.speedOf(ref.read(appPreferencesProvider))),
    auth: () => romm.authOptions,
    files: ref.watch(romFilesProvider),
    guard: PathGuard(root), // roms\ and userdata\app\ are shared, not per profile
    tempDir: p.join(root.appData, 'temp'),
    urlFor: romm.getDownloadUrl,
    detail: romm.getGame,
    disk: ref.watch(diskInfoProvider),
    checkHashes: () => DownloadCheck.of(ref.read(appPreferencesProvider)),
  );
});

/// Downloads waiting, running and failed (until dismissed), by game id. One
/// runs at a time, the others wait in [queue] order (#143); [finished]
/// lists this session's done ones.
class DownloadsNotifier extends StateNotifier<Map<String, DownloadProgress>> {
  DownloadsNotifier(this._ref) : super(const {});

  final Ref _ref;
  final _cancels = <String, CancelToken>{};
  final _games = <String, Game>{};
  final _queue = <Game>[];
  final _waiting = <String, Completer<void>>{};
  final _startedAt = <String, DateTime>{};
  final _finished = <Game>[];
  Game? _current;

  /// The one downloading or unpacking now.
  Game? get current => _current;

  /// Waiting, first to go first.
  List<Game> get queue => List.unmodifiable(_queue);

  /// Done this session, newest first.
  List<Game> get finished => List.unmodifiable(_finished);

  /// The games that failed, until retried or dismissed.
  List<Game> get failed => [
    for (final MapEntry(:key, :value) in state.entries)
      if (value.phase == DownloadPhase.failed && _games[key] != null) _games[key]!,
  ];

  /// When [gameId]'s download began (not when it was queued).
  DateTime? startedAt(String gameId) => _startedAt[gameId];

  void _set(String id, DownloadProgress? progress) {
    final next = Map<String, DownloadProgress>.from(state);
    if (progress == null) {
      next.remove(id);
    } else {
      next[id] = progress;
    }
    state = next;
  }

  /// Queues [game]; completes when its download has ended (done, failed or
  /// cancelled). A game already waiting or running isn't queued again.
  Future<void> start(Game game) {
    if (_ref.read(downloadServiceProvider) == null) return Future.value();
    if (state[game.id]?.phase.active ?? false) return _waiting[game.id]?.future ?? Future.value();
    _games[game.id] = game;
    // Room for it and for everything before it (#143): refused now, not
    // when its turn comes.
    if (spaceFor(game) case final e?) {
      _set(game.id, DownloadProgress(DownloadPhase.failed, error: tr('With the downloads before it: {0}', [e])));
      return Future.value();
    }
    _queue.add(game);
    final done = _waiting[game.id] = Completer<void>();
    _set(game.id, const DownloadProgress(DownloadPhase.queued));
    _next();
    return done.future;
  }

  /// Queues [games] together (Download all, #226): one space check for all
  /// of them with everything before, one state change. Those waiting or
  /// running already are left as they are. Throws [NotEnoughSpace] (nothing
  /// queued) when they don't fit.
  void startAll(List<Game> games) {
    if (_ref.read(downloadServiceProvider) == null) return;
    final fresh = [
      for (final g in games)
        if (!(state[g.id]?.phase.active ?? false)) g,
    ];
    if (fresh.isEmpty) return;
    checkSpace({
      _ref.read(appRootProvider).roms: fresh.fold(stillToCome(), (n, g) => n + g.fileSize),
    }, _ref.read(diskInfoProvider));
    final next = Map<String, DownloadProgress>.from(state);
    for (final g in fresh) {
      _games[g.id] = g;
      _queue.add(g);
      _waiting[g.id] = Completer<void>();
      next[g.id] = const DownloadProgress(DownloadPhase.queued);
    }
    state = next;
    _next();
  }

  /// Why [game] wouldn't fit with everything before it (#227: Make room
  /// offers to free it); null when it fits, or isn't checked.
  NotEnoughSpace? spaceFor(Game game) {
    try {
      // A multi-file game is a zip unpacked beside itself in the Gargosy
      // folder: twice its size for a while.
      final size = game.isMultiFile ? game.fileSize * 2 : game.fileSize;
      checkSpace({_ref.read(appRootProvider).roms: size + _stillToCome()}, _ref.read(diskInfoProvider));
      return null;
    } on NotEnoughSpace catch (e) {
      return e;
    }
  }

  /// What the queue and the running download will still write.
  int stillToCome() => _stillToCome();

  int _stillToCome() {
    final running = _current == null ? 0 : _current!.fileSize - (state[_current!.id]?.received ?? 0);
    return _queue.fold(running.clamp(0, 1 << 62), (n, g) => n + g.fileSize);
  }

  /// When the queue starts again, while Only download keeps it waiting
  /// (#228); null when it isn't waiting.
  DateTime? get waitsUntil => _waitsUntil;
  DateTime? _waitsUntil;
  Timer? _wake;

  /// Games the player said to download now, outside the window.
  final _now = <String>{};

  /// Download now (#228): [gameId] first, and started even outside the
  /// window.
  void startNow(String gameId) {
    _now.add(gameId);
    moveToFront(gameId);
    _next();
  }

  /// The window or speed changed in Settings: the queue looks again.
  void limitsChanged() => _next();

  void _next() {
    if (_current != null || _queue.isEmpty || !mounted) return;
    final window = DownloadLimits.of(_ref.read(appPreferencesProvider)).window;
    final now = _ref.read(downloadClockProvider)();
    if (window != null && !window.allows(now) && !_now.contains(_queue.first.id)) {
      final at = window.opensAt(now);
      _wake?.cancel();
      // Looked at again every minute, not once at the opening: a PC asleep
      // in between, or a changed clock, would miss it.
      final left = at.difference(now);
      _wake = Timer(left < const Duration(minutes: 1) ? left : const Duration(minutes: 1), _next);
      _waitsUntil = at;
      state = Map.of(state); // listeners read waitsUntil
      return;
    }
    _wake?.cancel();
    _wake = null;
    _waitsUntil = null;
    final game = _current = _queue.removeAt(0);
    _now.remove(game.id);
    _run(game).whenComplete(() {
      _current = null;
      _waiting.remove(game.id)?.complete();
      _next();
    });
  }

  Future<void> _run(Game game) async {
    final service = _ref.read(downloadServiceProvider);
    if (service == null) return _set(game.id, null);
    final cancel = CancelToken();
    _cancels[game.id] = cancel;
    _startedAt[game.id] = DateTime.now();
    _set(game.id, const DownloadProgress(DownloadPhase.downloading));
    try {
      await service.download(
        game,
        cancel: cancel,
        onProgress: (pr) {
          if (mounted && pr.phase != DownloadPhase.done) _set(game.id, pr);
        },
      );
      if (!mounted) return;
      _set(game.id, null);
      _finished
        ..removeWhere((g) => g.id == game.id)
        ..insert(0, game);
      if (_finished.length > 20) _finished.removeLast();
      await _ref.read(librarySnapshotProvider)?.remember(game);
    } on DioException catch (e) {
      if (!mounted) return;
      _set(game.id, CancelToken.isCancel(e) ? null : DownloadProgress(DownloadPhase.failed, error: e.message ?? '$e'));
    } on Object catch (e) {
      if (!mounted) return;
      _set(game.id, DownloadProgress(DownloadPhase.failed, error: '$e'));
    } finally {
      _cancels.remove(game.id);
      _startedAt.remove(game.id);
      if (mounted) _ref.read(romFilesVersionProvider.notifier).state++;
    }
  }

  /// Stops [gameId]'s download, or takes it out of the queue.
  void cancel(String gameId) {
    _now.remove(gameId);
    final i = _queue.indexWhere((g) => g.id == gameId);
    if (i >= 0) {
      _queue.removeAt(i);
      _waiting.remove(gameId)?.complete();
      _stopWaitingWhenEmpty();
      _set(gameId, null);
      return;
    }
    _cancels[gameId]?.cancel();
  }

  /// Nothing queued: no wait for the window, nothing to say until when.
  void _stopWaitingWhenEmpty() {
    if (_queue.isNotEmpty) return;
    _wake?.cancel();
    _wake = null;
    _waitsUntil = null;
  }

  /// Puts a waiting [gameId] first in the queue.
  void moveToFront(String gameId) {
    final i = _queue.indexWhere((g) => g.id == gameId);
    if (i <= 0) return;
    _queue.insert(0, _queue.removeAt(i));
    state = Map.of(state); // the order changed: listeners read it again
  }

  /// The queue emptied; the running download goes on (Downloads' Cancel
  /// all, #226).
  void cancelQueued() {
    final next = Map<String, DownloadProgress>.from(state);
    for (final g in _queue) {
      _waiting.remove(g.id)?.complete();
      next.remove(g.id);
    }
    _now.removeAll([for (final g in _queue) g.id]);
    _queue.clear();
    _stopWaitingWhenEmpty();
    state = next;
  }

  @override
  void dispose() {
    _wake?.cancel();
    super.dispose();
  }

  /// The queue emptied and the running download stopped (a profile switch).
  void cancelAll() {
    for (final g in _queue) {
      _waiting.remove(g.id)?.complete();
    }
    _queue.clear();
    _now.clear();
    _stopWaitingWhenEmpty();
    for (final c in _cancels.values) {
      c.cancel();
    }
  }

  /// How many are waiting or running.
  int get pending => _queue.length + (_current == null ? 0 : 1);

  /// Something for the Downloads page: waiting, running, failed or done.
  bool get anything => pending > 0 || _finished.isNotEmpty || failed.isNotEmpty;

  void dismiss(String gameId) => _set(gameId, null);

  Future<void> delete(Game game) async {
    await _ref.read(romFilesProvider).delete(game, PathGuard(_ref.read(appRootProvider)));
    await _ref.read(librarySnapshotProvider)?.forget(game.id);
    await _ref.read(gameManualsProvider)?.forget(game);
    _ref.read(romFilesVersionProvider.notifier).state++;
  }
}

/// Downloads belong to the profile that started them (its server and token):
/// switching or signing out cancels them, and their progress isn't shown to
/// another profile, whose game 7564 may be a different game (spec §4).
final downloadsProvider = StateNotifierProvider<DownloadsNotifier, Map<String, DownloadProgress>>((ref) {
  ref.watch(activeProfileProvider.select((c) => c?.profile.id));
  final notifier = DownloadsNotifier(ref);
  ref.onDispose(notifier.cancelAll);
  return notifier;
});

/// #232: the active profile's manuals (`cache\manuals\`); RomM's copies only
/// while RomM can be reached. Deleting a game from this PC removes its manual.
final gameManualsProvider = Provider<GameManuals?>((ref) {
  final profile = ref.watch(activeProfileProvider);
  if (profile == null) return null;
  final romm = ref.watch(rommServiceProvider);
  final offline = ref.watch(rommOfflineProvider);
  return GameManuals(
    guard: profile.guard,
    dir: p.join(profile.paths.cache, 'manuals'),
    download: romm == null || offline ? null : romm.downloadManual,
  );
});
