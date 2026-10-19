import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_auth_client.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/shell/app_shell.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_romm_auth.dart';

void main() {
  late AppHarness h;

  Future<void> typeOnScreen(WidgetTester tester, String text) async {
    for (final ch in text.split('')) {
      await tester.sendKeyEvent(
        LogicalKeyboardKey.findKeyByKeyId(ch.codeUnitAt(0)) ?? LogicalKeyboardKey.keyA,
        character: ch,
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  Future<void> openAdd(WidgetTester tester) async {
    await h.pumpApp(tester);
    await tester.tap(find.text('Add profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-url')));
    await tester.pumpAndSettle();
    await typeOnScreen(tester, 'romm.example');
    await tester.tap(find.text('Continue'));
    // Two rounds (0.4 s of fake time): the pairing poll (1 s) must not run yet.
    await h.settle(tester, rounds: 2);
  }

  testWidgets('device pairing: QR and code, then name, colour, no PIN, and the shell', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(
      start: const DeviceAuthStart(
        deviceCode: 'dc',
        userCode: 'WXYZ-9876',
        verificationUrl: 'https://romm.example/pair/device?user_code=WXYZ-9876',
        expiresIn: 600,
        interval: 1,
      ),
      polls: [
        const DevicePending(),
        const DeviceApproved(token: 'rmm_dev', deviceId: 'd1'),
      ],
      me: const RommUser(id: 7, username: 'anna', avatarPath: '', oauthScopes: []),
    );
    await openAdd(tester);
    expect(find.text('WXYZ-9876'), findsOneWidget);
    expect(find.byKey(const Key('pair-qr')), findsOneWidget);
    await h.settle(tester);
    expect(find.text('anna'), findsWidgets); // name field prefilled
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No PIN'));
    await h.settle(tester, until: find.byType(AppShell));
    expect(find.byType(AppShell), findsOneWidget);
    final ctx = h.container.read(activeProfileProvider)!;
    expect(ctx.profile.rommUserId, 7);
    expect(ctx.profile.serverUrl, 'https://romm.example');
    final login = await tester.runAsync(() => loginStoreForWidgetless(h, ctx.profile).read());
    expect(login!.token, 'rmm_dev');
    expect(login.kind, 'device');
  });

  testWidgets('a server without device pairing goes straight to the password; the password is not kept', (
    tester,
  ) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(
      start: null,
      passwordToken: 'rmm_pw',
      me: const RommUser(id: 9, username: 'anna', avatarPath: '', oauthScopes: []),
    );
    await openAdd(tester);
    await tester.tap(find.byKey(const Key('login-username')));
    await tester.pumpAndSettle();
    await typeOnScreen(tester, 'anna');
    await tester.tap(find.byKey(const Key('login-password')));
    await tester.pumpAndSettle();
    await typeOnScreen(tester, 'hunter22');
    expect(find.text('hunter22'), findsNothing);
    await tester.tap(find.text('Log in'));
    await h.settle(tester);
    expect(h.auth.passwordLogins, ['anna']);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No PIN'));
    await h.settle(tester, until: find.byType(AppShell)); // however slow the runner's file IO
    final ctx = h.container.read(activeProfileProvider)!;
    final files = io.Directory(ProfilePaths(h.root, ctx.profile.id).dir).listSync(recursive: true).whereType<io.File>();
    for (final f in files) {
      expect(latin1.decode(f.readAsBytesSync()), isNot(contains('hunter22')), reason: f.path);
    }
  });

  testWidgets('server step shows the error and stays', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(startError: const RommAuthException(RommAuthFailure.network, 'offline'));
    await openAdd(tester);
    expect(find.textContaining("Can't reach"), findsOneWidget);
    expect(find.byKey(const Key('server-url')), findsOneWidget);
  });

  testWidgets('a wrong password shows the error and keeps the step', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(
      start: null,
      passwordError: const RommAuthException(RommAuthFailure.badCredentials, 'Wrong username or password'),
    );
    await openAdd(tester);
    await tester.tap(find.text('Log in'));
    await h.settle(tester);
    expect(find.text('Wrong username or password'), findsOneWidget);
  });

  testWidgets('setting a PIN asks twice and saves it', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(
      start: null,
      me: const RommUser(id: 7, username: 'anna', avatarPath: '', oauthScopes: []),
    );
    await openAdd(tester);
    await tester.tap(find.text('Log in'));
    await h.settle(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set a PIN'));
    await tester.pumpAndSettle();
    for (var round = 0; round < 2; round++) {
      for (final k in [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit0,
      ]) {
        await tester.sendKeyEvent(k);
      }
      await h.settle(tester);
    }
    await h.settle(tester);
    final ctx = h.container.read(activeProfileProvider)!;
    expect(ctx.profile.pin!.verify('2580'), isTrue);
  });

  testWidgets('when pairing fails to start (not a network problem) the password form is offered, with the error', (
    tester,
  ) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(startError: const RommAuthException(RommAuthFailure.other, 'RomM answered 403'));
    await openAdd(tester);
    await h.settle(tester);
    expect(find.text('RomM answered 403'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('an address that is not a RomM server goes back to the server step with the reason', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(
      startError: const RommAuthException(RommAuthFailure.notRomm, 'This does not look like a RomM server'),
    );
    await openAdd(tester);
    await h.settle(tester);
    expect(find.textContaining('does not look like a RomM server'), findsOneWidget);
    expect(find.byKey(const Key('server-url')), findsOneWidget);
  });

  testWidgets('if creating the profile fails, the error shows, nothing half-made is left, and trying again works', (
    tester,
  ) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(
      start: null,
      me: const RommUser(id: 7, username: 'anna', avatarPath: '', oauthScopes: []),
    );
    await openAdd(tester);
    await tester.tap(find.text('Log in'));
    await h.settle(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    h.protector.failProtect = true;
    await tester.tap(find.text('No PIN'));
    // Creating the profile is file IO; a slow runner needs more rounds.
    await h.settle(tester, until: find.textContaining('could not be saved'));
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(h.container.read(activeProfileProvider), isNull);
    expect(io.Directory(h.root.profiles).listSync(), isEmpty);
    h.protector.failProtect = false;
    await tester.tap(find.text('No PIN'));
    await h.settle(tester, until: find.byType(AppShell));
    expect(find.byType(AppShell), findsOneWidget);
    expect(io.Directory(h.root.profiles).listSync(), hasLength(1));
  });

  testWidgets('after logging in, Cancel (confirmed) drops the login and adds no profile', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    h.auth = FakeRommAuth(
      start: null,
      me: const RommUser(id: 7, username: 'anna', avatarPath: '', oauthScopes: []),
    );
    await openAdd(tester);
    await tester.tap(find.text('Log in'));
    await h.settle(tester);
    expect(find.text('Your profile'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stop adding this profile?'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await h.settle(tester);
    expect(find.text('Who is playing?'), findsOneWidget);
    expect(io.Directory(h.root.profiles).listSync(), isEmpty);
  });
}
