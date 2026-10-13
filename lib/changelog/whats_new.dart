import 'package:pub_semver/pub_semver.dart';

import '../core/storage/app_preferences.dart';
import '../update/update_version.dart';

/// What's new after an update (issue #3): the version that last ran, kept
/// app-wide in `userdata\settings.json`, so an update by hand counts too.
const lastRunVersionKey = 'last_run_version';

/// The `## [x.y.z] - date` sections of [markdown] (CHANGELOG.md, Keep a
/// Changelog) with [last] < x.y.z <= [current], in file order; null when
/// there are none. The intro, `[Unreleased]` and the link list at the end
/// are left out.
String? changelogSince(String markdown, Version last, Version current) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final heading = RegExp(r'^## \[([^\]]+)\]');
  final out = <String>[];
  var keep = false;
  for (final line in lines) {
    final m = heading.firstMatch(line);
    if (m != null) {
      final v = UpdateVersion.parse(m.group(1)!);
      keep = v != null && v > last && v <= current;
    } else if (line.startsWith('# ') || RegExp(r'^\[[^\]]+\]:\s').hasMatch(line)) {
      // The title, or the link list at the end: never part of a section.
      keep = false;
      continue;
    }
    if (keep) out.add(line);
  }
  final text = out.join('\n').trim();
  return text.isEmpty ? null : text;
}

/// Records [current] as the version that last ran, and returns what's new
/// since the one before, to show once: null on a first start (none
/// recorded), the same version, a downgrade, or a changelog that can't be
/// read ([readChangelog] returns null). Never throws.
Future<String?> whatsNewToShow(AppPreferences prefs, String current,
    {required String? Function() readChangelog}) async {
  final now = UpdateVersion.parse(current);
  final before = UpdateVersion.parse(prefs.getString(lastRunVersionKey) ?? '');
  if (now == null) return null;
  if (before == null || now > before) await prefs.setString(lastRunVersionKey, now.toString());
  if (before == null || now <= before) return null;
  final String? markdown;
  try {
    markdown = readChangelog();
  } catch (_) {
    return null;
  }
  return markdown == null ? null : changelogSince(markdown, before, now);
}
