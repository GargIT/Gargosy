import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/download_providers.dart';

import '../helpers/fake_download_service.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

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
    final a = game(1, 'A'), b = game(2, 'B'), d = game(3, 'D');

    setUp(() async {
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
