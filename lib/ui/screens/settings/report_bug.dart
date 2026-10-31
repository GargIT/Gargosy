import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/log_redaction.dart';
import '../../../profiles/app_root.dart';
import '../../../profiles/path_guard.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/about_providers.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// #231: About → Report a bug. The newest log, redacted once more, is
/// copied to `userdata\app\gargosy-log-for-bug.txt` and its folder opened,
/// so it can be dragged into the form; GitHub's bug form opens with the
/// versions filled in. Gargosy sends nothing itself.
Future<void> reportBug(BuildContext context, WidgetRef ref, {required String windows}) async {
  final root = ref.read(appRootProvider);
  final open = ref.read(externalOpenerProvider);
  final romm = await ref.read(rommServerVersionProvider.future).catchError((Object _) => null);
  final copy = copyNewestLog(root);
  open(bugFormUrl(version: AppConstants.version, windows: windows, romm: romm).toString());
  if (copy != null) {
    open(p.dirname(copy));
  } else if (context.mounted) {
    showToast(context, tr('There is no log to attach yet.'));
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

/// The newest `gargosy-*.log` in `userdata\app\logs\`, redacted line by line
/// (on top of the redaction it was written with), as
/// `userdata\app\gargosy-log-for-bug.txt`; null when there is none.
String? copyNewestLog(AppRoot root) {
  final logs = io.Directory(root.logs);
  if (!logs.existsSync()) return null;
  final files = [
    for (final e in logs.listSync())
      if (e is io.File && p.basename(e.path).startsWith('gargosy-') && e.path.endsWith('.log')) e,
  ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
  if (files.isEmpty) return null;
  final out = PathGuard(root).check(p.join(root.appData, 'gargosy-log-for-bug.txt'));
  final text = files.first.readAsLinesSync().map(redact).join('\n');
  io.File(out).writeAsStringSync('$text\n');
  return out;
}
