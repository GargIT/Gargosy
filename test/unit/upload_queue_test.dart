import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/library/upload_queue.dart';

import '../helpers/game_fixtures.dart';

BackupEntry _entry(int minute, {bool synced = false}) => BackupEntry(
  timestamp: DateTime(2026, 10, 9, 20, minute),
  md5Hash: 'h$minute',
  localZipPath: 'z$minute.zip',
  isSynced: synced,
  emulatorId: 'pcsx2',
);

void main() {
  late List<({String romId, BackupEntry entry})> waiting;
  late List<String> pushed;
  late Set<String> offlineIds;
  late Set<String> failing;
  late bool offline;
  late UploadQueue queue;

  setUp(() {
    waiting = [];
    pushed = [];
    offlineIds = {};
    failing = {};
    offline = false;
    queue = UploadQueue(
      isOffline: () => offline,
      pending: () => [...waiting],
      markSynced: (id, e) async => waiting.removeWhere((w) => w.romId == id && w.entry == e),
      gameById: (id) async => offlineIds.contains(id) ? null : game(int.parse(id), 'Game $id'),
      romPathFor: (g) async => 'roms/${g.id}',
      push: (Game g, String romPath, BackupEntry newest) async {
        pushed.add('${g.id}:${newest.md5Hash}');
        return !failing.contains(g.id);
      },
    );
  });

  test("one upload per game: the newest session's, and the game's older ones leave the queue with it", () async {
    waiting = [(romId: '1', entry: _entry(1)), (romId: '1', entry: _entry(5)), (romId: '2', entry: _entry(3))];
    expect(await queue.run(), 2);
    expect(pushed, ['2:h3', '1:h5']);
    expect(waiting, isEmpty);
  });

  test("a failed upload stays queued, and doesn't hold up the games behind it", () async {
    waiting = [(romId: '1', entry: _entry(1)), (romId: '2', entry: _entry(3))];
    failing = {'1'};
    expect(await queue.run(), 1);
    expect(pushed, ['1:h1', '2:h3']);
    expect(queue.waitingFor('1'), hasLength(1));
    expect(queue.waitingFor('2'), isEmpty);
  });

  test('RomM unreachable: the run stops, nothing is pushed, everything waits', () async {
    waiting = [(romId: '1', entry: _entry(1)), (romId: '2', entry: _entry(3))];
    offlineIds = {'1', '2'};
    offline = true;
    expect(await queue.run(), 0);
    expect(pushed, isEmpty);
    expect(queue.waitingFor('1'), hasLength(1));
  });

  test("a game RomM can't find (RomM reachable) is skipped; the next goes up", () async {
    waiting = [(romId: '1', entry: _entry(1)), (romId: '2', entry: _entry(3))];
    offlineIds = {'1'};
    expect(await queue.run(), 1);
    expect(pushed, ['2:h3']);
  });

  test("a session that uploaded settles that game's older waiting saves", () async {
    waiting = [(romId: '1', entry: _entry(1)), (romId: '1', entry: _entry(2)), (romId: '2', entry: _entry(3))];
    await queue.settle('1');
    expect(queue.waitingFor('1'), isEmpty);
    expect(queue.waitingFor('2'), hasLength(1));
  });

  test('says while it runs', () async {
    waiting = [(romId: '1', entry: _entry(1))];
    final seen = <bool>[];
    queue.running.addListener(() => seen.add(queue.running.value));
    await queue.run();
    expect(seen, [true, false]);
  });

  test('a second run while one is running does nothing', () async {
    waiting = [(romId: '1', entry: _entry(1))];
    final a = queue.run();
    final b = queue.run();
    expect(await b, 0);
    expect(await a, 1);
    expect(pushed, ['1:h1']);
  });
}
