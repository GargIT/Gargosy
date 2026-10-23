import 'dart:io' as io;
import 'dart:isolate';

import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/storage/app_preferences.dart';
import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_providers.dart';

/// Where covers and platform logos are kept: `userdata\app\cache\images\`,
/// its list beside it as `images.json`. Not in `temp\`, where downloads stage.
String imageCacheDir(AppRoot root) => PathGuard(root).check(p.join(root.appData, 'cache', 'images'));

/// The cache's files in [dir], made on first use.
class FolderFileSystem implements FileSystem {
  FolderFileSystem(this.dir);
  final String dir;

  @override
  Future<fs.File> createFile(String name) async {
    final d = const LocalFileSystem().directory(dir);
    if (!await d.exists()) await d.create(recursive: true);
    return d.childFile(name);
  }
}

/// How many images the cache keeps (this PC's setting, for every profile):
/// past it, the ones looked at longest ago go.
class ImageCacheSize extends StateNotifier<int> {
  ImageCacheSize(this._prefs) : super(_read(_prefs));

  static const key = 'images.cacheSize';
  static const choices = [2000, 5000, 10000, 25000, 50000];
  static const fallback = 10000;

  /// About what a small cover from RomM weighs (240 × 360 PNG).
  static const bytesPerImage = 120 * 1024;

  final AppPreferences? _prefs;

  static int _read(AppPreferences? prefs) {
    final n = int.tryParse(prefs?.getString(key) ?? '');
    return choices.contains(n) ? n! : fallback;
  }

  Future<void> pick(int n) async {
    state = n;
    await _prefs?.setString(key, '$n');
  }
}

final imageCacheSizeProvider = StateNotifierProvider<ImageCacheSize, int>(
  (ref) => ImageCacheSize(ref.watch(appPreferencesProvider)),
);

/// What the cache holds on disk now.
typedef ImageCacheUsage = ({int files, int bytes});

Future<ImageCacheUsage> imageCacheUsage(String dir) => Isolate.run(() {
  final d = io.Directory(dir);
  if (!d.existsSync()) return (files: 0, bytes: 0);
  var files = 0;
  var bytes = 0;
  for (final f in d.listSync(followLinks: false).whereType<io.File>()) {
    files++;
    bytes += f.lengthSync();
  }
  return (files: files, bytes: bytes);
});

final imageCacheUsageProvider = FutureProvider.autoDispose<ImageCacheUsage>(
  (ref) => imageCacheUsage(imageCacheDir(ref.watch(appRootProvider))),
);

/// The cache before 0.3.0 lived in `temp\gargosy-images\`, listed in
/// `support\gargosy-images.json`: both go, once, in the background.
Future<void> removeOldImageCache(AppRoot root) async {
  final guard = PathGuard(root);
  try {
    final dir = io.Directory(guard.check(p.join(root.appData, 'temp', 'gargosy-images')));
    if (await dir.exists()) await dir.delete(recursive: true);
    final list = io.File(guard.check(p.join(root.appData, 'support', 'gargosy-images.json')));
    if (await list.exists()) await list.delete();
  } on io.FileSystemException {
    // A file in use: tried again next start.
  }
}
