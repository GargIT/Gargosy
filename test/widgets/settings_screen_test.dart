import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:gargosy/core/romm/romm_auth_client.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/core/save/state_sync_service.dart';
import 'package:gargosy/emulators/bios_sync.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/play/quit_combo.dart';
import 'package:gargosy/ui/screens/settings/storage_section.dart';
import 'package:gargosy/ui/shell/screensaver.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/pc_identity.dart';
import 'package:gargosy/profiles/pin.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/engine_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/retroachievements/ra_account.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/settings/settings_screen.dart';
import 'package:gargosy/ui/screens/settings/settings_rows.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
import 'package:gargosy/ui/widgets/cover_image.dart';
import 'package:gargosy/ui/widgets/g_focusable.dart';

import '../helpers/fake_protector.dart';
import '../helpers/fake_romm_auth.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

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

  Future<void> pump(
    WidgetTester tester, {
    PinHash? pin,
    UploadQueue? queue,
    BiosSync? bios,
    SettingsPage initial = SettingsPage.profile,
    FakeRommAuth? auth,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = await tester.runAsync(tempAppRoot);
    addTearDown(() => io.Directory(root!.root).deleteSync(recursive: true));
    c = ProviderContainer(
      overrides: [
        appRootProvider.overrideWithValue(root!),
        appPreferencesProvider.overrideWithValue(MemoryPrefs()),
        coverImageBuilderProvider.overrideWithValue((url) => const ColoredBox(color: Colors.grey)),
        rommHeartbeatEnabledProvider.overrideWithValue(false),
        uploadQueueProvider.overrideWith((ref) async => queue),
        biosSyncProvider.overrideWithValue(bios),
        dataProtectorProvider.overrideWithValue(FakeProtector()),
        pcIdentityProvider.overrideWithValue(const PcIdentity(machineName: 'TEST', userName: 'u', machineId: 'm')),
        rommAuthFactoryProvider.overrideWithValue((url, trust) => auth ?? FakeRommAuth()),
        platformsProvider.overrideWith((ref) async => [Platform(id: 1, name: 'PlayStation', slug: 'psx')]),
        emulatorsProvider.overrideWith(
          (ref) async => const [
            EmulatorInfo(
              id: 'duckstation',
              name: 'DuckStation',
              exe: 'duckstation-qt-x64-ReleaseLTCG.exe',
              supported: true,
              installedExe: r'C:\G\e\d.exe',
            ),
            EmulatorInfo(
              id: 'retroarch',
              name: 'RetroArch',
              exe: 'retroarch.exe',
              supported: true,
              installedExe: r'C:\G\e\r.exe',
            ),
            EmulatorInfo(
              id: 'melonds',
              name: 'melonDS',
              exe: 'melonDS.exe',
              supported: true,
              installedExe: r'C:\G\e\m.exe',
            ),
            EmulatorInfo(id: 'cemu', name: 'Cemu', exe: 'Cemu.exe', supported: true, installedExe: r'C:\G\e\c.exe'),
          ],
        ),
      ],
    );
    addTearDown(c.dispose);
    final anna = await tester.runAsync(
      () => c
          .read(profileStoreProvider)
          .create(name: 'Anna', colorIndex: 1, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna', pin: pin),
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
          home: SettingsScreen(initial: initial),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Profile → RomM account → Sign in again: the same RomM user, the new login used from then on', (
    tester,
  ) async {
    await pump(
      tester,
      auth: FakeRommAuth(
        start: const DeviceAuthStart(
          deviceCode: 'dc',
          userCode: 'CODE-1',
          verificationUrl: 'https://r/pair/device?user_code=CODE-1',
          expiresIn: 600,
          interval: 1,
        ),
        polls: [const DeviceApproved(token: 'new', deviceId: 'd')],
      ),
    );
    expect(find.text('Sign in again'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('romm-account')));
    for (var i = 0; i < 60 && c.read(activeProfileProvider)!.login.token != 'new'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(c.read(activeProfileProvider)!.login.token, 'new');
    final saved = await tester.runAsync(() => loginStoreForWidgetless(c).read());
    expect(saved!.token, 'new');
    expect(find.byType(SettingsScreen), findsOneWidget, reason: 'back on Settings');
    expect(find.text('Signed in again as anna.'), findsOneWidget);
  });

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

  testWidgets('the sidebar groups the sections; the headings never take focus', (tester) async {
    await pump(tester);
    for (final h in ['PROFILE', 'LIBRARY', 'THIS PC', 'GARGOSY']) {
      final heading = find.descendant(of: find.byKey(const Key('settings-sidebar')), matching: find.text(h));
      expect(heading, findsOneWidget, reason: h);
      expect(
        find.ancestor(of: heading, matching: find.byType(GFocusable)),
        findsNothing,
        reason: h,
      );
    }
    expect(find.text('Settings'), findsNothing, reason: 'the big title is gone');
    // Down through the sidebar lands on each item in turn, never a heading.
    final seen = <SettingsPage>[];
    for (var i = 0; i < SettingsPage.values.length; i++) {
      for (final page in SettingsPage.values) {
        final item = find.byKey(ValueKey('settings-${page.name}'));
        if (Focus.of(tester.element(find.descendant(of: item, matching: find.byType(Container)).first))
            .hasPrimaryFocus) {
          seen.add(page);
        }
      }
      await press(tester, GameAction.down);
    }
    expect(seen, SettingsPage.values);
  });

  testWidgets('initial opens that section with its item focused', (tester) async {
    await pump(tester, initial: SettingsPage.controller);
    expect(find.textContaining('Stick deadzone'), findsOneWidget);
    final item = find.byKey(const ValueKey('settings-controller'));
    expect(
      Focus.of(tester.element(find.descendant(of: item, matching: find.byType(Container)).first)).hasPrimaryFocus,
      isTrue,
    );
  });

  testWidgets('LB/RB walk the sections in order and stop at the ends', (tester) async {
    await pump(tester);
    await press(tester, GameAction.l1);
    expect(find.text('Rename'), findsOneWidget, reason: 'still Profile');
    await press(tester, GameAction.r1);
    expect(find.text('Connect'), findsOneWidget, reason: 'RetroAchievements');
    await press(tester, GameAction.r1);
    expect(find.text('ROWS, IN ORDER'), findsOneWidget, reason: 'Home');
    await press(tester, GameAction.r1);
    expect(find.text('Get BIOS files from RomM'), findsOneWidget, reason: 'Emulators');
    await press(tester, GameAction.r1);
    expect(find.text('WHICH EMULATOR PLAYS'), findsOneWidget, reason: 'Emulator settings');
    await press(tester, GameAction.r1);
    expect(find.textContaining('Stick deadzone'), findsOneWidget, reason: 'Controller');
    await press(tester, GameAction.r1);
    expect(find.text('Fullscreen (F11)'), findsOneWidget, reason: 'Display');
    await press(tester, GameAction.r1);
    expect(find.text('Empty Temp'), findsOneWidget, reason: 'Storage');
    await press(tester, GameAction.r1);
    expect(find.text('ABOUT'), findsOneWidget, reason: 'About');
    await press(tester, GameAction.r1);
    expect(find.text('ABOUT'), findsOneWidget, reason: 'the last one');
  });

  testWidgets('Controller: Select + LB + RB quits a game by default; another pick, or off, is kept', (tester) async {
    await pump(tester, initial: SettingsPage.controller);
    expect(c.read(quitButtonsProvider), QuitButtons.selectBumpers);
    expect(find.text('Select + LB + RB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quit-buttons')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select + Start').last);
    await tester.pumpAndSettle();
    expect(c.read(quitButtonsProvider), QuitButtons.selectStart);
    await tester.tap(find.byKey(const ValueKey('quit-buttons')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(c.read(quitButtonsProvider), isNull);
    expect(c.read(appPreferencesProvider).getString(QuitButtons.prefKey), QuitButtons.off);
  });

  testWidgets('Storage (#145): the drive, the folders, the ROMs by platform, and the image cache', (tester) async {
    await pump(tester, initial: SettingsPage.storage);
    final roms = io.Directory(p.join(c.read(appRootProvider).roms, 'psx'))..createSync(recursive: true);
    io.File(p.join(roms.path, 'Crash.chd')).writeAsBytesSync(List<int>.filled(2048, 1));
    c.invalidate(storageUsageProvider);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('ROMs'), findsOneWidget);
    expect(find.text('Temp'), findsOneWidget);
    expect(find.byKey(const ValueKey('storage-platform-psx')), findsOneWidget);
    expect(find.text('2.0 KB · 1 game'), findsOneWidget);
    expect(find.text('PlayStation'), findsWidgets, reason: "the platform's name, not its folder");
    await tester.scrollUntilVisible(find.text('Change'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('10 000 images (about 1.1 GB)'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25 000 images (about 2.9 GB)'));
    await tester.pumpAndSettle();
    expect(find.text('25 000 images (about 2.9 GB)'), findsOneWidget);
    expect(find.text('Clear the cache'), findsOneWidget);
  });

  testWidgets('Display: the screensaver after 5 minutes by default, changed from a list (#147)', (tester) async {
    await pump(tester, initial: SettingsPage.display);
    expect(find.text('After 5 minutes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('screensaver')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(c.read(screensaverMinutesProvider), 0);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('Rename goes through the Name field', (tester) async {
    await pump(tester);
    expect(find.textContaining('Profile created'), findsOneWidget);
    expect(find.textContaining('anna on r'), findsWidgets);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Profile name'), findsOneWidget);
  });

  testWidgets('RetroAchievements shows "Connected as" only when connected', (tester) async {
    await pump(tester, initial: SettingsPage.retroAchievements);
    expect(find.textContaining('Connected as'), findsNothing);
    expect(find.text('Connect'), findsOneWidget);
    await tester.runAsync(() => c.read(profilePrefsProvider)!.setString(kRaUsernameKey, 'GargIT'));
    c.invalidate(raAccountProvider);
    await tester.pumpAndSettle();
    expect(find.text('Connected as @GargIT'), findsOneWidget);
    expect(find.text('Hardcore mode'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
  });

  testWidgets("a platform's emulator is chosen for this profile", (tester) async {
    await pump(tester, initial: SettingsPage.emulatorSettings);
    expect(find.text('PlayStation'), findsOneWidget);
    await tester.tap(find.text('PlayStation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DuckStation').last);
    await tester.pumpAndSettle();
    // The choice is kept once the profile's prefs file is written with real IO; give a slow machine time.
    final registry = c.read(strategyRegistryProvider)!;
    for (var i = 0; i < 100 && registry.getPreferredEmulatorId('psx') == null; i++) {
      await settleIo(tester);
    }
    expect(registry.getPreferredEmulatorId('psx'), 'duckstation');
    // The field shows the choice once its provider has read it back; give a slow machine time.
    final shown = find.descendant(
      of: find.byKey(const ValueKey('emulator-for-psx')),
      matching: find.text('DuckStation'),
    );
    for (var i = 0; i < 100 && shown.evaluate().isEmpty; i++) {
      await settleIo(tester);
    }
    expect(shown, findsOneWidget);
  });

  testWidgets('one switch syncs save states for this profile; the note names who syncs', (tester) async {
    await pump(tester, initial: SettingsPage.emulatorSettings);
    expect(find.byKey(const ValueKey('state-sync')), findsOneWidget);
    // The old per-emulator toggles are gone.
    for (final id in ['duckstation', 'pcsx2', 'retroarch']) {
      expect(find.byKey(ValueKey('state-sync-$id')), findsNothing, reason: id);
    }
    // DuckStation, RetroArch and melonDS sync states (melonDS without Resume); Cemu doesn't; PCSX2 isn't installed.
    final synced = find.byKey(const ValueKey('state-sync-synced'));
    for (final name in ['DuckStation', 'RetroArch', 'melonDS']) {
      expect(
        find.descendant(of: synced, matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }
    final local = find.byKey(const ValueKey('state-sync-local'));
    expect(find.descendant(of: local, matching: find.text('Cemu')), findsOneWidget);
    expect(find.descendant(of: local, matching: find.text('DuckStation')), findsNothing);
    // The names are chips side by side, each as wide as its name, not one line each across the card.
    Rect chip(String name) => tester.getRect(
      find.ancestor(
        of: find.descendant(of: synced, matching: find.text(name)),
        matching: find.byType(SettingsBadge),
      ),
    );
    expect(chip('DuckStation').width, lessThan(200));
    expect(chip('RetroArch').top, chip('DuckStation').top);
    // melonDS syncs but can't start in a state: the list says where to load one.
    expect(find.text("melonDS: start the game, then load the state from the emulator's own menu."), findsOneWidget);
    // On by default (0.2.0); A turns it off for this profile.
    expect(StateSyncService.isOn(c.read(profilePrefsProvider)!), isTrue);
    await tester.tap(find.byKey(const ValueKey('state-sync')));
    await tester.pumpAndSettle();
    expect(c.read(profilePrefsProvider)!.getBool(StateSyncService.enabledKey), isFalse);
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
    expect(bios.calls, ['all cemu,duckstation,melonds,retroarch']);
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
  Future<int> forPlatform(String slug) async {
    calls.add('platform $slug');
    return found;
  }

  @override
  Future<int> forAll(Set<String> installed) async {
    calls.add('all ${(installed.toList()..sort()).join(',')}');
    return found;
  }
}

ProfileLoginStore loginStoreForWidgetless(ProviderContainer c) {
  final p = c.read(activeProfileProvider)!;
  return ProfileLoginStore(
    profileDir: p.paths.dir,
    protector: c.read(dataProtectorProvider),
    pc: c.read(pcIdentityProvider),
  );
}
