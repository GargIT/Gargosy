import 'package:pub_semver/pub_semver.dart';

/// Gargosy's versions as the updater compares them (issue #16): semver, so
/// `0.2.0-preview.3 < 0.2.0-preview.10 < 0.2.0`. Build metadata (`+1`) is
/// dropped: it never makes one Gargosy newer than another.
class UpdateVersion {
  UpdateVersion._();

  static final _asset = RegExp(r'^Gargosy-(.+)\.zip$');

  /// The version in a release asset's name (`Gargosy-0.2.0-preview.4.zip`),
  /// or null when the name isn't one. The asset names the version, not the
  /// tag: a preview's tag stays `v0.2.0-preview` while its version moves.
  static Version? fromAsset(String name) {
    final m = _asset.firstMatch(name);
    return m == null ? null : parse(m.group(1)!);
  }

  /// [raw] (`0.2.0`, `v0.2.0`, `0.2.0-preview.4+1`) as a version, or null.
  static Version? parse(String raw) {
    final text = raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    if (text.isEmpty) return null;
    try {
      return Version.parse(text);
    } on FormatException {
      return null;
    }
  }

  /// Whether [candidate] should be offered over [installed]: only a newer
  /// version, never a downgrade.
  static bool isNewer(Version candidate, Version installed) => candidate > installed;
}
