import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../library/upload_queue.dart';
import '../../providers/engine_providers.dart';
import '../theme/tokens.dart';
import 'hint_bar.dart';
import '../../l10n/tr.dart';

/// What the profile's saves are busy with right now (the save lock, or the
/// upload queue between its games), or null.
String? syncBusyWith(ValueListenable<String?>? activity, UploadQueue? queue) =>
    activity?.value ?? (queue?.running.value == true ? tr('Uploading saves that were waiting') : null);

/// Before the profile changes or goes: waits until its saves are done,
/// saying what it waits for. True when nothing runs any more; false when
/// the player stays (B).
Future<bool> waitForSyncIdle(BuildContext context, WidgetRef ref) async {
  final activity = ref.read(syncActivityProvider);
  final queue = ref.read(uploadQueueProvider).value;
  if (syncBusyWith(activity, queue) == null) return true;
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _SyncWait(activity: activity, queue: queue),
  );
  return done == true;
}

class _SyncWait extends StatefulWidget {
  const _SyncWait({required this.activity, required this.queue});
  final ValueListenable<String?>? activity;
  final UploadQueue? queue;

  @override
  State<_SyncWait> createState() => _SyncWaitState();
}

class _SyncWaitState extends State<_SyncWait> {
  late final Listenable _changes = Listenable.merge([?widget.activity, ?widget.queue?.running]);

  @override
  void initState() {
    super.initState();
    _changes.addListener(_changed);
  }

  @override
  void dispose() {
    _changes.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (syncBusyWith(widget.activity, widget.queue) == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: GColors.panel,
      borderRadius: BorderRadius.circular(GRadius.lg),
      child: Padding(
        padding: const EdgeInsets.all(GSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 40, color: GColors.primary),
            const SizedBox(height: GSpace.s4),
            Text(
              tr('Waiting for: {0}', [syncBusyWith(widget.activity, widget.queue) ?? 'the sync']),
              style: const TextStyle(fontSize: GFont.lg),
            ),
            const SizedBox(height: GSpace.s2),
            Text(tr('It goes on by itself when it is done.'), style: const TextStyle(color: GColors.fgMuted)),
            const SizedBox(height: GSpace.s4),
            HintBar(hints: [Hint(GameAction.back, tr('Stay on this profile'))]),
          ],
        ),
      ),
    ),
  );
}
