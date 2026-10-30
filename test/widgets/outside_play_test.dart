import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/catalog/save_catalog.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/play/outside_launch.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/play/play_menu.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/providers/update_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';
import 'package:gargosy/ui/screens/play/play_screen.dart';
import 'package:gargosy/ui/shell/app_shell.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
import 'package:gargosy/ui/widgets/cover_image.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../unit/play_controller_test.dart' show FakeEngine;

void main() {
  late FakeEngine engine;
  late int quits;

  /// The shell of an open profile, started with [launch]; [found] is what
  /// RomM gives for the game.
  Future<void> pump(WidgetTester tester, OutsideLaunch launch, {Game? found, bool downloaded = true}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = await tester.runAsync(tempAppRoot);
    addTearDown(() => io.Directory(root!.root).deleteSync(recursive: true));
    quits = 0;
    engine = FakeEngine()
      ..downloaded = downloaded
      ..menu = const PlayMenu(
        emulators: [EmulatorOption(SaveMaker('pcsx2'), 'PCSX2')],
        platformDefault: SaveMaker('pcsx2'),
        catalog: SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false),
      );
    final c = ProviderContainer(
      overrides: [
        appRootProvider.overrideWithValue(root!),
        appPreferencesProvider.overrideWithValue(MemoryPrefs()),
        coverImageBuilderProvider.overrideWithValue((url) => const ColoredBox(color: Colors.grey)),
        recentlyPlayedProvider.overrideWith((ref) async => const []),
        recentlyAddedProvider.overrideWith((ref) async => const []),
        favouriteGamesProvider.overrideWith((ref) async => const []),
        randomGameProvider.overrideWith((ref) async => null),
        platformsProvider.overrideWith((ref) async => const []),
        collectionsProvider.overrideWith((ref) async => const []),
        favouriteIdsProvider.overrideWithValue(const {}),
        libraryApiProvider.overrideWithValue(FakeLibraryApi(const [])),
        gameProvider.overrideWith((ref, id) async => found),
        romSavesProvider.overrideWith((ref, id) async => const []),
        romStatesProvider.overrideWith((ref, id) async => const []),
        romNotesProvider.overrideWith((ref, id) async => const []),
        raProgressionProvider.overrideWith((ref) async => const {}),
        playEngineProvider.overrideWithValue(engine),
        rommHeartbeatEnabledProvider.overrideWithValue(false),
        uploadQueueProvider.overrideWith((ref) async => null),
        appQuitProvider.overrideWithValue(() async => quits++),
        outsideLaunchProvider.overrideWith((ref) => launch),
      ],
    );
    addTearDown(c.dispose);
    final anna = await tester.runAsync(
      () => c
          .read(profileStoreProvider)
          .create(name: 'Anna', colorIndex: 1, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna'),
    );
    await tester.runAsync(
      () => c.read(activeProfileProvider.notifier).activate(anna!, const ProfileLogin(token: 't', kind: 'device')),
    );
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          navigatorKey: nav,
          theme: gargosyTheme(),
          builder: (context, child) => InputRouter(navigatorKey: nav, startGamepads: false, child: child!),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the game starts on its page, and Gargosy closes once the session has ended', (tester) async {
    await pump(tester, const OutsideLaunch(romId: '1'), found: game(1, 'G1'));
    expect(engine.steps, ['states', 'prepare', 'launch']);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(PlayScreen), findsNothing);
    expect(quits, 0, reason: 'not while the game runs');
    engine.running!.complete(const PlayResult('Save synced', synced: true));
    await tester.pumpAndSettle();
    expect(quits, 1);
  });

  testWidgets('a save that did not reach RomM is said before Gargosy closes', (tester) async {
    await pump(tester, const OutsideLaunch(romId: '1'), found: game(1, 'G1'));
    engine.running!.complete(const PlayResult('Saves not synced: offline', saveProblem: true));
    await tester.pumpAndSettle();
    expect(find.text("Your save didn't reach RomM"), findsOneWidget);
    expect(find.text('Saves not synced: offline'), findsWidgets);
    expect(quits, 0);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(quits, 1);
  });

  testWidgets('--play-stay keeps Gargosy open after the session', (tester) async {
    await pump(tester, const OutsideLaunch(romId: '1', stay: true), found: game(1, 'G1'));
    engine.running!.complete(const PlayResult('Save synced', synced: true));
    await tester.pumpAndSettle();
    expect(quits, 0);
  });

  testWidgets('a game RomM and this PC do not know: said, nothing starts, Gargosy stays', (tester) async {
    await pump(tester, const OutsideLaunch(romId: '99'));
    expect(find.text('Gargosy couldn\'t find the game 99.'), findsOneWidget);
    expect(engine.steps, isEmpty);
    expect(quits, 0);
  });

  testWidgets('a game that is not on this PC: refused on its play screen, Gargosy stays', (tester) async {
    await pump(tester, const OutsideLaunch(romId: '1'), found: game(1, 'G1'), downloaded: false);
    expect(engine.steps, isEmpty);
    expect(find.byType(PlayScreen), findsOneWidget);
    expect(quits, 0);
  });
}
