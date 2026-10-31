import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_models.dart';
import '../../library/library_snapshot.dart';
import '../../library/make_room.dart';
import '../../library/upload_queue.dart';
import '../../library/storage_usage.dart';
import '../../play/play_controller.dart';
import '../../play/play_time.dart';
import '../../providers/download_providers.dart';
import '../theme/tokens.dart';
import 'controller_dialogs.dart';
import 'format.dart';
import 'g_focusable.dart';
import 'toast.dart';
import '../../l10n/tr.dart';

/// One Make room at a time: a second press while one deletes waits out.
bool _busy = false;

/// #227: before [game] is queued, whether it fits. When it doesn't, Make
/// room: this profile's games on this PC not played for longest, largest
/// first, the ones that free enough ticked (never one whose saves wait to
/// upload), each with its size and last play; the player ticks and confirms,
/// they're deleted, and true says the download can start. False: not
/// started (cancelled, a game running, not enough to free, a delete failed).
Future<bool> makeRoomFor(BuildContext context, WidgetRef ref, Game game) async {
  final downloads = ref.read(downloadsProvider.notifier);
  final space = downloads.spaceFor(game);
  if (space == null) return true;
  if (_busy) return false;
  // A running game's ROM, or anything while one runs, is never deleted.
  if (ref.read(playControllerProvider).runningGameId != null) {
    showToast(context, tr('{0} Close the game first: nothing is deleted while one runs.', [space]));
    return false;
  }
  _busy = true;
  try {
    final files = ref.read(romFilesProvider);
    final games = ref.read(gamesOnThisPcProvider);
    final log = ref.read(playTimeLogProvider)?.all ?? const [];
    final lastHere = <String, DateTime>{};
    for (final s in log) {
      final had = lastHere[s.gameId];
      if (had == null || s.end.isAfter(had)) lastHere[s.gameId] = s.end;
    }
    // Waited for: while it loads, nothing would say which saves wait.
    final queue = await ref.read(uploadQueueProvider.future).catchError((Object _) => null);
    if (!context.mounted) return false;
    final candidates = roomCandidates(
      games,
      except: game.id,
      installedAt: files.installedAt,
      playedHere: (g) => lastHere[g.id],
      sizeOnDisk: (g) => sizeOf(files.pathFor(g)),
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
      try {
        await downloads.delete(c.game);
      } on Object catch (e) {
        debugPrint('[Downloads] Make room: ${c.game.displayName} not deleted: $e');
        if (context.mounted) {
          showToast(context, tr('{0} couldn\'t be deleted, so nothing is downloaded: {1}', [c.game.displayName, e]));
        }
        return false;
      }
    }
    return true;
  } finally {
    _busy = false;
  }
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
    final when = at == null
        ? tr('never played')
        : (c.played ? tr('played {0}', [formatDate(at)]) : tr('downloaded {0}, not played', [formatDate(at)]));
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
                  tr(
                    '{0} Delete games from this PC to make room: they stay on RomM. Another profile that has one of them here loses it too.',
                    [widget.space],
                  ),
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
                      // Not enough ticked: greyed, and A says why.
                      () => enough
                          ? Navigator.of(context)
                                .pop(widget.candidates.where((c) => _ticked.contains(c.game.id)).toList())
                          : showToast(context, tr('Tick more: they don\'t free enough yet.')),
                      greyed: !enough,
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
  // Read before any wait: the page may be gone by the end.
  final downloads = ref.read(downloadsProvider.notifier);
  if (!await makeRoomFor(context, ref, game)) return;
  await downloads.start(game);
}
