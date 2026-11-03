import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../library/download_schedule.dart';
import '../library/game_videos.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_providers.dart';
import 'download_providers.dart';
import 'romm_providers.dart';

/// Settings → Display → Video previews (#238); off without preferences.
final videoPreviewsOnProvider = Provider<bool>((ref) {
  final prefs = watchAppPreferencesOrNull(ref);
  return prefs != null && VideoPreviews.on(prefs);
});

/// Games' videos for the active profile's RomM: one folder per server, so
/// two servers' game ids never meet. Kept while the profile is open (what
/// downloads and what failed is remembered); whether a video may download
/// is asked each time: RomM reachable, no ROM downloading, no speed limit
/// set and inside the download hours (#228: a video never competes with them).
final gameVideosProvider = Provider<GameVideos?>((ref) {
  final profile = ref.watch(activeProfileProvider);
  if (profile == null) return null;
  final root = ref.watch(appRootProvider);
  final romm = ref.watch(rommServiceProvider);
  bool mayDownload() {
    if (ref.read(rommOfflineProvider)) return false;
    if (ref.read(downloadsProvider.notifier).pending > 0) return false;
    final limits = DownloadLimits.of(ref.read(appPreferencesProvider));
    if (limits.megabytesPerSecond > 0) return false;
    return limits.window?.allows(DateTime.now()) ?? true;
  }

  return GameVideos(
    guard: PathGuard(root),
    root: videoCacheDir(root),
    dir: p.join(videoCacheDir(root), videoServerKey(profile.profile.serverUrl)),
    download: romm?.downloadVideo,
    mayDownload: mayDownload,
  );
});
