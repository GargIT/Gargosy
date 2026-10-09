import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';
import '../unit/play_controller_test.dart' show FakeEngine;

const _pcsx2 = SaveMaker('pcsx2');
const _ra = SaveMaker('retroarch', coreId: 'pcsx2');

DateTime _day(int daysAgo, int h) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h).subtract(Duration(days: daysAgo));
}

SaveEntry _local(DateTime t, {String? onRomm}) =>
    SaveEntry(source: SaveSource.local, fileName: 'Mcd001.ps2', savedAt: t, maker: _pcsx2, tag: 'pcsx2', sameAsRommId: onRomm);
SaveEntry _romm(String name, DateTime t, {int id = 9}) => SaveEntry(
    source: SaveSource.romm, fileName: name, savedAt: t, maker: _pcsx2, tag: 'pcsx2', slot: name, rommSave: {'id': id});
RommSaveGroup _g(SaveEntry e) => RommSaveGroup(slot: e.slot!, tag: e.tag!, newest: e, older: const []);

void main() {
  late AppRoot root;
  late FakeEngine engine;
  final burnout = Game.fromJson(gameJson(7564, 'Burnout 3: Takedown', fsName: 'Burnout 3 (USA).chd'));

  Future<void> open(WidgetTester tester, {SaveCatalog? catalog, List<EmulatorOption>? emulators, List<ResumeEntry> states = const []}) async {
    await setDesktopSize(tester);
    root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    engine = FakeEngine()
      ..menu = PlayMenu(
        emulators: emulators ?? const [EmulatorOption(_pcsx2, 'PCSX2'), EmulatorOption(_ra, 'RetroArch · PCSX2')],
        platformDefault: (emulators ?? const [EmulatorOption(_pcsx2, '')]).firstOrNull?.maker,
        catalog: catalog ?? const SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false),
      )
      ..states = states;
    await tester.pumpWidget(testApp(
        Builder(
            builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayScreen(game: burnout))),
                    child: const Text('open'),
                  ),
                )),
        root: root,
        overrides: [
      appPreferencesProvider.overrideWithValue(MemoryPrefs()),
      playEngineProvider.overrideWithValue(engine),
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists this PC and RomM saves, newest first, with the newest preselected', (tester) async {
    await open(tester,
        catalog: SaveCatalog(
            thisPc: [_local(_day(2, 9))], backups: const [], romm: [_g(_romm('burnout.ps2', _day(0, 21)))], rommOffline: false));
    expect(find.text('On this PC'), findsOneWidget);
    expect(find.text('On RomM'), findsOneWidget);
    expect(find.text('Plays in PCSX2'), findsOneWidget);
    // The newest (RomM's, today) is the one Start uses.
    expect(find.byKey(const ValueKey('chosen-burnout.ps2')), findsOneWidget);
  });

  testWidgets('Start plays the chosen save in the chosen emulator', (tester) async {
    await open(tester,
        catalog: SaveCatalog(
            thisPc: [_local(_day(2, 9), onRomm: '1')], backups: const [], romm: [_g(_romm('burnout.ps2', _day(0, 21)))], rommOffline: false));
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(engine.steps, ['states', 'prepare', 'launch']);
    expect(engine.request!.emulator, _pcsx2);
    expect(engine.request!.save?.fileName, 'burnout.ps2');
    expect(find.byType(PlayScreen), findsNothing, reason: 'the play screen closes once the game started');
  });

  testWidgets('an older save asks first, and No keeps the screen open', (tester) async {
    await open(tester,
        catalog: SaveCatalog(
            thisPc: [_local(_day(0, 21), onRomm: '1')], backups: const [], romm: [_g(_romm('old.ps2', _day(5, 9)))], rommOffline: false));
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

  testWidgets('Y changes the emulator', (tester) async {
    await open(tester);
    await press(tester, GameAction.favorite);
    await tester.tap(find.text('RetroArch · PCSX2').last);
    await tester.pumpAndSettle();
    expect(find.text('Plays in RetroArch · PCSX2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(engine.request!.emulator, _ra);
  });

  testWidgets('with no emulator installed it says so', (tester) async {
    await open(tester, emulators: const []);
    expect(find.textContaining('No emulator for PlayStation 2 is installed'), findsOneWidget);
  });

  testWidgets('RB shows the states; A chooses one and Start resumes it', (tester) async {
    await open(tester,
        catalog: SaveCatalog(thisPc: [_local(_day(0, 9), onRomm: '1')], backups: const [], romm: const [], rommOffline: false),
        states: [
          ResumeEntry(
              emulatorId: 'pcsx2', emulatorName: 'PCSX2', fileName: 'slot1.p2s', slot: const NumberedStateSlot(1),
              savedAt: _day(0, 21), where: ResumeWhere.thisPc),
        ]);
    await press(tester, GameAction.r1);
    expect(find.text('Slot 1'), findsOneWidget);
    await tester.tap(find.text('Slot 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(engine.steps, ['states', 'check', 'prepare', 'launch']);
    expect(engine.loadStatePath, isNotNull);
  });
}
