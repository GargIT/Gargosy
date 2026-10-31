import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_models.dart';
import '../../library/library_snapshot.dart';
import '../../library/make_room.dart';
import '../../library/upload_queue.dart';
import '../../providers/download_providers.dart';
import '../theme/tokens.dart';
import 'controller_dialogs.dart';
import 'format.dart';
import 'g_focusable.dart';
import 'toast.dart';
import '../../l10n/tr.dart';

/// #227: before [game] is queued, whether it fits. When it doesn't, Make
/// room: this profile's games on this PC not played for longest, largest
/// first, the ones that free enough ticked (never one whose saves wait to
/// upload), each with its size and last play; the player ticks and confirms,
/// they're deleted, and true says the download can start. False: not
/// started (cancelled, or not enough to free).
Future<bool> makeRoomFor(BuildContext context, WidgetRef ref, Game game) async {
  final downloads = ref.read(downloadsProvider.notifier);
  final space = downloads.spaceFor(game);
  if (space == null) return true;
  final queue = ref.read(uploadQueueProvider).valueOrNull;
  final files = ref.read(romFilesProvider);
  final candidates = roomCandidates(
    ref.read(gamesOnThisPcProvider),
    except: game.id,
    installedAt: files.installedAt,
    unsynced: (g) => queue?.waitingFor(g.id).isNotEmpty ?? false,
  );
  final needed = shortfallOf(space);
  final picked = pickToFit(candidates, needed);
  if (picked.isEmpty) {
    showToast(context, '$space');
    return false;
  }
  final chosen = await showDialog<List<RoomCandidate>>(
    context: context,
    builder: (_) => _MakeRoom(space: '$space', needed: needed, candidates: candidates, picked: picked),
  );
  if (chosen == null || chosen.isEmpty) return false;
  for (final c in chosen) {
    await downloads.delete(c.game);
  }
  return true;
}

class _MakeRoom extends StatefulWidget {
  const _MakeRoom({required this.space, required this.needed, required this.candidates, required this.picked});

  final String space;
  final int needed;
  final List<RoomCandidate> candidates;
  final List<RoomCandidate> picked;

  @override
  State<_MakeRoom> createState() => _MakeRoomState();
}

class _MakeRoomState extends State<_MakeRoom> {
  late final _ticked = {for (final c in widget.picked) c.game.id};

  int get _freed => widget.candidates.where((c) => _ticked.contains(c.game.id)).fold(0, (n, c) => n + c.size);

  String _played(RoomCandidate c) {
    final at = c.lastPlayed;
    final when = at == null ? tr('never played') : tr('played {0}', [formatDate(at)]);
    return c.unsynced ? '$when · ${tr('saves not on RomM yet')}' : when;
  }

  @override
  Widget build(BuildContext context) {
    final enough = _freed >= widget.needed;
    return Center(
      child: Material(
        color: GColors.panel,
        borderRadius: BorderRadius.circular(GRadius.lg),
        child: SizedBox(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.all(GSpace.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Make room?'),
                  style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: GSpace.s2),
                Text(
                  tr('{0} Delete games from this PC to make room: they stay on RomM.', [widget.space]),
                  style: const TextStyle(color: GColors.fgSecondary),
                ),
                const SizedBox(height: GSpace.s3),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final c in widget.candidates)
                          GFocusable(
                            key: ValueKey('room-${c.game.id}'),
                            autofocus: c == widget.candidates.first,
                            borderRadius: GRadius.chip,
                            onActivate: () => setState(
                              () => _ticked.contains(c.game.id) ? _ticked.remove(c.game.id) : _ticked.add(c.game.id),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: GSpace.s2, vertical: GSpace.s2),
                              child: Row(
                                children: [
                                  Icon(
                                    _ticked.contains(c.game.id) ? Icons.check_box : Icons.check_box_outline_blank,
                                    size: 20,
                                  ),
                                  const SizedBox(width: GSpace.s3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.game.displayName, overflow: TextOverflow.ellipsis),
                                        Text(
                                          _played(c),
                                          style: TextStyle(
                                            fontSize: GFont.sm,
                                            color: c.unsynced ? GColors.accent : GColors.fgSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(formatBytes(c.size), style: const TextStyle(color: GColors.fgSecondary)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: GSpace.s3),
                Text(
                  tr('Frees {0} of {1} needed.', [formatBytes(_freed), formatBytes(widget.needed)]),
                  style: TextStyle(color: enough ? GColors.fgSecondary : GColors.accent),
                ),
                const SizedBox(height: GSpace.s4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    dialogButton(tr('Cancel'), () => Navigator.of(context).pop()),
                    const SizedBox(width: GSpace.s3),
                    dialogButton(
                      tr('Delete and download'),
                      enough
                          ? () =>
                                Navigator.of(context)
                                    .pop(widget.candidates.where((c) => _ticked.contains(c.game.id)).toList())
                          : null,
                      primary: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Download on a game's page and Home's header: [game] queued, after Make
/// room when it doesn't fit.
Future<void> downloadOrMakeRoom(BuildContext context, WidgetRef ref, Game game) async {
  if (!await makeRoomFor(context, ref, game)) return;
  await ref.read(downloadsProvider.notifier).start(game);
}
