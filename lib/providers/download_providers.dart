import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/platform/platform_info.dart';
import '../core/romm/romm_models.dart';
import '../library/disk_space.dart';
import '../library/download_service.dart';
import '../library/dsi_title.dart';
import '../library/library_snapshot.dart';
import '../library/rom_files.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_providers.dart';
import 'romm_providers.dart';
import '../l10n/tr.dart';

final romFilesProvider = Provider<RomFiles>((ref) => RomFiles(ref.watch(appRootProvider)));

/// The volumes and their free space (#142, #201); tests give their own.
final diskInfoProvider = Provider<DiskInfo>((ref) => diskInfoFor(PlatformInfo.current));

/// Bumped after a download or a delete, so "downloaded?" is read again.
final romFilesVersionProvider = StateProvider<int>((ref) => 0);

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
    dio: romm.dio,
    auth: () => romm.authOptions,
    files: ref.watch(romFilesProvider),
    guard: PathGuard(root), // roms\ and userdata\app\ are shared, not per profile
    tempDir: p.join(root.appData, 'temp'),
    urlFor: romm.getDownloadUrl,
    detail: romm.getGame,
    disk: ref.watch(diskInfoProvider),
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
    try {
      checkSpace({_ref.read(appRootProvider).roms: game.fileSize + _stillToCome()}, _ref.read(diskInfoProvider));
    } on NotEnoughSpace catch (e) {
      _set(game.id, DownloadProgress(DownloadPhase.failed, error: tr('With the downloads before it: {0}', [e])));
      return Future.value();
    }
    _queue.add(game);
    final done = _waiting[game.id] = Completer<void>();
    _set(game.id, const DownloadProgress(DownloadPhase.queued));
    _next();
    return done.future;
  }

  /// What the queue and the running download will still write.
  int _stillToCome() {
    final running = _current == null ? 0 : _current!.fileSize - (state[_current!.id]?.received ?? 0);
    return _queue.fold(running.clamp(0, 1 << 62), (n, g) => n + g.fileSize);
  }

  void _next() {
    if (_current != null || _queue.isEmpty || !mounted) return;
    final game = _current = _queue.removeAt(0);
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
    final i = _queue.indexWhere((g) => g.id == gameId);
    if (i >= 0) {
      _queue.removeAt(i);
      _waiting.remove(gameId)?.complete();
      _set(gameId, null);
      return;
    }
    _cancels[gameId]?.cancel();
  }

  /// Puts a waiting [gameId] first in the queue.
  void moveToFront(String gameId) {
    final i = _queue.indexWhere((g) => g.id == gameId);
    if (i <= 0) return;
    _queue.insert(0, _queue.removeAt(i));
    state = Map.of(state); // the order changed: listeners read it again
  }

  /// The queue emptied and the running download stopped (a profile switch).
  void cancelAll() {
    for (final g in _queue) {
      _waiting.remove(g.id)?.complete();
    }
    _queue.clear();
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
