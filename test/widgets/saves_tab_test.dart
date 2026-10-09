import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/core/save/catalog/save_catalog.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/play/play_menu.dart';
import 'package:gargosy/ui/screens/game/saves_tab.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';
import '../unit/play_controller_test.dart' show FakeEngine;

const _pcsx2 = SaveMaker('pcsx2');

SaveEntry _local(int day) =>
    SaveEntry(source: SaveSource.local, fileName: 'Mcd001.ps2', savedAt: DateTime(2026, 10, day), maker: _pcsx2, tag: 'pcsx2', sameAsRommId: '9');
SaveEntry _romm(String name, int day) =>
    SaveEntry(source: SaveSource.romm, fileName: name, savedAt: DateTime(2026, 10, day), maker: _pcsx2, tag: 'pcsx2', slot: 'gargosy', rommSave: const {'id': 4});

void main() {
  late FakeEngine engine;
  final g = Game.fromJson(gameJson(1, 'G', fsName: 'G.chd'));

  Future<void> pump(WidgetTester tester, {List<SaveEntry> local = const [], List<SaveEntry> romm = const [], bool offline = false,
      List<BackupEntry> waiting = const [], List<ResumeEntry> states = const []}) async {
    await setDesktopSize(tester);
    engine = FakeEngine()
      ..menu = PlayMenu(
        emulators: const [EmulatorOption(_pcsx2, 'PCSX2')],
        platformDefault: _pcsx2,
        catalog: SaveCatalog(
          thisPc: local,
          backups: const [],
          romm: [for (final r in romm) RommSaveGroup(slot: 'gargosy', tag: 'pcsx2', newest: r, older: const [])],
          rommOffline: offline,
        ),
      )
      ..states = states;
    await tester.pumpWidget(testApp(SavesTab(game: g), overrides: [
      playEngineProvider.overrideWithValue(engine),
      uploadsWaitingProvider.overrideWith((ref, id) => waiting),
    ]));
    await tester.pumpAndSettle();
  }

  Future<void> focus(WidgetTester tester, String text) async {
    Focus.of(tester.element(find.text(text))).requestFocus();
    await tester.pumpAndSettle();
  }

  testWidgets('X puts a RomM save on this PC; an older one asks first', (tester) async {
    await pump(tester, local: [_local(9)], romm: [_romm('old.ps2', 5)]);
    await focus(tester, 'old.ps2');
    await press(tester, GameAction.detail);
    expect(find.text('Put an older save on this PC?'), findsOneWidget);
    await tester.tap(find.text('Put it on this PC'));
    await tester.pumpAndSettle();
    expect(engine.steps, ['restore']);
    expect(find.textContaining('on this PC now'), findsOneWidget);
  });

  testWidgets('hold A deletes after asking; after a delete the list is read again', (tester) async {
    await pump(tester, romm: [_romm('a.ps2', 9)]);
    final before = engine.menuReads;
    await focus(tester, 'a.ps2');
    await press(tester, GameAction.confirmHold);
    expect(find.text('Delete this save from RomM?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(engine.steps, ['delete']);
    expect(engine.menuReads, greaterThan(before));
  });

  testWidgets('Upload to RomM and Back up now', (tester) async {
    await pump(tester, local: [_local(9)]);
    await tester.tap(find.text('Upload to RomM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();
    expect(engine.steps, ['upload', 'backup']);
  });

  testWidgets("offline: RomM rows are disabled", (tester) async {
    await pump(tester, local: [_local(9)], romm: [_romm('a.ps2', 9)], offline: true);
    expect(find.textContaining("RomM can't be reached"), findsOneWidget);
  });

  testWidgets('a save waiting to upload shows', (tester) async {
    await pump(tester, waiting: [BackupEntry(timestamp: DateTime(2026, 10, 9, 21), md5Hash: 'h', localZipPath: 'z')]);
    expect(find.textContaining('Waiting to upload'), findsOneWidget);
  });

  testWidgets('Saves | States switches the list; states are for looking at', (tester) async {
    await pump(tester, states: [
      ResumeEntry(emulatorId: 'pcsx2', emulatorName: 'PCSX2', fileName: 's1.p2s', slot: const NumberedStateSlot(1), savedAt: DateTime(2026, 10, 9), where: ResumeWhere.thisPc),
    ]);
    await tester.tap(find.textContaining('States'));
    await tester.pumpAndSettle();
    expect(find.text('Slot 1'), findsOneWidget);
    await tester.tap(find.text('Slot 1'));
    await tester.pumpAndSettle();
    expect(engine.steps, isEmpty);
  });

  testWidgets('a game running: the actions say to close it first', (tester) async {
    await pump(tester, local: [_local(9)]);
    final c = ProviderScope.containerOf(tester.element(find.byType(SavesTab)));
    c.read(playControllerProvider.notifier).state = const PlayState(runningGameId: '1');
    await tester.tap(find.text('Upload to RomM'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Close the game first'), findsOneWidget);
    expect(engine.steps, isEmpty);
  });

  testWidgets('RomM failing to answer shows the error with Retry', (tester) async {
    await setDesktopSize(tester);
    engine = FakeEngine()..menuError = StateError('RomM did not answer');
    await tester.pumpWidget(testApp(SavesTab(game: g), overrides: [
      playEngineProvider.overrideWithValue(engine),
      uploadsWaitingProvider.overrideWith((ref, id) => const []),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });
}
