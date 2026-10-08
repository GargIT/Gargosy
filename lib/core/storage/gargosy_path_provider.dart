// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// `path_provider` for Gargosy: the app's own folders live in `userdata\app\`;
/// anything else (Downloads, …) still comes from [previous].
class GargosyPathProvider extends PathProviderPlatform {
  GargosyPathProvider({required this.appDataDir, required this.previous});

  final String appDataDir;
  final PathProviderPlatform previous;

  @override
  Future<String?> getApplicationSupportPath() async => p.join(appDataDir, 'support');

  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(appDataDir, 'documents');

  @override
  Future<String?> getTemporaryPath() async => p.join(appDataDir, 'temp');

  @override
  Future<String?> getApplicationCachePath() async => p.join(appDataDir, 'cache');

  @override
  Future<String?> getLibraryPath() => previous.getLibraryPath();

  @override
  Future<String?> getDownloadsPath() => previous.getDownloadsPath();

  @override
  Future<String?> getExternalStoragePath() => previous.getExternalStoragePath();

  @override
  Future<List<String>?> getExternalCachePaths() => previous.getExternalCachePaths();

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) =>
      previous.getExternalStoragePaths(type: type);
}
