import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/romm/romm_models.dart';
import '../library/disk_space.dart';
import '../library/download_service.dart';
import '../library/dsi_title.dart';
import '../library/library_snapshot.dart';
import '../library/rom_files.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_providers.dart';
import 'romm_providers.dart';

final romFilesProvider = Provider<RomFiles>((ref) => RomFiles(ref.watch(appRootProvider)));

/// The free space on a path's drive (#142); tests give their own.
final freeSpaceProvider = Provider<FreeSpaceOf>((ref) => windowsFreeSpace);

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
    freeSpace: ref.watch(freeSpaceProvider),
  );
});

/// Downloads in progress (and failed ones, until dismissed), by game id.
class DownloadsNotifier extends StateNotifier<Map<String, DownloadProgress>> {
  DownloadsNotifier(this._ref) : super(const {});

  final Ref _ref;
  final _cancels = <String, CancelToken>{};

  void _set(String id, DownloadProgress? progress) {
    final next = Map<String, DownloadProgress>.from(state);
    if (progress == null) {
      next.remove(id);
    } else {
      next[id] = progress;
    }
    state = next;
  }

  Future<void> start(Game game) async {
    final service = _ref.read(downloadServiceProvider);
    final running = state[game.id];
    if (service == null || (running != null && running.phase == DownloadPhase.downloading)) return;
    final cancel = CancelToken();
    _cancels[game.id] = cancel;
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
      await _ref.read(librarySnapshotProvider)?.remember(game);
    } on DioException catch (e) {
      if (!mounted) return;
      _set(game.id, CancelToken.isCancel(e) ? null : DownloadProgress(DownloadPhase.failed, error: e.message ?? '$e'));
    } on Object catch (e) {
      if (!mounted) return;
      _set(game.id, DownloadProgress(DownloadPhase.failed, error: '$e'));
    } finally {
      _cancels.remove(game.id);
      if (mounted) _ref.read(romFilesVersionProvider.notifier).state++;
    }
  }

  void cancel(String gameId) => _cancels[gameId]?.cancel();

  void cancelAll() {
    for (final c in _cancels.values) {
      c.cancel();
    }
  }

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
