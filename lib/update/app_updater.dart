import 'package:pub_semver/pub_semver.dart';

import '../core/platform/platform_info.dart';
import '../profiles/app_root.dart';
import 'update_installer.dart';

/// Installs a downloaded update and tidies up after it (#203). Gargosy
/// can't replace its own files while it runs, so the OS's updater does it
/// after Gargosy exits and starts it again with what happened.
abstract class AppUpdater {
  /// Whether Update now can be offered here.
  bool get canInstall;

  /// Why [canInstall] is false, for the UI.
  String? get whyNot;

  /// The version a release asset named [name] holds for this OS, or null
  /// when it isn't this OS's (`Gargosy-<version>.zip` on Windows).
  Version? versionOfAsset(String name);

  /// Hands the update unpacked in [unpacked] (version [newVersion]) to the
  /// updater. The caller then quits Gargosy the normal way.
  Future<void> start(String unpacked, String newVersion);

  /// At start: what [args] say about the last update, and the clean-up
  /// after a good one.
  Future<UpdateOutcome?> afterStart(List<String> args);

  /// The clean-up [afterStart] began, running in the background.
  Future<void> get cleaning;
}

/// The [AppUpdater] of [platform]'s OS for the Gargosy in [root].
AppUpdater appUpdaterFor(
  PlatformInfo platform, {
  required AppRoot root,
  required int pid,
  required List<String> args,
  required String currentVersion,
}) {
  if (platform.isWindows) {
    return UpdateInstaller(root: root, pid: pid, args: args, currentVersion: currentVersion, platform: platform);
  }
  throw UnsupportedError('No updater on ${platform.os} yet');
}
