import 'dart:async';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../play/play_controller.dart';
import '../../profiles/path_guard.dart';
import '../../profiles/profile_providers.dart';
import '../../providers/about_providers.dart';
import '../../providers/update_providers.dart';
import '../../update/update_checker.dart';
import '../screens/doc_reader_screen.dart';
import '../theme/tokens.dart';
import 'controller_dialogs.dart';
import 'hint_bar.dart';
import 'sync_wait.dart';
import 'toast.dart';

/// Update now (issue #16): refused while a game runs, waits for the saves,
/// asks once, downloads with progress (B cancels), then hands over to
/// `GargosyUpdate.exe` and quits. Without the updater, the release page opens.
Future<void> runUpdate(BuildContext context, WidgetRef ref, ReleaseInfo release) async {
  final installer = ref.read(updateInstallerProvider);
  if (!installer.canInstall) {
    ref.read(externalOpenerProvider)(release.htmlUrl);
    return;
  }
  if (ref.read(playControllerProvider).runningGameId != null) {
    showToast(context, "Close the game first: Gargosy can't update while a game runs.");
    return;
  }
  if (ref.read(activeProfileProvider) != null && !await waitForSyncIdle(context, ref)) return;
  if (!context.mounted) return;
  final ok = await showConfirm(
    context,
    title: 'Update to ${release.version}?',
    body: 'Gargosy will close, update and start again. Your games, emulators and saves are not touched.',
    yes: 'Update',
  );
  if (!ok || !context.mounted) return;

  final unpacked = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DownloadDialog(release: release),
  );
  if (unpacked == null || !context.mounted) return;
  // A game or a sync may have started while it downloaded (RomM came back
  // and the upload queue runs): Gargosy quits only once both are done.
  if (ref.read(playControllerProvider).runningGameId != null) {
    showToast(context, "Close the game first: Gargosy can't update while a game runs.");
    return;
  }
  if (ref.read(activeProfileProvider) != null && !await waitForSyncIdle(context, ref)) return;
  if (!context.mounted) return;
  unawaited(showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _Restarting()));
  try {
    await installer.start(unpacked, release.version.toString());
  } on Object catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      showToast(context, "The updater couldn't start: $e");
    }
    return;
  }
  await ref.read(appQuitProvider)();
}

/// The release notes in the reader, written to `userdata\app\update\`.
Future<void> openReleaseNotes(BuildContext context, WidgetRef ref, ReleaseInfo release) async {
  final paths = ref.read(updateDownloaderProvider).paths;
  final guard = PathGuard(ref.read(appRootProvider));
  final file = io.File(guard.join(paths.dir, 'release-notes-${release.version}.md'));
  await file.parent.create(recursive: true);
  final notes = release.notes.trim().isEmpty ? 'No notes for this release.' : release.notes;
  await file.writeAsString('# Gargosy ${release.version}\n\n$notes\n\n[On GitHub](${release.htmlUrl})\n');
  if (context.mounted) await openDoc(context, file.path);
}

class _DownloadDialog extends ConsumerStatefulWidget {
  const _DownloadDialog({required this.release});
  final ReleaseInfo release;

  @override
  ConsumerState<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends ConsumerState<_DownloadDialog> {
  final _cancel = CancelToken();
  int _received = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final unpacked = await ref
          .read(updateDownloaderProvider)
          .download(
            widget.release,
            cancel: _cancel,
            onProgress: (r, t) {
              if (mounted) {
                setState(() {
                  _received = r;
                  _total = t;
                });
              }
            },
          );
      if (mounted) Navigator.of(context).pop(unpacked);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return; // B already closed it
      if (mounted) setState(() => _error = e.message ?? 'The download failed.');
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    if (!_cancel.isCancelled) _cancel.cancel('closed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
    return PopScope(
      canPop: true,
      child: Center(
        child: Material(
          color: GColors.panel,
          borderRadius: BorderRadius.circular(GRadius.lg),
          child: SizedBox(
            width: 460,
            child: Padding(
              padding: const EdgeInsets.all(GSpace.s5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _error == null ? 'Downloading Gargosy ${widget.release.version}…' : "The update can't be used",
                    style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: GSpace.s4),
                  if (_error == null) ...[
                    LinearProgressIndicator(value: fraction),
                    const SizedBox(height: GSpace.s2),
                    Text(
                      fraction == null ? '' : '${(fraction * 100).round()} %',
                      style: const TextStyle(color: GColors.fgMuted),
                    ),
                  ] else
                    Text('$_error Nothing was changed.', style: const TextStyle(color: GColors.fgSecondary)),
                  const SizedBox(height: GSpace.s4),
                  HintBar(hints: [Hint(GameAction.back, _error == null ? 'Cancel' : 'Close')]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Restarting extends StatelessWidget {
  const _Restarting();

  @override
  Widget build(BuildContext context) => const PopScope(
    canPop: false,
    child: Center(
      child: Material(
        color: GColors.panel,
        borderRadius: BorderRadius.all(Radius.circular(GRadius.lg)),
        child: Padding(
          padding: EdgeInsets.all(GSpace.s6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              SizedBox(width: GSpace.s4),
              Text('Restarting…', style: TextStyle(fontSize: GFont.lg)),
            ],
          ),
        ),
      ),
    ),
  );
}
