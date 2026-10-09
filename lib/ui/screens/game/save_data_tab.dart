import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../providers/library_providers.dart';
import '../../../library/upload_queue.dart';
import '../../theme/tokens.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/format.dart';
import '../../widgets/g_focusable.dart';

/// The saves and states this profile has on RomM for the game. Read-only for
/// now; the play screen (milestone C) restores and plays them.
class SaveDataTab extends ConsumerWidget {
  const SaveDataTab({super.key, required this.game});

  final Game game;

  Widget _row(String title, String subtitle) => GFocusable(
        borderRadius: GRadius.md,
        child: Container(
          margin: const EdgeInsets.only(bottom: GSpace.s2),
          padding: const EdgeInsets.all(GSpace.s3),
          decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.md)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted)),
          ]),
        ),
      );

  static String _when(Object? iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    return d == null ? '' : formatDate(d);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saves = ref.watch(romSavesProvider(game.id));
    final states = ref.watch(romStatesProvider(game.id));
    final waiting = ref.watch(uploadsWaitingProvider(game.id));
    return ListView(padding: const EdgeInsets.only(bottom: GSpace.s14), children: [
      if (waiting.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(GSpace.s4),
          decoration: BoxDecoration(
              color: GColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(GRadius.lg)),
          child: Text(
              'Waiting to upload: your save from ${_when(waiting.first.timestamp.toUtc().toIso8601String())} '
              "isn't on RomM yet. It goes up when RomM can be reached.",
              style: const TextStyle(color: GColors.accent)),
        ),
        const SizedBox(height: GSpace.s5),
      ],
      const Text('Saves', style: TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
      const SizedBox(height: GSpace.s3),
      ...saves.when(
        loading: () => [const LinearProgressIndicator()],
        error: (e, _) => [
          SizedBox(height: 180, child: ErrorRetry(message: describeLoadError(e), onRetry: () => ref.invalidate(romSavesProvider(game.id)))),
        ],
        data: (list) => list.isEmpty
            ? [const Text('No saves on RomM yet.', style: TextStyle(color: GColors.fgMuted))]
            : [
                for (final s in list)
                  _row(
                    s['file_name']?.toString() ?? 'save',
                    [
                      s['emulator']?.toString(),
                      _when(s['updated_at'] ?? s['created_at']),
                      if (s['file_size_bytes'] is int) formatBytes(s['file_size_bytes'] as int),
                    ].whereType<String>().where((x) => x.isNotEmpty).join('  ·  '),
                  ),
              ],
      ),
      const SizedBox(height: GSpace.s6),
      const Text('States', style: TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
      const SizedBox(height: GSpace.s3),
      ...states.when(
        loading: () => [const LinearProgressIndicator()],
        error: (e, _) => [
          SizedBox(height: 180, child: ErrorRetry(message: describeLoadError(e), onRetry: () => ref.invalidate(romStatesProvider(game.id)))),
        ],
        data: (list) => list.isEmpty
            ? [const Text('No states on RomM yet.', style: TextStyle(color: GColors.fgMuted))]
            : [
                for (final s in list)
                  _row(s.fileName, [s.emulator, _when(s.updatedAt)].whereType<String>().where((x) => x.isNotEmpty).join('  ·  ')),
              ],
      ),
    ]);
  }
}
