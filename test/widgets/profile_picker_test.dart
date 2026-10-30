import 'dart:io' as io;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_auth_client.dart';
import 'package:gargosy/play/outside_launch.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/pin.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/shell/app_shell.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_romm_auth.dart';

void main() {
  late AppHarness h;

  Future<Profile> addProfile(
    WidgetTester tester,
    String name, {
    String? pin,
    bool loggedIn = true,
    int userId = 7,
  }) async {
    final store = h.container.read(profileStoreProvider);
    final p = (await tester.runAsync(
      () => store.create(
        name: name,
        colorIndex: 0,
        serverUrl: 'https://romm.example',
        rommUserId: userId,
        rommUsername: name.toLowerCase(),
        pin: pin == null ? null : PinHash.create(pin, random: Random(3), iterations: 1000),
      ),
    ))!;
    if (loggedIn) {
      await tester.runAsync(
        () => loginStoreForWidgetless(
          h,
          p,
        ).write(ProfilePaths(h.root, p.id).guard, const ProfileLogin(token: 't', kind: 'device')),
      );
    }
    return p;
  }

  testWidgets('with no profiles the picker offers only Add profile', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    await h.pumpApp(tester);
    expect(find.text('Who is playing?'), findsOneWidget);
    expect(find.text('Add profile'), findsOneWidget);
  });

  testWidgets('A on a badge without PIN opens the shell; the last used badge has focus', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    await addProfile(tester, 'Anna');
    final bob = await addProfile(tester, 'Bob', userId: 8);
    await tester.runAsync(() => h.container.read(profileStoreProvider).setLastUsed(bob.id));
    await h.pumpApp(tester);
    await h.send(tester, GameAction.confirm);
    expect(find.byType(AppShell), findsOneWidget);
    expect(h.container.read(activeProfileProvider)!.profile.name, 'Bob');
  });

  testWidgets('a PIN badge asks for the PIN; a wrong PIN stays, the right one opens', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    await addProfile(tester, 'Anna', pin: '4711');
    await h.pumpApp(tester);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    await h.send(tester, GameAction.confirm);
    expect(find.text('PIN for Anna'), findsOneWidget);
    for (final k in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit1,
    ]) {
      await tester.sendKeyEvent(k);
    }
    await h.settle(tester);
    expect(find.text('Wrong PIN'), findsOneWidget);
    for (final k in [
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit1,
    ]) {
      await tester.sendKeyEvent(k);
    }
    await h.settle(tester, until: find.byType(AppShell));
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('without a login on this PC the badge asks to log in again', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    await addProfile(tester, 'Anna', loggedIn: false);
    h.auth = FakeRommAuth(start: null); // password fallback
    await h.pumpApp(tester);
    expect(find.text('Log in again'), findsOneWidget);
    await h.send(tester, GameAction.confirm);
    expect(find.textContaining('Log in to'), findsOneWidget);
  });

  testWidgets('re-login as another RomM user is refused and nothing is saved', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    final anna = await addProfile(tester, 'Anna', loggedIn: false, userId: 7);
    h.auth = FakeRommAuth(
      start: const DeviceAuthStart(
        deviceCode: 'dc',
        userCode: 'CODE-1',
        verificationUrl: 'https://romm.example/pair/device?user_code=CODE-1',
        expiresIn: 600,
        interval: 1,
      ),
      polls: [const DeviceApproved(token: 'bobs', deviceId: 'd')],
      me: const RommUser(id: 8, username: 'bob', avatarPath: '', oauthScopes: []),
    );
    await h.pumpApp(tester);
    await h.send(tester, GameAction.confirm);
    await h.settle(tester);
    expect(find.textContaining('different RomM user'), findsOneWidget);
    expect(await tester.runAsync(() => loginStoreForWidgetless(h, anna).read()), isNull);
    expect(h.container.read(activeProfileProvider), isNull);
  });

  testWidgets('X opens options; deleting a profile with a PIN needs the PIN, then asks to confirm', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    final anna = await addProfile(tester, 'Anna', pin: '1234');
    await h.pumpApp(tester);
    await h.send(tester, GameAction.detail);
    expect(find.text('Delete profile'), findsOneWidget);
    await tester.tap(find.text('Delete profile'));
    await tester.pumpAndSettle();
    expect(find.text('PIN for Anna'), findsOneWidget);
    for (final k in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyEvent(k);
    }
    await h.settle(tester);
    expect(find.textContaining('Delete Anna?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await h.settle(tester);
    expect(io.Directory(ProfilePaths(h.root, anna.id).dir).existsSync(), isFalse);
    expect(find.text('Anna'), findsNothing);
  });

  testWidgets('password re-login as another RomM user is refused and no token is made', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    final anna = await addProfile(tester, 'Anna', loggedIn: false, userId: 7);
    h.auth = FakeRommAuth(
      start: null,
      me: const RommUser(id: 8, username: 'bob', avatarPath: '', oauthScopes: []),
    );
    await h.pumpApp(tester);
    await h.send(tester, GameAction.confirm);
    await tester.tap(find.text('Log in'));
    await h.settle(tester);
    expect(find.textContaining('different RomM user (bob)'), findsOneWidget);
    expect(h.auth.passwordLogins, isEmpty);
    expect(await tester.runAsync(() => loginStoreForWidgetless(h, anna).read()), isNull);
  });

  testWidgets('if the login cannot be saved on re-login, the error shows and the profile does not open', (
    tester,
  ) async {
    h = AppHarness();
    await h.setUp(tester);
    await addProfile(tester, 'Anna', loggedIn: false, userId: 7);
    h.auth = FakeRommAuth(start: null);
    await h.pumpApp(tester);
    await h.send(tester, GameAction.confirm);
    h.secrets.failProtect = true;
    await tester.tap(find.text('Log in'));
    await h.settle(tester);
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(h.container.read(activeProfileProvider), isNull);
  });

  group('started with --play (#223)', () {
    testWidgets('the named profile opens without a press, and the shell takes the launch', (tester) async {
      h = AppHarness();
      await h.setUp(tester);
      await addProfile(tester, 'Anna');
      final bob = await addProfile(tester, 'Bob', userId: 8);
      h.container.read(outsideLaunchProvider.notifier).state = OutsideLaunch(romId: '1', profileId: bob.id);
      await h.pumpApp(tester);
      await h.settle(tester, until: find.byType(AppShell));
      expect(h.container.read(activeProfileProvider)!.profile.name, 'Bob');
      expect(h.container.read(outsideLaunchProvider), isNull);
    });

    testWidgets('several profiles and none named: the picker asks, and the one picked plays it', (tester) async {
      h = AppHarness();
      await h.setUp(tester);
      await addProfile(tester, 'Anna');
      final bob = await addProfile(tester, 'Bob', userId: 8);
      await tester.runAsync(() => h.container.read(profileStoreProvider).setLastUsed(bob.id));
      h.container.read(outsideLaunchProvider.notifier).state = const OutsideLaunch(romId: '1');
      await h.pumpApp(tester);
      expect(find.text('Who is playing?'), findsOneWidget, reason: 'never the last used on its own');
      expect(h.container.read(outsideLaunchProvider), isNotNull);
      await h.send(tester, GameAction.confirm);
      await h.settle(tester, until: find.byType(AppShell));
      expect(h.container.read(activeProfileProvider)!.profile.name, 'Bob');
      expect(h.container.read(outsideLaunchProvider), isNull, reason: 'the shell took it');
    });

    testWidgets('a badge picked by hand for another profile than the named one drops the launch', (tester) async {
      h = AppHarness();
      await h.setUp(tester);
      final anna = await addProfile(tester, 'Anna', pin: '4711');
      await addProfile(tester, 'Bob', userId: 8);
      h.container.read(outsideLaunchProvider.notifier).state = OutsideLaunch(romId: '1', profileId: anna.id);
      await h.pumpApp(tester);
      expect(find.text('PIN for Anna'), findsOneWidget);
      await h.send(tester, GameAction.back);
      expect(h.container.read(outsideLaunchProvider), isNull);
    });

    testWidgets('handed over to the picker by a later start: the named profile opens', (tester) async {
      h = AppHarness();
      await h.setUp(tester);
      await addProfile(tester, 'Anna');
      final bob = await addProfile(tester, 'Bob', userId: 8);
      await h.pumpApp(tester);
      expect(find.text('Who is playing?'), findsOneWidget);
      h.container.read(outsideLaunchProvider.notifier).state = OutsideLaunch(romId: '1', profileId: bob.id);
      await h.settle(tester, until: find.byType(AppShell));
      expect(h.container.read(activeProfileProvider)!.profile.name, 'Bob');
    });

    testWidgets('a PIN is asked first; Back stays at the picker and drops the launch', (tester) async {
      h = AppHarness();
      await h.setUp(tester);
      await addProfile(tester, 'Anna', pin: '4711');
      h.container.read(outsideLaunchProvider.notifier).state = const OutsideLaunch(romId: '1');
      await h.pumpApp(tester);
      expect(find.text('PIN for Anna'), findsOneWidget);
      await h.send(tester, GameAction.back);
      expect(find.text('Who is playing?'), findsOneWidget);
      expect(h.container.read(activeProfileProvider), isNull);
      expect(h.container.read(outsideLaunchProvider), isNull);
    });

    testWidgets('a profile that is not here: nothing opens, the launch is dropped', (tester) async {
      h = AppHarness();
      await h.setUp(tester);
      await addProfile(tester, 'Anna');
      await addProfile(tester, 'Bob', userId: 8);
      h.container.read(outsideLaunchProvider.notifier).state = const OutsideLaunch(romId: '1', profileId: 'gone');
      await h.pumpApp(tester);
      expect(h.container.read(activeProfileProvider), isNull);
      expect(h.container.read(outsideLaunchProvider), isNull);
    });
  });
}
