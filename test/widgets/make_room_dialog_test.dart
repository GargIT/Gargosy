import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/disk_space.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/download_providers.dart';
import 'package:gargosy/ui/widgets/make_room_dialog.dart';

import '../helpers/fake_disk.dart';
import '../helpers/fake_download_service.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  late AppRoot root;
  late FakeDownloadService fake;
  int? free;
  final wanted = Game.fromJson(gameJson(9, 'Wanted', size: 300));
  final old = Game.fromJson({
    ...gameJson(1, 'Old', size: 250),
    'rom_user': {'last_played': '2020-01-01T00:00:00Z'},
  });
  final recent = Game.fromJson({
    ...gameJson(2, 'Recent', size: 250),
    'rom_user': {'last_played': '2026-10-30T00:00:00Z'},
  });

  Future<void> pump(WidgetTester tester) async {
    root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    fake = FakeDownloadService(RomFiles(root), PathGuard(root));
    fake.holds['9'] = Completer<void>();
    for (final g in [old, recent]) {
      io.File(RomFiles(root).pathFor(g))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List<int>.filled(250, 1));
    }
    // 100 bytes over the headroom: 300 to download leaves 200 short.
    free = spaceHeadroom + 100;
    await tester.pumpWidget(
      testApp(
        Consumer(
          builder: (context, ref, _) =>
              TextButton(onPressed: () => downloadOrMakeRoom(context, ref, wanted), child: const Text('download')),
        ),
        root: root,
        overrides: [
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          downloadServiceProvider.overrideWithValue(fake),
          diskInfoProvider.overrideWithValue(FakeDisk((_) => free)),
          gamesOnThisPcProvider.overrideWithValue([recent, old]),
          uploadQueueProvider.overrideWith((ref) async => null),
        ],
      ),
    );
    await tester.tap(find.text('download'));
    await tester.pumpAndSettle();
  }

  testWidgets("doesn't fit: the game not played for longest is ticked; deleted, then it downloads", (tester) async {
    await pump(tester);
    expect(find.text('Make room?'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.textContaining('Frees 250 B'), findsOneWidget);
    free = spaceHeadroom + 1000; // what the delete frees
    await tester.tap(find.text('Delete and download'));
    for (var i = 0; i < 20 && fake.started.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('Make room?'), findsNothing, reason: 'closed');
    expect(fake.started, ['9']);
    expect(io.File(RomFiles(root).pathFor(old)).existsSync(), isFalse);
    expect(io.File(RomFiles(root).pathFor(recent)).existsSync(), isTrue);
  });

  testWidgets('Cancel deletes nothing and downloads nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(io.File(RomFiles(root).pathFor(old)).existsSync(), isTrue);
    expect(fake.started, isEmpty);
  });
}
