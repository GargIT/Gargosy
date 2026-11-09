import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/storage/app_preferences.dart';
import '../l10n/tr.dart';

/// A package manager Gargosy was installed with (#244). It updates Gargosy,
/// so Gargosy's own Update hands over to it.
enum PackageManager {
  /// Scoop: `<scoop>\apps\gargosy\<version or current>\`, the user's folders
  /// kept apart by its `persist` (the GargIT/scoop-gargosy bucket).
  scoop('Scoop', 'scoop update gargosy'),

  /// winget's portable package: `…\WinGet\Packages\GargIT.Gargosy_<source>\Gargosy\`.
  /// The user's folders are inside winget's package folder.
  winget('winget', 'winget upgrade GargIT.Gargosy');

  const PackageManager(this.label, this.updateCommand);

  /// Its name, as people write it.
  final String label;

  /// The command that updates Gargosy.
  final String updateCommand;

  /// What winget's package names start with: Gargosy's id, then the source.
  static const wingetFolder = 'gargit.gargosy_';

  /// App-wide pref: the winget warning was shown once.
  static const wingetWarnedKey = 'packages.wingetWarned';

  /// The package manager whose folder [root] (the Gargosy folder) is in,
  /// or null for a Gargosy unzipped by hand.
  /// Scoop's: `apps\gargosy\<version or current>\` holding Scoop's own
  /// `manifest.json` (a folder unzipped by hand into `apps\gargosy\` isn't).
  static PackageManager? of(String root, {bool Function(String path)? exists}) {
    final parts = p.split(p.normalize(root)).map((s) => s.toLowerCase()).toList();
    if (parts.any((s) => s.startsWith(wingetFolder))) return winget;
    if (_inScoopApp(parts) && (exists ?? _exists)(p.join(root, 'manifest.json'))) return scoop;
    return null;
  }

  static bool _exists(String path) => io.File(path).existsSync();

  static bool _inScoopApp(List<String> parts) {
    final n = parts.length;
    return n >= 3 && parts[n - 2] == 'gargosy' && parts[n - 3] == 'apps';
  }

  /// [exe] (Gargosy.exe as Windows resolved it) through Scoop's `current`
  /// link when it's in one of Scoop's version folders: the folder Gargosy
  /// works from, and what shortcuts point at, outlive an update (Scoop moves
  /// the player's folders on to the next version). Else [exe] itself.
  static String stableExecutable(String exe, {bool Function(String path)? exists, bool Function(String dir)? isDir}) {
    final dir = p.dirname(exe);
    final parts = p.split(p.normalize(dir)).map((s) => s.toLowerCase()).toList();
    if (!_inScoopApp(parts) || parts.last == 'current') return exe;
    final current = p.join(p.dirname(dir), 'current');
    final hasCurrent = (isDir ?? (d) => io.Directory(d).existsSync())(current);
    if (!hasCurrent || !(exists ?? _exists)(p.join(dir, 'manifest.json'))) return exe;
    return p.join(current, p.basename(exe));
  }

  /// "Installed with Scoop: update it with `scoop update gargosy`."
  String get updateHint => tr('Installed with {0}: update it with {1}', [label, updateCommand]);

  /// winget deletes what is in its package folder on a purge: said in
  /// About and once at the first start.
  static String get wingetWarning => tr(
    "winget keeps this Gargosy folder in its own package folder. Uninstalling with --purge, or from Windows' Installed apps, can delete your ROMs, emulators and saves with it. Back up the userdata folder first.",
  );

  /// Whether the winget warning still has to be shown once.
  static bool wingetWarningDue(PackageManager? pm, AppPreferences prefs) =>
      pm == winget && prefs.getBool(wingetWarnedKey) != true;
}
