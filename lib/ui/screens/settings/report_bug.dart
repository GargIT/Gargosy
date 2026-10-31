import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/file_log_sink.dart';
import '../../../core/storage/log_redaction.dart';
import '../../../profiles/app_root.dart';
import '../../../profiles/path_guard.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/about_providers.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// #231: About → Report a bug. GitHub's bug form opens first, with the
/// versions filled in (RomM's when it's known already: never waited for);
/// then the last two logs (this session's and the one before, where a crash
/// would be), redacted again, are copied to one file in its own folder in
/// temp, and that folder opens, so the file can be dragged into the form.
/// Gargosy sends nothing itself.
Future<void> reportBug(BuildContext context, WidgetRef ref, {required String windows}) async {
  final root = ref.read(appRootProvider);
  final open = ref.read(externalOpenerProvider);
  final romm = ref.read(rommServerVersionProvider).value;
  final form = open(bugFormUrl(version: AppConstants.version, windows: windowsName(windows), romm: romm).toString());
  unawaited(
    form.then((opened) {
      if (!opened && context.mounted) showToast(context, tr("The bug form couldn't be opened."));
    }),
  );
  try {
    final copy = await copyLogsForBug(root);
    if (copy != null) {
      open(p.dirname(copy));
    } else if (context.mounted) {
      showToast(context, tr('There is no log to attach yet.'));
    }
  } on Object catch (e) {
    debugPrint('[About] log for a bug report: $e');
    if (context.mounted) showToast(context, tr('The log couldn\'t be copied: {0}', [e]));
  }
}

/// GitHub's bug form with the versions in its fields.
Uri bugFormUrl({required String version, required String windows, String? romm}) =>
    Uri.https('github.com', '/GargIT/Gargosy/issues/new', {
      'template': 'bug_report.yml',
      'version': version,
      'windows': windows,
      if (romm != null && romm.isNotEmpty) 'romm': romm,
    });

/// [os] (Dart's `operatingSystemVersion`) as people know it: Windows 11
/// still calls itself Windows 10 there, and only its build (22000 and up)
/// tells.
String windowsName(String os) {
  final build = int.tryParse(RegExp(r'Build (\d+)').firstMatch(os)?.group(1) ?? '');
  return build != null && build >= 22000 ? os.replaceFirst('Windows 10', 'Windows 11') : os;
}

/// Where the copy goes: its own folder in temp (Empty Temp clears it).
String bugReportDir(AppRoot root) => p.join(root.appData, 'temp', 'bug-report');

/// The last two logs (`FileLogSink`'s order), oldest first, each redacted
/// again line by line, in one file in [bugReportDir]; null when there are
/// none. Read and written in another isolate (a log can be 5 MB).
Future<String?> copyLogsForBug(AppRoot root) async {
  final logs = FileLogSink.logsIn(root.logs);
  if (logs.isEmpty) return null;
  final last = [for (final f in logs.skip(logs.length < 2 ? 0 : logs.length - 2)) f.path];
  final guard = PathGuard(root);
  final out = guard.check(p.join(bugReportDir(root), 'gargosy-log-for-bug.txt'));
  await Isolate.run(() {
    io.Directory(p.dirname(out)).createSync(recursive: true);
    final text = StringBuffer();
    for (final path in last) {
      text.writeln('===== ${p.basename(path)} =====');
      for (final line in io.File(path).readAsLinesSync()) {
        text.writeln(redact(line));
      }
      text.writeln();
    }
    io.File(out).writeAsStringSync('$text');
  });
  return out;
}
