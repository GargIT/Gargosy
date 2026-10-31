import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/disk_space.dart';
import 'package:gargosy/library/make_room.dart';

import '../helpers/game_fixtures.dart';

Game _g(int id, int size, {String? played}) => Game.fromJson({
  ...gameJson(id, 'G$id', size: size),
  if (played != null) 'rom_user': {'last_played': played},
});

void main() {
  final installed = <String, DateTime>{'4': DateTime(2026, 1, 1)};

  List<RoomCandidate> candidates(List<Game> games, {Set<String> unsynced = const {}}) =>
      roomCandidates(games, except: '9', installedAt: (g) => installed[g.id], unsynced: (g) => unsynced.contains(g.id));

  test('never played first, then played longest ago; the largest first among equals; the one to download left out', () {
    final list = candidates([
      _g(1, 100, played: '2026-10-01T00:00:00Z'),
      _g(2, 300),
      _g(3, 500),
      _g(4, 50),
      _g(5, 100, played: '2025-01-01T00:00:00Z'),
      _g(9, 999),
    ]);
    expect([for (final c in list) c.game.id], ['3', '2', '5', '4', '1']);
    expect(list[3].lastPlayed, DateTime(2026, 1, 1), reason: 'not played: its download time');
  });

  test('ticked until enough is freed, never one whose saves wait to upload', () {
    final list = candidates([_g(1, 500), _g(2, 300), _g(3, 200)], unsynced: {'1'});
    expect([for (final c in pickToFit(list, 400)) c.game.id], ['2', '3']);
    expect(list.first.unsynced, isTrue);
  });

  test('not enough even with every one: nothing ticked', () {
    expect(pickToFit(candidates([_g(1, 100), _g(2, 100)]), 1000), isEmpty);
  });

  test("the shortfall is what's needed plus the headroom, less what's free", () {
    expect(shortfallOf(const NotEnoughSpace(drive: 'D:', needed: 1000, free: 400)), 600 + spaceHeadroom);
  });
}
