import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/disk_space.dart';
import 'package:gargosy/library/download_schedule.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/download_providers.dart';

import '../helpers/fake_download_service.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/fake_disk.dart';

void main() {
  test('switching profile cancels the old profile\'s downloads and forgets their progress', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final fake = FakeDownloadService(RomFiles(root), PathGuard(root))..hold = Completer<void>();
    final c = ProviderContainer(
      overrides: [
        appRootProvider.overrideWithValue(root),
        appPreferencesProvider.overrideWithValue(MemoryPrefs()),
        downloadServiceProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(c.dispose);
    final store = c.read(profileStoreProvider);
    final anna = await store.create(
      name: 'Anna',
      colorIndex: 0,
      serverUrl: 'https://a',
      rommUserId: 7,
      rommUsername: 'anna',
    );
    final bob = await store.create(
      name: 'Bob',
      colorIndex: 0,
      serverUrl: 'https://b',
      rommUserId: 8,
      rommUsername: 'bob',
    );
    await c.read(activeProfileProvider.notifier).activate(anna, const ProfileLogin(token: 'a', kind: 'device'));

    final sub = c.listen(downloadsProvider, (_, _) {});
    addTearDown(sub.close);
    final running = c.read(downloadsProvider.notifier).start(game(7564, 'Burnout 3'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(downloadsProvider).keys, ['7564']);

    await c.read(activeProfileProvider.notifier).activate(bob, const ProfileLogin(token: 'b', kind: 'device'));
    await running;
    expect(c.read(downloadsProvider), isEmpty);
    expect(RomFiles(root).isDownloaded(game(7564, 'Burnout 3')), isFalse);
  });

  group('the queue (#143)', () {
    late FakeDownloadService fake;
    late ProviderContainer c;
    late DownloadsNotifier downloads;
    int? free;
    final a = game(1, 'A'), b = game(2, 'B'), d = game(3, 'D');

    setUp(() async {
      free = null;
      final root = await tempAppRoot();
      addTearDown(() => io.Directory(root.root).delete(recursive: true));
      fake = FakeDownloadService(RomFiles(root), PathGuard(root));
      for (final g in [a, b, d]) {
        fake.holds[g.id] = Completer<void>();
      }
      c = ProviderContainer(
        overrides: [
          appRootProvider.overrideWithValue(root),
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          downloadServiceProvider.overrideWithValue(fake),
          diskInfoProvider.overrideWithValue(FakeDisk((_) => free)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(downloadsProvider, (_, _) {});
      downloads = c.read(downloadsProvider.notifier);
    });

    Future<void> tick() => Future<void>.delayed(Duration.zero);

    test('one at a time, in the order picked; the next starts when one ends', () async {
      final first = downloads.start(a);
      unawaited(downloads.start(b));
      unawaited(downloads.start(d));
      unawaited(downloads.start(b)); // already queued: not twice
      await tick();
      expect(fake.started, ['1']);
      expect(c.read(downloadsProvider)['2']!.phase, DownloadPhase.queued);
      expect(downloads.queue.map((g) => g.id), ['2', '3']);
      expect(downloads.pending, 3);
      fake.holds['1']!.complete();
      await first;
      await tick();
      expect(fake.started, ['1', '2']);
      expect(downloads.finished.map((g) => g.id), ['1']);
      expect(c.read(downloadsProvider).containsKey('1'), isFalse);
    });

    test('Y puts a waiting one first; X takes it out of the queue, or stops the running one', () async {
      unawaited(downloads.start(a));
      unawaited(downloads.start(b));
      final last = downloads.start(d);
      await tick();
      downloads.moveToFront('3');
      expect(downloads.queue.map((g) => g.id), ['3', '2']);
      downloads.cancel('2');
      await tick();
      expect(downloads.queue.map((g) => g.id), ['3']);
      expect(c.read(downloadsProvider).containsKey('2'), isFalse);
      downloads.cancel('1');
      await tick();
      await tick();
      expect(fake.started, ['1', '3'], reason: 'the stopped one gave way to the next');
      expect(downloads.failed, isEmpty, reason: 'stopped is not failed');
      fake.holds['3']!.complete();
      await last;
      expect(downloads.pending, 0);
    });

    test('startAll (#226): queued together in order, those running or waiting left as they are', () async {
      unawaited(downloads.start(a));
      await tick();
      downloads.startAll([a, b, d]);
      await tick();
      expect(fake.started, ['1']);
      expect(downloads.queue.map((g) => g.id), ['2', '3']);
    });

    test('startAll that does not fit queues none of them', () async {
      free = 1500;
      expect(() => downloads.startAll([a, b, d]), throwsA(isA<NotEnoughSpace>()));
      expect(downloads.pending, 0);
    });

    test('outside Only download (#228) the queue waits and says until when; Download now starts one', () async {
      final prefs = MemoryPrefs();
      await prefs.setString(DownloadLimits.windowKey, '22:00-07:00');
      final timed = ProviderContainer(
        overrides: [
          appRootProvider.overrideWithValue(c.read(appRootProvider)),
          appPreferencesProvider.overrideWithValue(prefs),
          downloadServiceProvider.overrideWithValue(fake),
          diskInfoProvider.overrideWithValue(FakeDisk((_) => null)),
          downloadClockProvider.overrideWithValue(() => DateTime(2026, 10, 31, 12)),
        ],
      );
      addTearDown(timed.dispose);
      timed.listen(downloadsProvider, (_, _) {});
      final q = timed.read(downloadsProvider.notifier);
      unawaited(q.start(a));
      unawaited(q.start(b));
      await tick();
      expect(fake.started, isEmpty);
      expect(q.waitsUntil, DateTime(2026, 10, 31, 22));
      q.startNow('2');
      await tick();
      expect(fake.started, ['2']);
      expect(q.waitsUntil, isNull);
      expect(q.queue.map((g) => g.id), ['1'], reason: 'the rest still wait');
      q.cancel('1');
      expect(q.waitsUntil, isNull, reason: 'nothing left to wait');
    });

    test('Cancel all (#226) empties the queue; the running one goes on', () async {
      unawaited(downloads.start(a));
      final waitingB = downloads.start(b);
      final waitingD = downloads.start(d);
      await tick();
      downloads.cancelQueued();
      await waitingB;
      await waitingD;
      expect(downloads.queue, isEmpty);
      expect(downloads.current?.id, '1');
      expect(c.read(downloadsProvider).keys, ['1']);
    });

    test('queued only when it fits with everything before it', () async {
      const gb = 1 << 30;
      Game sized(int id) => Game.fromJson({...gameJson(id, 'G$id'), 'file_size_bytes': 2 * gb});
      free = 5 * gb; // room for two of them, not three
      unawaited(downloads.start(sized(1)));
      unawaited(downloads.start(sized(2)));
      unawaited(downloads.start(sized(3)));
      await tick();
      expect(downloads.queue.map((g) => g.id), ['2']);
      expect(c.read(downloadsProvider)['3']!.phase, DownloadPhase.failed);
      expect(c.read(downloadsProvider)['3']!.error, startsWith('With the downloads before it: Needs 6.0 GB'));
      fake.holds['1']!.complete();
    });

    test('a failed one is listed until retried, and the queue goes on', () async {
      fake.fail.add('1');
      final first = downloads.start(a);
      unawaited(downloads.start(b));
      fake.holds['1']!.complete();
      await first;
      await tick();
      expect(downloads.failed.map((g) => g.id), ['1']);
      expect(c.read(downloadsProvider)['1']!.error, contains('no room'));
      expect(fake.started, ['1', '2']);
      expect(downloads.anything, isTrue);
      fake.fail.clear();
      fake.holds['1'] = Completer<void>()..complete();
      unawaited(downloads.start(a));
      await tick();
      expect(downloads.queue.map((g) => g.id), ['1'], reason: 'waits for B');
    });
  });
}
