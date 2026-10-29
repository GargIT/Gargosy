import 'package:path/path.dart' as p;

import '../core/platform/platform_info.dart';
import 'app_root.dart';

class PathGuardException implements Exception {
  PathGuardException(this.path, this.reason);
  final String path;
  final String reason;

  @override
  String toString() => 'PathGuardException: $path ($reason)';
}

/// Every write Gargosy makes goes through [check] or [join] (spec §8): only
/// `roms\`, `emulators\`, `bios\`, `userdata\templates\`, `userdata\app\`,
/// `userdata\settings.json` and the active profile's folder are writable.
///
/// Paths compare as the file system does (#204): any case on Windows and
/// macOS, exactly elsewhere. On Linux `roms/` and `ROMS/` are two folders,
/// and a server path that matches an allowed folder only when lowercased
/// is refused.
class PathGuard {
  PathGuard(this.root, {this.activeProfileId, PlatformInfo? platform}) : _platform = platform ?? PlatformInfo.current;

  final AppRoot root;
  final String? activeProfileId;
  final PlatformInfo _platform;

  /// Whether `a` and `A` are different names here.
  bool get caseSensitive => !(_platform.isWindows || _platform.isMacOS);

  PathGuard forProfile(String id) => PathGuard(root, activeProfileId: id, platform: _platform);

  /// [path] absolute and normalized, without a trailing separator, in the
  /// case it compares in: two paths to one place give the same key.
  String pathKey(String path) {
    final full = p.normalize(p.absolute(path)).replaceAll(RegExp(r'[\\/]+$'), '');
    return caseSensitive ? full : full.toLowerCase();
  }

  /// Whether [a] and [b] are the same place, as the file system compares.
  bool samePath(String a, String b) => pathKey(a) == pathKey(b);

  List<String> get _allowedDirs => [
    root.roms,
    root.emulators,
    root.bios,
    root.templates,
    root.appData,
    if (activeProfileId != null) p.join(root.profiles, activeProfileId),
  ];

  /// [path], absolute and normalized, if it may be written; throws otherwise.
  String check(String path) {
    final full = p.normalize(p.absolute(path));
    final key = pathKey(full);
    if (key == pathKey(root.settingsFile)) return full;
    for (final dir in _allowedDirs) {
      final d = pathKey(dir);
      if (key == d || key.startsWith('$d${p.separator}')) return full;
    }
    throw PathGuardException(full, "outside Gargosy's writable folders");
  }

  /// [name] (e.g. from a server) under [dir], checked. Rejects absolute names,
  /// drive letters, `..` and empty names.
  String join(String dir, String name) {
    if (name.isEmpty ||
        name.contains(':') ||
        name.startsWith(r'\') ||
        name.startsWith('/') ||
        p.split(name).contains('..')) {
      throw PathGuardException(name, 'not a plain relative name');
    }
    return check(p.join(dir, name));
  }
}
