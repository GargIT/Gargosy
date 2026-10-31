import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/download_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/widgets/download_all_button.dart';

import '../helpers/fake_disk.dart';
import '../helpers/fake_download_service.dart';
import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  Future<FakeDownloadService> pump(WidgetTester tester, {int? free}) async {
    final root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    final fake = FakeDownloadService(RomFiles(root), PathGuard(root));
    for (final id in ['1', '2', '3']) {
      fake.holds[id] = Completer<void>();
    }
    await tester.pumpWidget(
      testApp(
        const Center(child: DownloadAllButton(query: GalleryQuery(platformId: 1))),
        root: root,
        overrides: [
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          libraryApiProvider.overrideWithValue(FakeLibraryApi([game(1, 'A'), game(2, 'B'), game(3, 'C')])),
          downloadServiceProvider.overrideWithValue(fake),
          diskInfoProvider.overrideWithValue(FakeDisk((_) => free)),
        ],
      ),
    );
    return fake;
  }

  testWidgets("Download all asks with the count and size, then queues them in the gallery's order", (tester) async {
    final fake = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('download-all')));
    await tester.pumpAndSettle();
    expect(find.text('Download 3 games?'), findsOneWidget);
    expect(find.textContaining('About 2.9 KB in all'), findsOneWidget);
    await tester.tap(find.text('Download all').last);
    await tester.pumpAndSettle();
    expect(fake.started, ['1']);
  });

  testWidgets('not enough room: said, nothing asked or queued', (tester) async {
    final fake = await pump(tester, free: 100);
    await tester.tap(find.byKey(const ValueKey('download-all')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Needs'), findsOneWidget);
    expect(find.text('Download 3 games?'), findsNothing);
    expect(fake.started, isEmpty);
    await tester.pump(const Duration(seconds: 10));
  });
}
