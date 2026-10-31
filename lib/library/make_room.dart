import '../core/romm/romm_models.dart';
import 'disk_space.dart';

/// #227: a game on this PC that could go to make room for a download.
class RoomCandidate {
  const RoomCandidate(this.game, {required this.size, this.lastPlayed, this.played = true, this.unsynced = false});

  final Game game;

  /// What deleting it frees: its size on disk.
  final int size;

  /// When it was played last ([played]), else when it was downloaded.
  final DateTime? lastPlayed;

  /// Whether [lastPlayed] is a play (else the download's time).
  final bool played;

  /// Its saves aren't all on RomM (uploads waiting): never ticked for the
  /// player, and said.
  final bool unsynced;
}

/// [games] on this PC as candidates, the ones not played for longest first
/// (the newest of RomM's last play and this PC's own, else the download's
/// time), the largest first among equals; [except] (the game to download)
/// and [running] (a game being played) left out.
List<RoomCandidate> roomCandidates(
  List<Game> games, {
  required String except,
  String? running,
  required DateTime? Function(Game) installedAt,
  required DateTime? Function(Game) playedHere,
  required int Function(Game) sizeOnDisk,
  required bool Function(Game) unsynced,
}) {
  DateTime? newest(DateTime? a, DateTime? b) => a == null ? b : (b == null || a.isAfter(b) ? a : b);
  final list = <RoomCandidate>[];
  for (final g in games) {
    if (g.id == except || g.id == running) continue;
    final size = sizeOnDisk(g);
    if (size <= 0) continue;
    final played = newest(g.lastPlayed, playedHere(g));
    list.add(
      RoomCandidate(g, size: size, lastPlayed: played ?? installedAt(g), played: played != null, unsynced: unsynced(g)),
    );
  }
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
