// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:package_info_plus/package_info_plus.dart';

class AppConstants {
  /// App version, read from pubspec.yaml at startup via package_info_plus.
  /// Update only in pubspec.yaml — this field is populated automatically.
  /// The updater compares it and RomM and RetroAchievements receive it, so
  /// it never carries build metadata; [displayVersion] is what the player sees.
  static String version = '0.0.0'; // Overwritten in main() from pubspec.yaml

  /// The part after `+` in the exe's version (`0.11.0+11` → `11`,
  /// `0.11.0+handtest.43aa4b1` → `handtest.43aa4b1`).
  static String buildNumber = '';

  /// [version] as the player sees it (About, the user menu, the log, a bug
  /// report): with [buildNumber] when it is more than a number, so a
  /// handtest build reads `0.11.0+handtest.43aa4b1` and a release `0.11.0`.
  static String get displayVersion => displayVersionOf(version, buildNumber);

  /// A purely numeric build number (a release's pubspec `+11`) is left out;
  /// any other build metadata is kept after a `+`.
  static String displayVersionOf(String version, String buildNumber) {
    final build = buildNumber.trim();
    if (build.isEmpty || RegExp(r'^\d+$').hasMatch(build)) return version;
    return '$version+$build';
  }

  /// [raw] without a leading `v`: the release workflow passes the tag
  /// (`v0.6.1`) as the Linux/macOS build name, and the UI adds its own `v`.
  static String normalizeVersion(String raw) => raw.trim().replaceFirst(RegExp(r'^[vV]'), '');

  /// Call once in main() before runApp() to populate [version] and [buildNumber].
  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    version = normalizeVersion(info.version);
    buildNumber = info.buildNumber;
  }
}
