import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/download_providers.dart';
import 'package:gargosy/ui/screens/downloads_screen.dart';

import '../helpers/fake_download_service.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  final a = game(1, 'Okami'), b = game(2, 'Rez'), d = game(3, 'Ico');

  test('the progress line: how much, how fast, how long', () {
    const mb = 1024 * 1024;
    expect(
      DownloadsScreen.progressLine(
        const DownloadProgress(DownloadPhase.downloading, received: 100 * mb, total: 400 * mb),
        const Duration(seconds: 10),
      ),
      '100 MB of 400 MB · 10 MB/s · 30 s left',
    );
    expect(DownloadsScreen.progressLine(const DownloadProgress(DownloadPhase.extracting), Duration.zero), 'Unpacking…');
  });

  testWidgets('the one running, then the queue; Y puts one first, X takes one out', (tester) async {
    await setDesktopSize(tester);
    final root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    final fake = FakeDownloadService(RomFiles(root), PathGuard(root));
    for (final g in [a, b, d]) {
      fake.holds[g.id] = Completer<void>();
    }
    await tester.pumpWidget(
      testApp(
        const DownloadsScreen(),
        root: root,
        overrides: [
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          downloadServiceProvider.overrideWithValue(fake),
        ],
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(DownloadsScreen)));
    final downloads = c.read(downloadsProvider.notifier);
    expect(find.textContaining('Nothing downloading'), findsOneWidget);
    for (final g in [a, b, d]) {
      unawaited(downloads.start(g));
    }
    await tester.pumpAndSettle();
    expect(find.text('DOWNLOADING'), findsOneWidget);
    expect(find.text('QUEUED · 2'), findsOneWidget);
    double y(String id) => tester.getTopLeft(find.byKey(ValueKey('download-$id'))).dy;
    expect(y('1') < y('2') && y('2') < y('3'), isTrue);

    await press(tester, GameAction.down); // Rez
    await press(tester, GameAction.down); // Ico
    await press(tester, GameAction.favorite);
    expect(y('3') < y('2'), isTrue, reason: 'Ico first in the queue');
    expect(downloads.queue.map((g) => g.id), ['3', '2']);

    await press(tester, GameAction.detail); // X on the focused one
    expect(find.byKey(const ValueKey('download-3')), findsNothing);
    expect(downloads.queue.map((g) => g.id), ['2']);
    for (final h in fake.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('DONE'), findsOneWidget);
  });
}
