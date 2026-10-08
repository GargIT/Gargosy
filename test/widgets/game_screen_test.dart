import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/download_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';

import '../helpers/fake_download_service.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  late AppRoot root;
  late FakeDownloadService downloads;

  final burnout = Game.fromJson({
    ...gameJson(7564, 'Burnout 3: Takedown', fsName: 'Burnout 3 (USA).chd'),
    'summary': 'Crash your rivals.',
    'metadatum': {'genres': ['Racing'], 'first_release_date': 1094428800000},
    'regions': ['USA'],
  });

  Future<void> pump(WidgetTester tester, {Set<String> favourites = const {}}) async {
    await setDesktopSize(tester);
    root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    downloads = FakeDownloadService(RomFiles(root), PathGuard(root));
    await tester.pumpWidget(testApp(GameScreen(game: burnout), root: root, overrides: [
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
      gameProvider.overrideWith((ref, id) async => burnout),
      favouriteIdsProvider.overrideWithValue(favourites),
      downloadServiceProvider.overrideWithValue(downloads),
      romSavesProvider.overrideWith((ref, id) async => [{'id': 1, 'file_name': 'burnout.ps2', 'emulator': 'pcsx2'}]),
      romStatesProvider.overrideWith((ref, id) async => const []),
      romNotesProvider.overrideWith((ref, id) async => const []),
      raProgressionProvider.overrideWith((ref) async => const {}),
    ]));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title, platform, year and the Overview', (tester) async {
    await pump(tester);
    expect(find.text('Burnout 3: Takedown'), findsWidgets); // the title, and the cover's placeholder art (no server in tests)
    expect(find.textContaining('PlayStation 2'), findsWidgets);
    expect(find.textContaining('2004'), findsWidgets);
    expect(find.text('Crash your rivals.'), findsOneWidget);
    expect(find.text('Racing'), findsOneWidget);
  });

  testWidgets('RB and LB walk the tabs; Details lists the file', (tester) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await press(tester, GameAction.r1);
    }
    expect(find.text('Burnout 3 (USA).chd'), findsOneWidget);
    await press(tester, GameAction.r1); // stays on the last tab
    expect(find.text('Burnout 3 (USA).chd'), findsOneWidget);
    await press(tester, GameAction.l1);
    await press(tester, GameAction.l1);
    await press(tester, GameAction.l1);
    await press(tester, GameAction.l1);
    expect(find.text('Crash your rivals.'), findsOneWidget);
  });

  testWidgets('Download puts the ROM in roms\\, then Delete removes it after asking', (tester) async {
    await pump(tester);
    expect(find.textContaining('Download'), findsOneWidget);
    await press(tester, GameAction.confirm); // Download has focus
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(downloads.started, ['7564']);
    expect(RomFiles(root).isDownloaded(burnout), isTrue);
    expect(find.text('Delete from this PC'), findsOneWidget);
    await tester.tap(find.text('Delete from this PC'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete Burnout 3: Takedown from this PC?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(RomFiles(root).isDownloaded(burnout), isFalse);
  });

  testWidgets('a favourite shows a filled heart', (tester) async {
    await pump(tester, favourites: {'7564'});
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('while unpacking there is no Cancel (it could not stop the unzip)', (tester) async {
    await pump(tester);
    downloads.hold = Completer<void>();
    downloads.holdIn = DownloadPhase.extracting;
    await press(tester, GameAction.confirm);
    expect(find.text('Unpacking…'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    downloads.hold!.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  });

  testWidgets('LB/RB keep working after switching tabs from inside a tab', (tester) async {
    await pump(tester);
    await press(tester, GameAction.r1); // Save data
    Focus.of(tester.element(find.text('burnout.ps2'))).requestFocus();
    await tester.pumpAndSettle();
    await press(tester, GameAction.r1); // Achievements
    await press(tester, GameAction.r1); // Notes
    expect(find.text('Add a note'), findsOneWidget);
  });
}
