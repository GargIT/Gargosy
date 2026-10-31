import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/ui/screens/storage_platform_screen.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  testWidgets("largest first; X marks, Delete marked asks, then only the ROMs go", (tester) async {
    await setDesktopSize(tester);
    final root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    final crash = game(1, 'Crash Bandicoot', platform: 'psx', fsName: 'Crash.chd');
    void file(String name, int bytes) => io.File(p.join(root.roms, 'psx', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(bytes, 1));
    file('Crash.chd', 3000);
    file('Spyro.chd', 1000);
    file('Other.chd', 2000);
    await tester.pumpWidget(
      testApp(
        const StoragePlatformScreen(folder: 'psx'),
        root: root,
        overrides: [
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          gamesOnThisPcProvider.overrideWithValue([crash]),
          platformsProvider.overrideWith((ref) async => [Platform(id: 1, name: 'PlayStation', slug: 'psx')]),
        ],
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('PlayStation'), findsOneWidget);
    double y(String name) => tester.getTopLeft(find.byKey(ValueKey('storage-rom-$name'))).dy;
    expect(y('Crash.chd') < y('Other.chd') && y('Other.chd') < y('Spyro.chd'), isTrue);
    expect(find.text('Crash Bandicoot'), findsOneWidget, reason: "this profile's game by its name");
    expect(find.textContaining("not in this profile's library"), findsNWidgets(2));

    await press(tester, GameAction.detail); // Crash
    await press(tester, GameAction.down);
    await press(tester, GameAction.detail); // Other
    expect(find.textContaining('Delete marked (2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('storage-delete-marked')));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 games from this PC?'), findsOneWidget);
    expect(find.textContaining('another profile may have downloaded it'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    // Real file work: given time until it's done (a slow CI runner needs more than a moment).
    for (var i = 0; i < 40 && io.File(p.join(root.roms, 'psx', 'Other.chd')).existsSync(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(RomFiles(root).isDownloaded(crash), isFalse);
    expect(io.File(p.join(root.roms, 'psx', 'Other.chd')).existsSync(), isFalse);
    expect(io.File(p.join(root.roms, 'psx', 'Spyro.chd')).existsSync(), isTrue);
    expect(find.byKey(const ValueKey('storage-rom-Spyro.chd')), findsOneWidget);
  });
}
