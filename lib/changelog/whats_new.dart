import 'package:pub_semver/pub_semver.dart';

import '../core/storage/app_preferences.dart';
import '../update/update_version.dart';

/// What's new after an update (issue #3): the version that last ran, kept
/// app-wide in `userdata\settings.json`, so an update by hand counts too.
const lastRunVersionKey = 'last_run_version';

/// When this Gargosy started: set by main() ([markAppStart]); a profile
/// made before it means Gargosy ran before.
DateTime appStartedAt = DateTime.now();

void markAppStart() => appStartedAt = DateTime.now();

final _heading = RegExp(r'^## \[([^\]]+)\]');

/// The link list at the end of a Keep a Changelog file: `[Unreleased]: …`,
/// `[0.2.0]: …`. A reference link inside a section (`[#3]: …`) isn't one.
final _versionLink = RegExp(r'^\[(Unreleased|v?\d[^\]]*)\]:\s', caseSensitive: false);

/// The `## [x.y.z] - date` sections of [markdown] (CHANGELOG.md, Keep a
/// Changelog) with [last] < x.y.z <= [current], in file order; null when
/// there are none. The intro, `[Unreleased]` and the link list at the end
/// are left out.
String? changelogSince(String markdown, Version last, Version current) {
  final out = <String>[];
  var keep = false;
  for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final m = _heading.firstMatch(line);
    if (m != null) {
      final v = UpdateVersion.parse(m.group(1)!);
      keep = v != null && v > last && v <= current;
    } else if (line.startsWith('# ') || _versionLink.hasMatch(line)) {
      keep = false;
      continue;
    }
    if (keep) out.add(line);
  }
  final text = out.join('\n').trim();
  return text.isEmpty ? null : text;
}

/// The release just before [current] in [markdown]'s headings, or null.
Version? _releaseBefore(String markdown, Version current) {
  Version? best;
  for (final m in RegExp(_heading.pattern, multiLine: true).allMatches(markdown)) {
    final v = UpdateVersion.parse(m.group(1)!);
    if (v != null && v < current && (best == null || v > best)) best = v;
  }
  return best;
}

/// What's new for this start, or null. [title] is the running version as
/// it's shown. Nothing is recorded here: the caller calls [recordRun] once
/// the page is up (or when [text] is null), so a start that never shows it
/// shows it next time.
///
/// Shown on the first start of a newer version than the one that last ran.
/// With none recorded, [existingInstall] (a profile from an earlier start)
/// means Gargosy was in use before this feature came: this release's own
/// section is shown. A fresh install, the same version or a downgrade shows
/// nothing; so does a changelog that can't be read. Never throws.
Future<({String? text, String title, Future<void> Function() recordRun})> whatsNewToShow(
  AppPreferences prefs,
  String current, {
  required String? Function() readChangelog,
  bool existingInstall = false,
}) async {
  final now = UpdateVersion.parse(current);
  final before = UpdateVersion.parse(prefs.getString(lastRunVersionKey) ?? '');
  Future<void> record() async {
    if (now != null && (before == null || now > before)) await prefs.setString(lastRunVersionKey, now.toString());
  }

  final title = now?.toString() ?? current;
  if (now == null || (before == null && !existingInstall) || (before != null && now <= before)) {
    return (text: null, title: title, recordRun: record);
  }
  String? markdown;
  try {
    markdown = readChangelog();
  } catch (_) {
    markdown = null;
  }
  if (markdown == null) return (text: null, title: title, recordRun: record);
  final last = before ?? _releaseBefore(markdown, now) ?? Version.none;
  return (text: changelogSince(markdown, last, now), title: title, recordRun: record);
}
