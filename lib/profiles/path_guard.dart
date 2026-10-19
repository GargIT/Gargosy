import 'package:path/path.dart' as p;

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
class PathGuard {
  PathGuard(this.root, {this.activeProfileId});

  final AppRoot root;
  final String? activeProfileId;

  PathGuard forProfile(String id) => PathGuard(root, activeProfileId: id);

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
    final lower = full.toLowerCase();
    if (lower == root.settingsFile.toLowerCase()) return full;
    for (final dir in _allowedDirs) {
      final d = dir.toLowerCase();
      if (lower == d || lower.startsWith('$d${p.separator}')) return full;
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
