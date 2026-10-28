import 'dart:async';
import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/platform/platform_info.dart';
import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';
import 'update_paths.dart';
import '../l10n/tr.dart';

/// Starts a process that outlives Gargosy; tests pass a recorder.
typedef DetachedStarter = Future<void> Function(String exe, List<String> args);

Future<void> _startDetached(String exe, List<String> args) =>
    io.Process.start(exe, args, mode: io.ProcessStartMode.detached);

/// What the last update did, from the arguments `GargosyUpdate.exe` started
/// this Gargosy with.
sealed class UpdateOutcome {
  const UpdateOutcome();
}

class UpdatedFrom extends UpdateOutcome {
  const UpdatedFrom(this.oldVersion);
  final String oldVersion;
}

/// The update was rolled back; [detail] is the last line of `update.log`.
class UpdateFailed extends UpdateOutcome {
  const UpdateFailed(this.detail);
  final String? detail;
}

/// Hands an unpacked update to `GargosyUpdate.exe` and cleans up after it
/// (issue #16). Gargosy can't replace its own exe, DLLs and `data\` while it
/// runs: the updater waits for this process to exit, swaps the files listed
/// in `app-files.txt` and starts Gargosy again with `--updated-from=<old>`
/// (or the old one with `--update-failed`).
class UpdateInstaller {
  UpdateInstaller({
    required this.root,
    required this.pid,
    required this.args,
    required this.currentVersion,
    required this.platform,
    DetachedStarter? start,
  }) : _start = start ?? _startDetached,
       paths = UpdatePaths(root),
       _guard = PathGuard(root);

  final AppRoot root;
  final UpdatePaths paths;
  final PathGuard _guard;
  final int pid;

  /// Gargosy's own command line, passed on to the new version.
  final List<String> args;
  final String currentVersion;
  final PlatformInfo platform;
  final DetachedStarter _start;

  static const updatedFromArg = '--updated-from=';
  static const updateFailedArg = '--update-failed';

  /// Whether Update now can be offered: the updater ships beside
  /// Gargosy.exe, and the folder isn't one Windows protects (Program Files,
  /// Windows), where it couldn't replace the files. Elsewhere a folder that
  /// can't be written makes the updater roll back and say so.
  late final bool canInstall = io.File(paths.installedUpdater).existsSync() && !_inProtectedFolder;

  /// Why [canInstall] is false, for the UI.
  late final String? whyNot = _whyNot();

  String? _whyNot() {
    if (!io.File(paths.installedUpdater).existsSync()) {
      return tr('This Gargosy has no {0}: update it by hand from the release page this once.', [
        UpdatePaths.updaterExe,
      ]);
    }
    if (_inProtectedFolder) return tr('Gargosy is in a folder Windows protects, so it can\'t update itself there.');
    return null;
  }

  bool get _inProtectedFolder {
    final env = platform.environment;
    final r = p.normalize(root.root).toLowerCase();
    return [
      env['ProgramFiles'],
      env['ProgramFiles(x86)'],
      env['ProgramW6432'],
      env['SystemRoot'],
      env['windir'],
    ].whereType<String>().where((d) => d.isNotEmpty).any((d) {
      final dir = p.normalize(d).toLowerCase();
      return r == dir || p.isWithin(dir, r);
    });
  }

  /// The updater's command line for [unpacked], version [newVersion].
  List<String> commandLine(String unpacked, String newVersion) => [
    '--pid',
    '$pid',
    '--root',
    root.root,
    '--from',
    unpacked,
    '--version',
    newVersion,
    '--old-version',
    currentVersion,
    '--',
    ...args.where((a) => !a.startsWith(updatedFromArg) && a != updateFailedArg),
  ];

  /// Copies the updater into `userdata\app\update\` and starts that copy
  /// (so the one beside Gargosy.exe can be replaced too). The caller then
  /// quits Gargosy the normal way, so settings are flushed: the
  /// updater waits for this process to end.
  Future<void> start(String unpacked, String newVersion) async {
    if (!canInstall) throw StateError(whyNot ?? tr('Can\'t update'));
    final copy = _guard.check(paths.updaterCopy);
    await io.Directory(p.dirname(copy)).create(recursive: true);
    await io.File(paths.installedUpdater).copy(copy);
    final log = io.File(_guard.check(paths.log));
    if (await log.exists()) await log.delete();
    await _start(copy, commandLine(unpacked, newVersion));
  }

  /// At start: what [args] say about the last update. After a good one, the
  /// old files, the zip, the unpacked folder and the updater's copy go.
  Future<UpdateOutcome?> afterStart(List<String> args) async {
    final from = args.where((a) => a.startsWith(updatedFromArg)).firstOrNull;
    if (from != null) {
      // The old release is removed in the background: the window doesn't
      // wait for thousands of deletes.
      cleaning = _cleanUp();
      unawaited(cleaning);
      return UpdatedFrom(from.substring(updatedFromArg.length));
    }
    if (args.contains(updateFailedArg)) return UpdateFailed(_lastLogLine());
    return null;
  }

  /// The clean-up after an update, running in the background (tests wait for it).
  Future<void> cleaning = Future.value();

  Future<void> _cleanUp() async {
    final dir = io.Directory(paths.dir);
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      if (p.basename(e.path) == p.basename(paths.log)) continue; // kept to read what happened
      try {
        await e.delete(recursive: true);
      } on io.FileSystemException {
        // Locked for a moment (the updater still closing): the next update clears it.
      }
    }
  }

  String? _lastLogLine() {
    try {
      final lines = io.File(paths.log).readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty);
      // The updater writes "yyyy-mm-dd hh:mm:ss  " first: the message alone.
      return lines.isEmpty ? null : lines.last.replaceFirst(RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\s+'), '');
    } on io.FileSystemException {
      return null;
    }
  }
}
