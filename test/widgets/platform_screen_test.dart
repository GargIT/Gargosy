import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/retroarch_core_list.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/emulators/bios_sync.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/providers/engine_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';
import 'package:gargosy/ui/screens/platform/platform_screen.dart';
import 'package:gargosy/ui/screens/settings/settings_screen.dart';
import 'package:gargosy/ui/widgets/game_card.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_library_api.dart';
import '../helpers/fake_secret_store.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

class _Bios implements BiosSync {
  final platforms = <String>[];

  @override
  Future<int> forPlatform(String slug) async {
    platforms.add(slug);
    return 1;
  }

  @override
  Future<int> forEmulator(String emulatorId) async => 0;

  @override
  Future<int> forAll(Set<String> installed) async => 0;
}

void main() {
  late AppRoot root;
  late StrategyRegistry registry;
  late _Bios bios;

  final ps2 = Platform.fromJson({
    'id': 1,
    'name': 'PlayStation 2',
    'slug': 'ps2',
    'display_name': 'PlayStation 2',
    'category': 'Console',
    'family_name': 'Sony',
    'generation': 6,
    'rom_count': 120,
    'fs_size_bytes': 3 * 1024 * 1024 * 1024,
    'firmware': [
      {'id': 1, 'file_name': 'SCPH-70012.bin', 'file_size_bytes': 4194304},
      {'id': 2, 'file_name': 'SCPH-10000.bin', 'file_size_bytes': 4194304},
    ],
  });
  final games = [for (var i = 1; i <= 120; i++) game(i, 'Game ${i.toString().padLeft(3, '0')}')];

  Future<void> pump(WidgetTester tester) async {
    await setDesktopSize(tester);
    root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    io.File(p.join(root.bios, 'scph-70012.bin')).writeAsBytesSync([1]);
    final dirs = ProfileLaunchDirectories(
      secrets: FakeSecretStore(),
      root: root,
      paths: ProfilePaths(root, 'aaa'),
      prefs: MemoryPrefs(),
    );
    registry = StrategyRegistry(dirs, MemoryPrefs());
    bios = _Bios();
    await tester.pumpWidget(
      testApp(
        PlatformScreen(platform: ps2),
        root: root,
        overrides: [
          libraryApiProvider.overrideWithValue(FakeLibraryApi(games)),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue([
            game(5, 'Ico'),
            game(6, 'Rez'),
            Game.fromJson({...gameJson(7, 'Halo'), 'platform_id': 9}),
          ]),
          biosSyncProvider.overrideWithValue(bios),
          strategyRegistryProvider.overrideWithValue(registry),
          emulatorsProvider.overrideWith(
            (ref) async => const [
              EmulatorInfo(
                id: 'retroarch',
                name: 'RetroArch',
                exe: 'retroarch.exe',
                supported: true,
                installedExe: r'C:\G\e\r.exe',
              ),
              EmulatorInfo(id: 'pcsx2', name: 'PCSX2', exe: 'pcsx2-qt.exe', supported: true),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  String? focusedCard() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GameCard>()?.game.name;

  testWidgets("the header: name, RomM's type, maker and generation, four numbers", (tester) async {
    await pump(tester);
    expect(find.text('PlayStation 2'), findsWidgets);
    for (final t in ['Console', 'Sony', 'Generation 6', '120', 'IN LIBRARY', 'ON THIS PC', '3.0 GB', 'FIRMWARE']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    final onPc = find.ancestor(of: find.text('ON THIS PC'), matching: find.byType(Column)).first;
    expect(find.descendant(of: onPc, matching: find.text('2')), findsOneWidget); // Halo is another platform's
    expect(focusedCard(), 'Game 001');
  });

  testWidgets('Random opens one of the platform\'s games', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('platform-random')));
    await tester.pumpAndSettle();
    expect(tester.widget<GameScreen>(find.byType(GameScreen)).game.platformId, 1);
  });

  testWidgets('Firmware / BIOS marks what bios\\ has; Get missing asks for the platform', (tester) async {
    await pump(tester);
    await press(tester, GameAction.r1);
    expect(find.textContaining('1 of 2'), findsOneWidget);
    expect(find.text('On this PC'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    await tester.tap(find.text('Get missing from RomM'));
    await tester.pumpAndSettle();
    expect(bios.platforms, ['ps2']);
    expect(find.text('Got 1 from RomM.'), findsOneWidget);
  });

  testWidgets('Emulator: the installed emulator, its core, and a way to install the other', (tester) async {
    await pump(tester);
    await press(tester, GameAction.r1);
    await press(tester, GameAction.r1);
    expect(find.text('PLAYSTATION 2 PLAYS IN'), findsOneWidget);
    expect(find.text('RetroArch'), findsWidgets);
    final cores = getCoresForSlug('ps2');
    expect(cores.length, greaterThan(1));
    await tester.tap(find.byKey(const ValueKey('platform-core')));
    await tester.pumpAndSettle();
    final other = cores.firstWhere((c) => c.id != getDefaultCoreForSlug('ps2'));
    await tester.tap(find.text(other.displayName).last);
    await tester.pumpAndSettle();
    expect(registry.getCoreOverride('ps2'), other.id);
    expect(find.text('Core: ${other.displayName}'), findsOneWidget);
    await tester.tap(find.text('Install under Emulators'));
    await tester.pumpAndSettle();
    expect(tester.widget<SettingsScreen>(find.byType(SettingsScreen)).initial, SettingsPage.emulators);
  });

  testWidgets('LB/RB switch tabs, and each tab gets its focus back', (tester) async {
    await pump(tester);
    await press(tester, GameAction.right);
    expect(focusedCard(), 'Game 002');
    await press(tester, GameAction.r1);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GameCard>(), isNull);
    await press(tester, GameAction.down); // into the file list
    final inFirmware = FocusManager.instance.primaryFocus;
    await press(tester, GameAction.l1);
    expect(focusedCard(), 'Game 002');
    await press(tester, GameAction.r1);
    expect(FocusManager.instance.primaryFocus, inFirmware);
  });

  testWidgets('scrolling the games hides the header; the name moves into the tab row', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('platform-pinned-name')), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('IN LIBRARY'), findsNothing);
    expect(find.byKey(const ValueKey('platform-pinned-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-field')), findsOneWidget); // the bar stays
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 5000));
    await tester.pumpAndSettle();
    expect(find.text('IN LIBRARY'), findsOneWidget);
  });

  testWidgets('with the D-pad: the header comes back once focus leaves the games, so Random is reached', (
    tester,
  ) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await press(tester, GameAction.down);
    }
    expect(find.text('IN LIBRARY'), findsNothing);
    for (var i = 0; i < 10 && find.byKey(const ValueKey('platform-random')).evaluate().isEmpty; i++) {
      await press(tester, GameAction.up);
    }
    for (var i = 0; i < 6; i++) {
      await press(tester, GameAction.up);
    }
    final random = find.byKey(const ValueKey('platform-random'));
    expect(random, findsOneWidget);
    expect(
      Focus.of(tester.element(find.descendant(of: random, matching: find.byType(Container)).first)).hasFocus,
      isTrue,
    );
    // And back down: tabs, bar, the covers.
    for (var i = 0; i < 6 && focusedCard() == null; i++) {
      await press(tester, GameAction.down);
    }
    expect(focusedCard(), isNotNull);
  });
}
