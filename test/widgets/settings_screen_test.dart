import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/core/save/state_sync_service.dart';
import 'package:gargosy/emulators/bios_sync.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/pin.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/engine_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/settings/settings_screen.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
import 'package:gargosy/ui/widgets/cover_image.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

/// Lets file writes started from a tap finish: real IO and the test's
/// clock take turns, one round per async step.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

void main() {
  late ProviderContainer c;

  Future<void> pump(WidgetTester tester, {PinHash? pin, UploadQueue? queue, BiosSync? bios}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = await tester.runAsync(tempAppRoot);
    addTearDown(() => io.Directory(root!.root).deleteSync(recursive: true));
    c = ProviderContainer(overrides: [
      appRootProvider.overrideWithValue(root!),
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
      coverImageBuilderProvider.overrideWithValue((url) => const ColoredBox(color: Colors.grey)),
      rommHeartbeatEnabledProvider.overrideWithValue(false),
      uploadQueueProvider.overrideWith((ref) async => queue),
      biosSyncProvider.overrideWithValue(bios),
      platformsProvider.overrideWith((ref) async => [Platform(id: 1, name: 'PlayStation', slug: 'psx')]),
      emulatorsProvider.overrideWith((ref) async => const [
            EmulatorInfo(id: 'duckstation', name: 'DuckStation', exe: 'duckstation-qt-x64-ReleaseLTCG.exe', supported: true, installedExe: r'C:\G\e\d.exe'),
            EmulatorInfo(id: 'retroarch', name: 'RetroArch', exe: 'retroarch.exe', supported: true, installedExe: r'C:\G\e\r.exe'),
          ]),
    ]);
    addTearDown(c.dispose);
    final anna = await tester.runAsync(() => c.read(profileStoreProvider).create(
        name: 'Anna', colorIndex: 1, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna', pin: pin));
    await tester.runAsync(() => c.read(activeProfileProvider.notifier).activate(anna!, const ProfileLogin(token: 't', kind: 'device')));
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: nav,
        theme: gargosyTheme(),
        builder: (context, child) => InputRouter(navigatorKey: nav, startGamepads: false, child: child!),
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the sections; each opens its settings', (tester) async {
    await pump(tester);
    for (final s in ['Profile', 'Controller', 'Display', 'Emulators', 'RetroAchievements']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    await tester.tap(find.text('Controller'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stick deadzone'), findsOneWidget);
    await tester.tap(find.text('RetroAchievements'));
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets("a platform's emulator is chosen for this profile", (tester) async {
    await pump(tester);
    await tester.tap(find.text('Emulators'));
    await tester.pumpAndSettle();
    expect(find.text('PlayStation'), findsOneWidget);
    await tester.tap(find.text('PlayStation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DuckStation').last);
    await tester.pumpAndSettle();
    await settleIo(tester); // the profile's prefs file is written with real IO
    expect(c.read(strategyRegistryProvider)!.getPreferredEmulatorId('psx'), 'duckstation');
    expect(find.text('DuckStation'), findsWidgets);
  });

  testWidgets('save-state sync is switched on per emulator, for this profile', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Emulators'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('state-sync-duckstation')));
    await tester.pumpAndSettle();
    expect(c.read(profilePrefsProvider)!.getBool(StateSyncService.enabledKey('duckstation')), isTrue);
  });

  testWidgets('deleting the profile names the saves still waiting to upload', (tester) async {
    final queue = UploadQueue(
      isOffline: () => false,
      pending: () => [(romId: '5', entry: BackupEntry(timestamp: DateTime(2026), md5Hash: 'h', localZipPath: 'z'))],
      markSynced: (_, _) async {},
      gameById: (id) async => game(5, 'Okami'),
      romPathFor: (_) async => null,
      push: (_, _, _) async => false,
    );
    await pump(tester, queue: queue);
    await tester.tap(find.text('Delete profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining("1 save hasn't reached RomM"), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(c.read(activeProfileProvider), isNotNull);
  });

  testWidgets('changing the PIN asks for the current one first', (tester) async {
    final pin = (await tester.runAsync(() async => PinHash.create('1234', iterations: 10)))!;
    await pump(tester, pin: pin);
    await tester.tap(find.text('Change PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Current PIN'), findsOneWidget);
  });

  testWidgets('deleting the profile is refused while a game runs', (tester) async {
    await pump(tester);
    c.read(playControllerProvider.notifier).state = const PlayState(runningGameId: '1');
    await tester.tap(find.text('Delete profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Close the game first'), findsOneWidget);
    expect(find.textContaining('Delete Anna?'), findsNothing);
  });

  testWidgets('Emulators: BIOS files come from RomM for every installed emulator', (tester) async {
    final bios = _FakeBios(found: 3);
    await pump(tester, bios: bios);
    await tester.tap(find.text('Emulators'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get BIOS files from RomM'));
    await tester.pumpAndSettle();
    expect(bios.calls, ['all duckstation,retroarch']);
    expect(find.textContaining('Got 3 BIOS files from RomM'), findsOneWidget);
  });
}

class _FakeBios implements BiosSync {
  _FakeBios({this.found = 0});
  final int found;
  final calls = <String>[];

  @override
  Future<int> forEmulator(String emulatorId) async {
    calls.add('one $emulatorId');
    return found;
  }

  @override
  Future<int> forAll(Set<String> installed) async {
    calls.add('all ${(installed.toList()..sort()).join(',')}');
    return found;
  }
}
