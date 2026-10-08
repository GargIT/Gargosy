import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/shell/app_shell.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';

import '../helpers/profile_test_env.dart';

void main() {
  late ProviderContainer c;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = await tester.runAsync(tempAppRoot);
    addTearDown(() => io.Directory(root!.root).deleteSync(recursive: true));
    c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root!),
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
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
}
