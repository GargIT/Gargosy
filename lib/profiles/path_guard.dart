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
  PathGuard(this.root, {this.activeProfileId, PlatformInfo? platform}) : _platform = platform ?? PlatformInfo.current {
    final id = activeProfileId;
    if (id != null && !isProfileId(id)) throw ArgumentError.value(id, 'activeProfileId', 'not a profile id');
  }

  /// A profile's id names its folder under `profiles\`: one plain name, never
  /// `..` or a path, wherever it was read from (a profile.json, a swap marker).
  static bool isProfileId(String id) => _profileId.hasMatch(id);
  static final _profileId = RegExp(r'^[a-z0-9-]{1,64}$');

  final AppRoot root;
  final String? activeProfileId;
  final PlatformInfo _platform;

  /// Whether `a` and `A` are different names here.
  bool get caseSensitive => !(_platform.isWindows || _platform.isMacOS);

  PathGuard forProfile(String id) => PathGuard(root, activeProfileId: id, platform: _platform);

  /// [path] absolute and normalized, without a trailing separator, in the
  /// case it compares in: two paths to one place give the same key.
  String pathKey(String path) => _keyOf(p.normalize(p.absolute(path)));

  /// [pathKey] of a path already absolute and normalized.
  String _keyOf(String full) {
    final key = full.replaceAll(_trailingSeparators, '');
    return caseSensitive ? key : key.toLowerCase();
  }

  static final _trailingSeparators = RegExp(r'[\\/]+$');

  /// Whether [a] and [b] are the same place, as the file system compares.
  bool samePath(String a, String b) => pathKey(a) == pathKey(b);

  /// Whether [child] is inside [parent] (not [parent] itself), as the file
  /// system compares: `p.isWithin` sees case on macOS, where this doesn't.
  bool isWithin(String parent, String child) => _keyWithin(pathKey(parent), pathKey(child));

  /// [child]'s path below [parent] (as written in [child]), when it is inside
  /// as the file system compares; null otherwise. Part by part, so a name
  /// that differs only in case still matches (`p.relative` would go `..`).
  String? relativeWithin(String parent, String child) {
    final ps = p.split(p.normalize(p.absolute(parent)));
    final cs = p.split(p.normalize(p.absolute(child)));
    if (cs.length <= ps.length) return null;
    for (var i = 0; i < ps.length; i++) {
      if (_keyOf(ps[i]) != _keyOf(cs[i])) return null;
    }
    return p.joinAll(cs.skip(ps.length));
  }

  static bool _keyWithin(String parent, String child) => child.startsWith('$parent${p.separator}');

  /// The shared places' keys (settings.json first), worked out once per
  /// [AppRoot] and case rule, not per guard: most callers make a guard for
  /// one use, and [check] runs in loops (template copies, zip entries,
  /// backups). [AppRoot] is absolute, so they don't depend on the working folder.
  static final _sharedKeys = Expando<Map<bool, List<String>>>();

  List<String> get _shared => (_sharedKeys[root] ??= {})[caseSensitive] ??= [
    for (final dir in [root.settingsFile, root.roms, root.emulators, root.bios, root.templates, root.appData])
      pathKey(dir),
  ];

  /// The active profile's folder's key, only when a path isn't in a shared place.
  late final String? _profileKey = switch (activeProfileId) {
    null => null,
    final id => pathKey(p.join(root.profiles, id)),
  };

  /// [path], absolute and normalized, if it may be written; throws otherwise.
  String check(String path) {
    final full = p.normalize(p.absolute(path));
    final key = _keyOf(full);
    final shared = _shared;
    if (key == shared.first) return full;
    for (final d in shared.skip(1)) {
      if (key == d || _keyWithin(d, key)) return full;
    }
    if (_profileKey case final d? when key == d || _keyWithin(d, key)) return full;
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
