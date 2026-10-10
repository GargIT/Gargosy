import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/constants/app_constants.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/engine_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/settings/about_section.dart';
import 'package:gargosy/ui/screens/settings/settings_screen.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/shell/app_shell.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
import 'package:gargosy/ui/widgets/cover_image.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late ProviderContainer c;

  Future<void> pump(WidgetTester tester, {List<Override> extra = const []}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = await tester.runAsync(tempAppRoot);
    addTearDown(() => io.Directory(root!.root).deleteSync(recursive: true));
    c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root!),
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
      // The real pages, with a library that never touches RomM.
      coverImageBuilderProvider.overrideWithValue((url) => const ColoredBox(color: Colors.grey)),
      recentlyPlayedProvider.overrideWith((ref) async => [for (var i = 21; i <= 30; i++) game(i, 'G$i')]),
      recentlyAddedProvider.overrideWith((ref) async => [for (var i = 1; i <= 20; i++) game(i, 'G$i')]),
      favouriteGamesProvider.overrideWith((ref) async => [for (var i = 31; i <= 40; i++) game(i, 'G$i')]),
      randomGameProvider.overrideWith((ref) async => game(41, 'Pick')),
      platformsProvider.overrideWith((ref) async => const []),
      collectionsProvider.overrideWith((ref) async => const []),
      favouriteIdsProvider.overrideWithValue(const {}),
      rommHeartbeatEnabledProvider.overrideWithValue(false),
      uploadQueueProvider.overrideWith((ref) async => null),
      ...extra,
    ]);
    addTearDown(c.dispose);
    final anna = await tester.runAsync(() => c.read(profileStoreProvider).create(
        name: 'Anna', colorIndex: 1, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna'));
    await tester.runAsync(() => c.read(activeProfileProvider.notifier).activate(anna!, const ProfileLogin(token: 't', kind: 'device')));
    final nav = GlobalKey<NavigatorState>();
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

  Future<void> send(WidgetTester tester, GameAction a) async {
    inputActionBus.add(a);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the logo, the four v2 tabs and the profile badge; Home first', (tester) async {
    await pump(tester);
    for (final t in shellTabs) {
      expect(find.text(t), findsWidgets);
    }
    expect(find.byKey(const Key('page-Home')), findsOneWidget);
    expect(find.text('Welcome, Anna'), findsOneWidget);
    expect(find.byKey(const Key('top-bar-logo')), findsOneWidget);
  });

  testWidgets('RB and LB move between tabs and stop at the ends', (tester) async {
    await pump(tester);
    await send(tester, GameAction.r1);
    expect(find.byKey(const Key('page-Platforms')), findsOneWidget);
    await send(tester, GameAction.r1);
    await send(tester, GameAction.r1);
    await send(tester, GameAction.r1);
    expect(find.byKey(const Key('page-Search')), findsOneWidget);
    await send(tester, GameAction.l1);
    expect(find.byKey(const Key('page-Collections')), findsOneWidget);
  });

  testWidgets('Start opens the user menu; Switch profile signs out', (tester) async {
    await pump(tester);
    await send(tester, GameAction.start);
    expect(find.text('Switch profile'), findsOneWidget);
    await tester.tap(find.text('Switch profile'));
    await tester.pumpAndSettle();
    expect(c.read(activeProfileProvider), isNull);
  });

  testWidgets("the user menu shows Gargosy's version to the right of the profile name", (tester) async {
    final was = AppConstants.version;
    addTearDown(() => AppConstants.version = was);
    AppConstants.version = '1.2.3';
    await pump(tester);
    await send(tester, GameAction.start);
    final version = find.text('v1.2.3');
    expect(version, findsOneWidget);
    // The menu's name heading: the last one built (the menu is on top).
    final nameBox = tester.getRect(find.text(c.read(activeProfileProvider)!.profile.name).last);
    expect(tester.getRect(version).left, greaterThan(nameBox.right));
    expect(tester.getCenter(version).dy, closeTo(nameBox.center.dy, 8));
  });

  testWidgets('B closes the user menu', (tester) async {
    await pump(tester);
    await send(tester, GameAction.start);
    await send(tester, GameAction.back);
    expect(find.text('Switch profile'), findsNothing);
    expect(c.read(activeProfileProvider), isNotNull);
  });

  testWidgets('focus comes back to the tab it left when the menu closes', (tester) async {
    await pump(tester);
    await send(tester, GameAction.r1);
    final before = FocusManager.instance.primaryFocus;
    await send(tester, GameAction.start);
    await send(tester, GameAction.back);
    expect(FocusManager.instance.primaryFocus, before);
  });

  testWidgets('the top bar turns to glass when the page scrolls', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('top-bar-glass')), findsNothing);
    await tester.drag(find.byKey(const Key('page-Home')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top-bar-glass')), findsOneWidget);
  });

  testWidgets('scrolling a shelf sideways does not turn the bar to glass', (tester) async {
    await pump(tester);
    await tester.drag(find.text('G1'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top-bar-glass')), findsNothing);
  });

  testWidgets('the user menu opens the emulators screen', (tester) async {
    await pump(tester);
    await send(tester, GameAction.start);
    expect(find.text('Emulators'), findsOneWidget);
  });

  testWidgets('switching profile during a game is refused', (tester) async {
    await pump(tester);
    c.read(playControllerProvider.notifier).state = const PlayState(runningGameId: '1');
    await send(tester, GameAction.start);
    await tester.tap(find.text('Switch profile'));
    await tester.pumpAndSettle();
    expect(c.read(activeProfileProvider), isNotNull);
    expect(find.textContaining('Close the game first'), findsOneWidget);
  });

  testWidgets('a banner shows while RomM is unreachable', (tester) async {
    await pump(tester, extra: [rommOfflineProvider.overrideWithValue(true)]);
    expect(find.textContaining("RomM can't be reached"), findsOneWidget);
  });

  testWidgets('saves waiting to upload go up when RomM is back', (tester) async {
    final offline = StateProvider<bool>((ref) => true);
    final waiting = <({String romId, BackupEntry entry})>[];
    final pushed = <String>[];
    final queue = UploadQueue(
      isOffline: () => false,
      pending: () => [...waiting],
      markSynced: (id, e) async => waiting.removeWhere((w) => w.entry == e),
      gameById: (id) async => game(int.parse(id), 'G$id'),
      romPathFor: (g) async => 'roms/${g.id}',
      push: (g, romPath, e) async {
        pushed.add(g.id);
        return true;
      },
    );
    await pump(tester, extra: [
      rommOfflineProvider.overrideWith((ref) => ref.watch(offline)),
      uploadQueueProvider.overrideWith((ref) async => queue),
    ]);
    waiting.add((romId: '5', entry: BackupEntry(timestamp: DateTime(2026), md5Hash: 'h', localZipPath: 'z.zip')));
    c.read(offline.notifier).state = false;
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(pushed, ['5']);
    expect(find.textContaining('1 save that was waiting'), findsOneWidget);
  });

  testWidgets('Start → Settings opens the settings', (tester) async {
    await pump(tester);
    await send(tester, GameAction.start);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Start → About opens the About dialog', (tester) async {
    await pump(tester);
    await send(tester, GameAction.start);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutSection), findsOneWidget);
  });

  testWidgets('switching profile waits for a running sync, saying what it waits for', (tester) async {
    final activity = ValueNotifier<String?>("Uploading Okami's save");
    await pump(tester, extra: [syncActivityProvider.overrideWithValue(activity)]);
    await send(tester, GameAction.start);
    await tester.tap(find.text('Switch profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Uploading Okami's save"), findsOneWidget);
    expect(c.read(activeProfileProvider), isNotNull);
    activity.value = null;
    await tester.pumpAndSettle();
    expect(c.read(activeProfileProvider), isNull);
  });

  testWidgets('switching profile also waits for saves still going up from the queue', (tester) async {
    final queue = UploadQueue(
      isOffline: () => false,
      pending: () => const [],
      markSynced: (_, _) async {},
      gameById: (_) async => null,
      romPathFor: (_) async => null,
      push: (_, _, _) async => false,
    );
    await pump(tester, extra: [uploadQueueProvider.overrideWith((ref) async => queue)]);
    queue.running.value = true;
    await send(tester, GameAction.start);
    await tester.tap(find.text('Switch profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('saves that were waiting'), findsOneWidget);
    expect(c.read(activeProfileProvider), isNotNull);
    queue.running.value = false;
    await tester.pumpAndSettle();
    expect(c.read(activeProfileProvider), isNull);
  });
}
