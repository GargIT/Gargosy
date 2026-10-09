import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/gallery_screen.dart';
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
  late ProviderContainer c;
  late GlobalKey<NavigatorState> nav;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = await tester.runAsync(tempAppRoot);
    addTearDown(() => io.Directory(root!.root).deleteSync(recursive: true));
    final g1 = game(1, 'G1');
    c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root!),
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
      coverImageBuilderProvider.overrideWithValue((url) => const ColoredBox(color: Colors.grey)),
      recentlyPlayedProvider.overrideWith((ref) async => [g1]),
      recentlyAddedProvider.overrideWith((ref) async => const []),
      favouriteGamesProvider.overrideWith((ref) async => const []),
      randomGameProvider.overrideWith((ref) async => null),
      platformsProvider.overrideWith((ref) async => const []),
      collectionsProvider.overrideWith((ref) async => const []),
      favouriteIdsProvider.overrideWithValue(const {}),
      libraryApiProvider.overrideWithValue(FakeLibraryApi([g1])),
      gameProvider.overrideWith((ref, id) async => g1),
      romSavesProvider.overrideWith((ref, id) async => const []),
      romStatesProvider.overrideWith((ref, id) async => const []),
      romNotesProvider.overrideWith((ref, id) async => const []),
      raProgressionProvider.overrideWith((ref) async => const {}),
      playEngineProvider.overrideWithValue(FakeEngine()),
      rommHeartbeatEnabledProvider.overrideWithValue(false),
      uploadQueueProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(c.dispose);
    final anna = await tester.runAsync(() => c.read(profileStoreProvider).create(
        name: 'Anna', colorIndex: 1, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna'));
    await tester.runAsync(() => c.read(activeProfileProvider.notifier).activate(anna!, const ProfileLogin(token: 't', kind: 'device')));
    nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: nav,
        theme: gargosyTheme(),
        builder: (context, child) => InputRouter(navigatorKey: nav, startGamepads: false, child: child!),
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, Widget page) async {
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pumpAndSettle();
  }

  testWidgets('the game page has the top bar, with no tab lit', (tester) async {
    await pump(tester);
    await open(tester, GameScreen(game: game(1, 'G1')));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byKey(const Key('top-bar-logo')), findsWidgets);
    expect(find.descendant(of: find.byType(GameScreen), matching: find.text('Platforms')), findsOneWidget);
    expect(find.descendant(of: find.byType(GameScreen), matching: find.byKey(const Key('top-bar-tab-lit'))), findsNothing);
  });

  testWidgets('the gallery has the top bar too', (tester) async {
    await pump(tester);
    await open(tester, const GalleryScreen(title: 'PS2', query: GalleryQuery()));
    expect(find.descendant(of: find.byType(GalleryScreen), matching: find.byKey(const Key('top-bar-logo'))), findsOneWidget);
  });

  testWidgets('a tab from a page two deep returns to the shell on that tab', (tester) async {
    await pump(tester);
    await open(tester, const GalleryScreen(title: 'PS2', query: GalleryQuery()));
    await open(tester, GameScreen(game: game(1, 'G1')));
    await tester.tap(find.descendant(of: find.byType(GameScreen), matching: find.text('Collections')));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsNothing);
    expect(find.byType(GalleryScreen), findsNothing);
    expect(c.read(shellTabProvider), 2);
  });

  testWidgets('Start on the game page opens the user menu', (tester) async {
    await pump(tester);
    await open(tester, GameScreen(game: game(1, 'G1')));
    inputActionBus.add(GameAction.start);
    await tester.pumpAndSettle();
    expect(find.text('Switch profile'), findsOneWidget);
  });

  testWidgets('the play screen has no top bar', (tester) async {
    await pump(tester);
    await open(tester, PlayScreen(game: game(1, 'G1')));
    expect(find.descendant(of: find.byType(PlayScreen), matching: find.byKey(const Key('top-bar-logo'))), findsNothing);
  });
}
