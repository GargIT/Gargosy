import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/input/gamepad_service.dart';
import '../../../core/romm/romm_admin.dart';
import '../../../core/romm/romm_models.dart';
import '../../../l10n/tr.dart';
import '../../../library/library_scan.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/format.dart';
import '../../widgets/hint_bar.dart';
import '../../widgets/toast.dart';

/// Picks the files to upload; the seam tests replace.
final uploadFilePickerProvider = Provider<Future<List<String>> Function(String title)>(
  (ref) =>
      (title) async => [for (final f in await FilePicker.pickFiles(dialogTitle: title)) ?f.path],
);

/// A platform page's Upload a game (#245, a RomM admin's): files from this
/// PC go to [platform]'s folder on RomM one after another, with progress
/// (B cancels the one going), then RomM scans the platform to add them.
Future<void> uploadGamesTo(BuildContext context, WidgetRef ref, Platform platform) async {
  final romm = ref.read(rommServiceProvider);
  if (romm == null) return;
  final files = await ref.read(uploadFilePickerProvider)(tr('Games to upload to {0}', [platform.nameForDisplay]));
  if (files.isEmpty || !context.mounted) return;
  final cancel = CancelToken();
  final progress = ValueNotifier<(String, int, int)>((p.basename(files.first), 0, 0));
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => _UploadDialog(progress: progress, onCancel: cancel.cancel, count: files.length),
  );
  var sent = 0;
  String? failed;
  try {
    for (final path in files) {
      final name = p.basename(path);
      progress.value = (name, 0, 0);
      await romm.uploadGame(
        platform.id,
        path,
        cancel: cancel,
        onProgress: (done, total) => progress.value = (name, done, total),
      );
      sent++;
    }
  } on DioException catch (e) {
    failed = CancelToken.isCancel(e) ? null : '${e.message ?? e.type}';
  } on Object catch (e) {
    failed = '$e';
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await dialog;
    progress.dispose();
  }
  if (!context.mounted) return;
  if (failed != null) {
    showToast(context, tr('Couldn\'t upload: {0}', [failed]), error: true);
  } else if (sent < files.length) {
    showToast(context, tr('Upload cancelled.'));
  }
  if (sent == 0) return;
  // RomM adds a file to the library when it scans its platform.
  final why = await ref.read(libraryScanProvider.notifier).start(ScanKind.quick, platformIds: [platform.id]);
  if (!context.mounted) return;
  showToast(
    context,
    why == null
        ? tr('Uploaded {0} to {1}. RomM is adding it to the library.', [
            sent == 1 ? p.basename(files.first) : tr('{0} games', [sent]),
            platform.nameForDisplay,
          ])
        : tr('Uploaded {0}, but RomM didn\'t scan: {1}', [sent, why]),
    queued: true,
  );
}

class _UploadDialog extends StatelessWidget {
  const _UploadDialog({required this.progress, required this.onCancel, required this.count});

  final ValueNotifier<(String, int, int)> progress;
  final VoidCallback onCancel;
  final int count;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onCancel();
    },
    child: AlertDialog(
      backgroundColor: GColors.panel,
      title: Text(count == 1 ? tr('Uploading to RomM') : tr('Uploading {0} games to RomM', [count])),
      content: SizedBox(
        width: 420,
        child: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, v, _) {
            final (name, done, total) = v;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: GSpace.s3),
                LinearProgressIndicator(value: total > 0 ? done / total : null),
                const SizedBox(height: GSpace.s2),
                Text(
                  total > 0 ? '${formatBytes(done)} / ${formatBytes(total)}' : tr('Starting…'),
                  style: const TextStyle(color: GColors.fgSecondary),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        HintBar(hints: [Hint(GameAction.back, tr('Cancel'))]),
        dialogButton(tr('Cancel'), onCancel),
      ],
    ),
  );
}
