import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../library/game_videos.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_providers.dart';
import 'romm_providers.dart';

/// Settings → Display → Video previews (#238); off without preferences.
final videoPreviewsOnProvider = Provider<bool>((ref) {
  final prefs = watchAppPreferencesOrNull(ref);
  return prefs != null && VideoPreviews.on(prefs);
});

/// Games' videos for the active profile's RomM: one folder per server, so
/// two servers' game ids never meet; no download while RomM is away.
final gameVideosProvider = Provider<GameVideos?>((ref) {
  final profile = ref.watch(activeProfileProvider);
  if (profile == null) return null;
  final root = ref.watch(appRootProvider);
  final romm = ref.watch(rommServiceProvider);
  final offline = ref.watch(rommOfflineProvider);
  final server = sha1.convert(utf8.encode(profile.profile.serverUrl.toLowerCase())).toString().substring(0, 12);
  return GameVideos(
    guard: PathGuard(root),
    dir: p.join(videoCacheDir(root), server),
    download: romm == null || offline ? null : romm.downloadVideo,
  );
});
