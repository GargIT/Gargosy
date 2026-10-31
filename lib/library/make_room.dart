import '../core/romm/romm_models.dart';
import 'disk_space.dart';

/// #227: a game on this PC that could go to make room for a download.
class RoomCandidate {
  const RoomCandidate(this.game, {required this.size, this.lastPlayed, this.unsynced = false});

  final Game game;

  /// What deleting it frees, by RomM's size.
  final int size;

  /// When it was played last (RomM's, else its download); null: never.
  final DateTime? lastPlayed;

  /// Its saves aren't all on RomM (uploads waiting): never ticked for the
  /// player, and said.
  final bool unsynced;
}

/// [games] on this PC as candidates, the ones not played for longest first,
/// the largest first among equals; [except] (the game to download) left out.
List<RoomCandidate> roomCandidates(
  List<Game> games, {
  required String except,
  required DateTime? Function(Game) installedAt,
  required bool Function(Game) unsynced,
}) {
  final list = [
    for (final g in games)
      if (g.id != except && g.fileSize > 0)
        RoomCandidate(g, size: g.fileSize, lastPlayed: g.lastPlayed ?? installedAt(g), unsynced: unsynced(g)),
  ];
  int byTime(DateTime? a, DateTime? b) => a == null ? (b == null ? 0 : -1) : (b == null ? 1 : a.compareTo(b));
  list.sort((a, b) {
    final t = byTime(a.lastPlayed, b.lastPlayed);
    return t != 0 ? t : b.size.compareTo(a.size);
  });
  return list;
}

/// The candidates ticked at first: in [candidates]' order, skipping
/// unsynced ones, until [needed] bytes are freed. Empty when even all of them
/// wouldn't free enough.
List<RoomCandidate> pickToFit(List<RoomCandidate> candidates, int needed) {
  final picked = <RoomCandidate>[];
  var freed = 0;
  for (final c in candidates) {
    if (freed >= needed) break;
    if (c.unsynced) continue;
    picked.add(c);
    freed += c.size;
  }
  return freed >= needed ? picked : const [];
}

/// How many more bytes [space] needs, the headroom with it.
int shortfallOf(NotEnoughSpace space) => space.needed + spaceHeadroom - space.free;
