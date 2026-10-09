import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/retroarch_core_list.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/catalog/save_catalog.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/play/play_menu.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/screens/play/play_screen.dart';
import 'package:gargosy/ui/theme/tokens.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';
import '../unit/play_controller_test.dart' show FakeEngine;

const _pcsx2 = SaveMaker('pcsx2');
const _ra = SaveMaker('retroarch', coreId: 'pcsx2');
const _cores = [
  RetroArchCore(id: 'pcsx2_libretro', displayName: 'LRPS2', platforms: ['ps2'], category: CoreCategory.sony),
  RetroArchCore(id: 'play_libretro', displayName: 'Play!', platforms: ['ps2'], category: CoreCategory.sony),
];

DateTime _day(int daysAgo, int h) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h).subtract(Duration(days: daysAgo));
}

SaveEntry _local(DateTime t, {String? onRomm}) => SaveEntry(
  source: SaveSource.local,
  fileName: 'Mcd001.ps2',
  savedAt: t,
  maker: _pcsx2,
  tag: 'pcsx2',
  sameAsRommId: onRomm,
);
SaveEntry _romm(String name, DateTime t, {int id = 9}) => SaveEntry(
  source: SaveSource.romm,
  fileName: name,
  savedAt: t,
  maker: _pcsx2,
  tag: 'pcsx2',
  slot: name,
  rommSave: {'id': id},
);
RommSaveGroup _g(SaveEntry e) => RommSaveGroup(slot: e.slot!, tag: e.tag!, newest: e, older: const []);

/// Where the game page puts its cover (the page's padding).
const gamePageCoverOffset = Offset(GSpace.rowPad, GLayout.navHeight + GSpace.s4);

