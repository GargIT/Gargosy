import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/providers/update_providers.dart';
import 'package:gargosy/app.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/pc_identity.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_providers.dart';

import 'fake_protector.dart';
import 'fake_romm_auth.dart';
import 'profile_test_env.dart';

/// The login store [GargosyApp] uses for [p], for checks from a test.
ProfileLoginStore loginStoreForWidgetless(AppHarness h, Profile p) => ProfileLoginStore(
      profileDir: ProfilePaths(h.root, p.id).dir,
      protector: h.protector,
      pc: h.container.read(pcIdentityProvider),
    );

class AppHarness {
  late AppRoot root;
  late ProviderContainer container;
  final protector = FakeProtector();
  FakeRommAuth auth = FakeRommAuth();
  final prefs = MemoryPrefs();

  Future<void> setUp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    container = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root),
      appPreferencesProvider.overrideWithValue(prefs),
      dataProtectorProvider.overrideWithValue(protector),
      pcIdentityProvider.overrideWithValue(const PcIdentity(machineName: 'TEST', userName: 'u', machineId: 'm')),
      rommAuthFactoryProvider.overrideWithValue((url, trust) => auth),
      // No timers and no upload queue in app tests.
      rommHeartbeatEnabledProvider.overrideWithValue(false),
      // Never GitHub from app tests.
      updateAutoCheckEnabledProvider.overrideWithValue(false),
      uploadQueueProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const GargosyApp(startGamepads: false)));
    await settle(tester);
  }

  Future<void> send(WidgetTester tester, GameAction a) async {
    inputActionBus.add(a);
    await settle(tester);
  }

  /// Lets everything the app started finish. File IO and the PIN isolate need
  /// the real event loop ([WidgetTester.runAsync]); their continuations, and
  /// timers such as the device-pairing poll, need the fake clock
  /// ([WidgetTester.pump]). Each round gives both; one sequential async step
  /// takes one round, and creating a profile is about forty. With [until], it
  /// keeps going (up to 1000 rounds) until that finds something: a slow
  /// machine's file IO can need more rounds than [rounds].
  Future<void> settle(WidgetTester tester, {int rounds = 100, Finder? until}) async {
    for (var i = 0; i < (until == null ? rounds : 1000); i++) {
      if (until != null && i >= rounds && until.evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
  }

}