void main() {
  late AppRoot root;
  late FakeEngine engine;
  final burnout = Game.fromJson(gameJson(7564, 'Burnout 3: Takedown', fsName: 'Burnout 3 (USA).chd'));

  Future<void> open(
    WidgetTester tester, {
    SaveCatalog? catalog,
    List<EmulatorOption>? emulators,
    List<ResumeEntry> states = const [],
    double width = 1920,
    SaveMaker? remembered,
  }) async {
    tester.view.physicalSize = Size(width, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    root = (await tester.runAsync(tempAppRoot))!;
    final mine = root.root;
    addTearDown(() => io.Directory(mine).deleteSync(recursive: true));
    engine = FakeEngine()
      ..menu = PlayMenu(
        emulators:
            emulators ?? const [EmulatorOption(_pcsx2, 'PCSX2'), EmulatorOption(_ra, 'RetroArch', cores: _cores)],
        platformDefault: (emulators ?? const [EmulatorOption(_pcsx2, '')]).firstOrNull?.maker,
        remembered: remembered,
        catalog: catalog ?? const SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false),
      )
      ..states = states;
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayScreen(game: burnout))),
              child: const Text('open'),
            ),
          ),
        ),
        root: root,
        overrides: [
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          playEngineProvider.overrideWithValue(engine),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder inPanel(String text) =>
      find.descendant(of: find.byKey(const ValueKey('play-settings')), matching: find.text(text));

  testWidgets('lists This PC and On RomM, with the newest chosen and the emulator in the panel', (tester) async {
    await open(
      tester,
      catalog: SaveCatalog(
        thisPc: [_local(_day(2, 9))],
        backups: const [],
        romm: [_g(_romm('burnout.ps2', _day(0, 21)))],
        rommOffline: false,
      ),
    );
    expect(find.text('This PC'), findsOneWidget);
    expect(find.text('On RomM'), findsOneWidget);
    expect(inPanel('PCSX2'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('save-row-chosen')), matching: find.text('burnout.ps2')),
      findsOneWidget,
    );
  });

  testWidgets('the line under the button says what A does', (tester) async {
    await open(
      tester,
      catalog: SaveCatalog(
        thisPc: const [],
        backups: const [],
        romm: [_g(_romm('burnout.ps2', _day(0, 21)))],
        rommOffline: false,
      ),
    );
    expect(find.text('in PCSX2 · RomM save, today 21:00'), findsOneWidget);
  });

  testWidgets('Start plays the chosen save in the chosen emulator', (tester) async {
    await open(
      tester,
      catalog: SaveCatalog(
        thisPc: [_local(_day(2, 9), onRomm: '1')],
        backups: const [],
        romm: [_g(_romm('burnout.ps2', _day(0, 21)))],
        rommOffline: false,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(engine.steps, ['states', 'prepare', 'launch']);
    expect(engine.request!.emulator, _pcsx2);
    expect(engine.request!.save?.fileName, 'burnout.ps2');
    expect(find.byType(PlayScreen), findsNothing, reason: 'the play screen closes once the game started');
  });

  testWidgets('an older save asks first, and No keeps the screen open', (tester) async {
    await open(
      tester,
      catalog: SaveCatalog(
        thisPc: [_local(_day(0, 21), onRomm: '1')],
        backups: const [],
        romm: [_g(_romm('old.ps2', _day(5, 9)))],
        rommOffline: false,
      ),
    );
    await tester.tap(find.text('old.ps2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(find.text('Play an older save?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(engine.steps, isEmpty);
    expect(find.byType(PlayScreen), findsOneWidget);
  });

  testWidgets('Y opens the emulator picker; the choice plays', (tester) async {
    await open(tester);
    await press(tester, GameAction.favorite);
    await tester.tap(find.text('RetroArch').last);
    await tester.pumpAndSettle();
    expect(inPanel('RetroArch'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(engine.request!.emulator.emulatorId, 'retroarch');
  });

  testWidgets('the core picker is for RetroArch only; a chosen core is played and remembered', (tester) async {
    await open(tester);
    expect(inPanel('Core: RetroArch only'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-emulator')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RetroArch').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-core')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play!').last);
    await tester.pumpAndSettle();
    expect(inPanel('Core: Play!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-always')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(engine.request!.emulator, const SaveMaker('retroarch', coreId: 'play'));
    expect(engine.request!.remember, isTrue);
  });

  testWidgets('with no emulator installed it says so', (tester) async {
    await open(tester, emulators: const []);
    expect(find.textContaining('No emulator for PlayStation 2 is installed'), findsOneWidget);
  });

  testWidgets('a newer state is chosen, the button reads Resume, and Start resumes it', (tester) async {
    await open(
      tester,
      catalog: SaveCatalog(
        thisPc: [_local(_day(0, 9), onRomm: '1')],
        backups: const [],
        romm: const [],
        rommOffline: false,
      ),
      states: [
        ResumeEntry(
          emulatorId: 'pcsx2',
          emulatorName: 'PCSX2',
          fileName: 'slot1.p2s',
          slot: const NumberedStateSlot(1),
          savedAt: _day(0, 21),
          where: ResumeWhere.thisPc,
        ),
      ],
    );
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Slot 1'), findsOneWidget, reason: "the chosen state's tab is shown");
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(engine.steps, ['states', 'check', 'prepare', 'launch']);
    expect(engine.loadStatePath, isNotNull);
  });

  testWidgets('LB/RB switch Saves and States', (tester) async {
    await open(
      tester,
      states: [
        ResumeEntry(
          emulatorId: 'pcsx2',
          emulatorName: 'PCSX2',
          fileName: 's.p2s',
          slot: const NumberedStateSlot(2),
          savedAt: _day(3, 9),
          where: ResumeWhere.thisPc,
        ),
      ],
    );
    await press(tester, GameAction.r1);
    expect(find.text('Slot 2'), findsOneWidget);
    await press(tester, GameAction.l1);
    expect(find.text('This PC'), findsOneWidget);
  });

  testWidgets('narrow: the settings become one row above the list', (tester) async {
    await open(tester, width: 900);
    final panel = tester.getTopLeft(find.byKey(const ValueKey('play-settings')));
    final saves = tester.getTopLeft(find.text('This PC'));
    expect(panel.dy, lessThan(saves.dy));
  });

  testWidgets('B closes an open picker before leaving', (tester) async {
    await open(tester);
    await press(tester, GameAction.favorite);
    expect(find.byKey(const ValueKey('dropdown-list')), findsOneWidget);
    await press(tester, GameAction.back);
    expect(find.byKey(const ValueKey('dropdown-list')), findsNothing);
    expect(find.byType(PlayScreen), findsOneWidget);
    await press(tester, GameAction.back);
    expect(find.byType(PlayScreen), findsNothing);
  });

  testWidgets('the cover is 240 × 324, as on the game page', (tester) async {
    await open(tester);
    expect(tester.getSize(find.byKey(const ValueKey('play-cover'))), const Size(240, 324));
  });

  testWidgets("choosing the same emulator again keeps its core (the remembered one)", (tester) async {
    await open(tester, remembered: const SaveMaker('retroarch', coreId: 'play'));
    expect(inPanel('Core: Play!'), findsOneWidget);
    await press(tester, GameAction.favorite);
    await tester.tap(find.text('RetroArch').last);
    await tester.pumpAndSettle();
    expect(inPanel('Core: Play!'), findsOneWidget);
  });

  testWidgets("switching to RetroArch picks the remembered core when RetroArch is the remembered emulator", (
    tester,
  ) async {
    await open(tester, remembered: const SaveMaker('retroarch', coreId: 'play'));
    await press(tester, GameAction.favorite);
    await tester.tap(find.text('PCSX2').last);
    await tester.pumpAndSettle();
    await press(tester, GameAction.favorite);
    await tester.tap(find.text('RetroArch').last);
    await tester.pumpAndSettle();
    expect(inPanel('Core: Play!'), findsOneWidget);
  });

  testWidgets("the cover sits exactly where the game page's does; title and platform beside it, as there", (
    tester,
  ) async {
    await open(tester);
    expect(tester.getTopLeft(find.byKey(const ValueKey('play-cover'))), gamePageCoverOffset);
    final cover = tester.getRect(find.byKey(const ValueKey('play-cover')));
    final title = tester.getTopLeft(find.text('Burnout 3: Takedown').last);
    expect(title.dx, greaterThan(cover.right));
    expect(title.dy, lessThan(cover.center.dy));
  });

  testWidgets('Back is at the bottom of the cover column, as wide as Play, outlined', (tester) async {
    await open(tester);
    final play = tester.getRect(find.byKey(const ValueKey('play-start')));
    final back = tester.getRect(find.byKey(const ValueKey('play-back')));
    expect(back.width, play.width);
    expect(back.top, greaterThan(play.bottom));
    final boxes = tester
        .widgetList<Container>(
          find.descendant(of: find.byKey(const ValueKey('play-back')), matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    expect(boxes.any((d) => d.border != null && d.color == null), isTrue, reason: 'outlined, not filled');
    await tester.tap(find.byKey(const ValueKey('play-back')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsNothing);
  });

  testWidgets('the emulator field opens a list right under it, ✓ on the current; picking closes it', (tester) async {
    await open(tester);
    final field = tester.getRect(find.byKey(const ValueKey('play-emulator')));
    await tester.tap(find.byKey(const ValueKey('play-emulator')));
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byKey(const ValueKey('dropdown-list')));
    expect(list.top, greaterThanOrEqualTo(field.bottom));
    expect(list.left, moreOrLessEquals(field.left));
    expect(list.width, moreOrLessEquals(field.width));
    final current = find.byKey(const ValueKey('dropdown-current'));
    expect(find.descendant(of: current, matching: find.text('PCSX2')), findsOneWidget);
    expect(find.descendant(of: current, matching: find.byIcon(Icons.check)), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('dropdown-list')), matching: find.text('RetroArch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dropdown-list')), findsNothing);
    expect(inPanel('RetroArch'), findsOneWidget);
  });

  testWidgets('Full screen is on by default; turning it off is kept for that emulator', (tester) async {
    await open(tester, emulators: const [
      EmulatorOption(_pcsx2, 'PCSX2', fullscreen: true),
      EmulatorOption(_ra, 'RetroArch', cores: _cores, fullscreen: true),
    ]);
    Switch toggle() => tester.widget<Switch>(
        find.descendant(of: find.byKey(const ValueKey('play-fullscreen')), matching: find.byType(Switch)));
    expect(toggle().value, isTrue);
    await tester.tap(find.byKey(const ValueKey('play-fullscreen')));
    await tester.pumpAndSettle();
    expect(toggle().value, isFalse);
    expect(engine.fullscreen, {'pcsx2': false});
  });

  testWidgets("an emulator Gargosy can't tell to go full screen: the switch is greyed and says so", (tester) async {
    await open(tester, emulators: const [EmulatorOption(_pcsx2, 'PCSX2')]);
    expect(inPanel('Set in the emulator'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-fullscreen')));
    await tester.pumpAndSettle();
    expect(engine.fullscreen, isEmpty);
  });
}
