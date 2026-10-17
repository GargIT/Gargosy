import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/core/save/catalog/play_view.dart';
import 'package:gargosy/core/save/catalog/save_catalog.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/ui/widgets/save_list/save_list.dart';
import 'package:gargosy/ui/widgets/save_list/state_list.dart';

import '../helpers/widget_env.dart';

const _pcsx2 = SaveMaker('pcsx2');

DateTime _t(int day, [int h = 12]) => DateTime(2026, 10, day, h);

SaveEntry _local(int day, {String? onRomm}) =>
    SaveEntry(source: SaveSource.local, fileName: 'Mcd001.ps2', savedAt: _t(day), maker: _pcsx2, tag: 'pcsx2', sameAsRommId: onRomm, sizeBytes: 8650752);
SaveEntry _backup(int day) => SaveEntry(
    source: SaveSource.backup,
    fileName: 'backup-$day.zip',
    savedAt: _t(day),
    maker: _pcsx2,
    backup: BackupEntry(timestamp: _t(day), md5Hash: 'h$day', localZipPath: 'b$day.zip', emulatorId: 'pcsx2'));
SaveEntry _romm(String name, int day, {SaveMaker maker = _pcsx2, String tag = 'pcsx2', int id = 1}) => SaveEntry(
    source: SaveSource.romm, fileName: name, savedAt: _t(day), maker: maker, tag: tag, slot: 'gargosy', rommSave: {'id': id});

PlayView _view({List<SaveEntry> local = const [], List<SaveEntry> backups = const [], List<RommSaveGroup> romm = const [], bool showAll = false, bool offline = false}) =>
    buildPlayView(
      catalog: SaveCatalog(thisPc: local, backups: backups, romm: romm, rommOffline: offline),
      states: const [],
      platformSlug: 'ps2',
      picked: _pcsx2,
      platformDefault: _pcsx2,
      installed: const {'pcsx2'},
      showAll: showAll,
    );

RommSaveGroup _group(List<SaveEntry> newestFirst) =>
    RommSaveGroup(slot: 'gargosy', tag: newestFirst.first.tag ?? '', newest: newestFirst.first, older: newestFirst.skip(1).toList());

void main() {
  Future<void> pump(WidgetTester tester, Widget list, {double width = 1000}) async {
    tester.view.physicalSize = Size(width + 80, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(Padding(padding: const EdgeInsets.all(40), child: list)));
    await tester.pumpAndSettle();
  }

  String name(SaveMaker m) => m.emulatorId == 'pcsx2' ? 'PCSX2' : 'RetroArch';

  testWidgets('This PC then On RomM; backups and older versions fold; X or A unfolds', (tester) async {
    await pump(tester, SaveList(
      view: _view(local: [_local(9)], backups: [_backup(8), _backup(7)], romm: [_group([_romm('a.zip', 9, id: 1), _romm('b.zip', 8, id: 2), _romm('c.zip', 7, id: 3)])]),
      mode: SaveListMode.choose,
      nameOf: name,
    ));
    expect(find.text('This PC'), findsOneWidget);
    expect(find.text('On RomM'), findsOneWidget);
    expect(find.text('▸ 2 backups'), findsOneWidget);
    expect(find.text('▸ 2 older versions'), findsOneWidget);
    expect(find.text('b.zip'), findsNothing);
    await tester.tap(find.text('▸ 2 older versions'));
    await tester.pumpAndSettle();
    expect(find.text('▾ 2 older versions'), findsOneWidget);
    expect(find.text('b.zip'), findsOneWidget);
  });

  testWidgets('two columns when wide, stacked when narrow', (tester) async {
    final view = _view(local: [_local(9)], romm: [_group([_romm('a.zip', 9)])]);
    await pump(tester, SaveList(view: view, mode: SaveListMode.choose, nameOf: name), width: 1400);
    var pc = tester.getTopLeft(find.text('This PC')), romm = tester.getTopLeft(find.text('On RomM'));
    expect(pc.dy, romm.dy);
    expect(romm.dx, greaterThan(pc.dx));
    await pump(tester, SaveList(view: view, mode: SaveListMode.choose, nameOf: name), width: 800);
    pc = tester.getTopLeft(find.text('This PC'));
    romm = tester.getTopLeft(find.text('On RomM'));
    expect(romm.dy, greaterThan(pc.dy));
  });

  testWidgets('marks: the emulator tag, on RomM; a save the emulator can\'t use is greyed with why', (tester) async {
    final chosen = <String>[];
    await pump(tester, SaveList(
      view: _view(local: [_local(9, onRomm: '1')], romm: [_group([_romm('a.zip', 9)]), _group([_romm('dolphin.gci', 8, maker: const SaveMaker('dolphin'), tag: 'dolphin', id: 5)])], showAll: true),
      mode: SaveListMode.choose,
      nameOf: name,
      onChoose: (p) => chosen.add(p.entry.fileName),
    ));
    expect(find.text('on RomM'), findsOneWidget);
    expect(find.text('pcsx2'), findsWidgets);
    final lrps2 = find.ancestor(of: find.text('dolphin.gci'), matching: find.byKey(const ValueKey('save-row-unusable')));
    expect(lrps2, findsOneWidget);
    await tester.tap(find.text('dolphin.gci'));
    await tester.pumpAndSettle();
    expect(chosen, isEmpty, reason: "a save the emulator can't use can't be chosen");
    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(chosen, ['a.zip']);
  });

  testWidgets('the chosen row is marked', (tester) async {
    final view = _view(romm: [_group([_romm('a.zip', 9)])]);
    await pump(tester, SaveList(view: view, mode: SaveListMode.choose, nameOf: name, chosen: view.preselected));
    expect(find.descendant(of: find.byKey(const ValueKey('save-row-chosen')), matching: find.text('a.zip')), findsOneWidget);
  });

  testWidgets('manage mode: X puts a RomM row on this PC, hold A deletes it', (tester) async {
    final restored = <String>[], deleted = <String>[];
    await pump(tester, SaveList(
      view: _view(romm: [_group([_romm('a.zip', 9)])]),
      mode: SaveListMode.manage,
      nameOf: name,
      onRestore: (e) => restored.add(e.fileName),
      onDelete: (e) => deleted.add(e.fileName),
    ));
    Focus.of(tester.element(find.text('a.zip'))).requestFocus();
    await tester.pumpAndSettle();
    await press(tester, GameAction.detail);
    expect(restored, ['a.zip']);
    await press(tester, GameAction.confirmHold);
    expect(deleted, ['a.zip']);
  });

  testWidgets("offline: On RomM says RomM can't be reached, and its rows do nothing", (tester) async {
    final restored = <String>[];
    await pump(tester, SaveList(
      view: _view(local: [_local(9)], romm: [_group([_romm('a.zip', 9)])], offline: true),
      mode: SaveListMode.manage,
      nameOf: name,
      onRestore: (e) => restored.add(e.fileName),
    ));
    expect(find.textContaining("RomM can't be reached"), findsOneWidget);
  });

  testWidgets('the state list: newest first, where each is, and a version warning', (tester) async {
    final chose = <String>[];
    await pump(tester, StateList(
      states: [
        ResumeEntry(emulatorId: 'pcsx2', emulatorName: 'PCSX2', fileName: 's1.p2s', slot: const NumberedStateSlot(1), savedAt: _t(9), where: ResumeWhere.thisPc),
        ResumeEntry(
            emulatorId: 'pcsx2', emulatorName: 'PCSX2', fileName: 'auto.p2s', slot: const AutoStateSlot(), savedAt: _t(8), where: ResumeWhere.romm,
            emulatorVersion: '1.7', installedVersion: '2.0', compat: StateCompat.mismatch),
      ],
      chosen: null,
      loading: false,
      onChoose: (e) => chose.add(e.fileName),
    ));
    expect(find.text('Slot 1'), findsOneWidget);
    expect(find.textContaining('on RomM'), findsOneWidget);
    expect(find.textContaining('Made with PCSX2 1.7; you have 2.0'), findsOneWidget);
    await tester.tap(find.text('Slot 1'));
    await tester.pumpAndSettle();
    expect(chose, ['s1.p2s']);
  });

  testWidgets("a state the emulator can't start in: shown with where to load it, A doesn't choose it", (tester) async {
    final chose = <String>[];
    await pump(tester, StateList(
      states: [
        ResumeEntry(
            emulatorId: 'azahar', emulatorName: 'Azahar', fileName: 'x.01.cst', slot: const NumberedStateSlot(1),
            savedAt: _t(9), where: ResumeWhere.romm, resumable: false),
      ],
      chosen: null,
      loading: false,
      onChoose: (e) => chose.add(e.fileName),
    ));
    expect(find.textContaining("load it from Azahar's menu"), findsOneWidget);
    await tester.tap(find.text('Slot 1'));
    await tester.pumpAndSettle();
    expect(chose, isEmpty);
  });

  testWidgets('manage mode with the mouse: a click opens Put on this PC / Delete', (tester) async {
    final restored = <String>[], deleted = <String>[];
    await pump(tester, SaveList(
      view: _view(romm: [_group([_romm('a.zip', 9)])]),
      mode: SaveListMode.manage,
      nameOf: name,
      onRestore: (e) => restored.add(e.fileName),
      onDelete: (e) => deleted.add(e.fileName),
    ));
    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Put on this PC'));
    await tester.pumpAndSettle();
    expect(restored, ['a.zip']);
    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, ['a.zip']);
  });

  testWidgets("manage mode: a save the emulator can't use isn't put on this PC (X does nothing), but can be deleted", (tester) async {
    final restored = <String>[], deleted = <String>[];
    await pump(tester, SaveList(
      view: _view(romm: [_group([_romm('dolphin.gci', 8, maker: const SaveMaker('dolphin'), tag: 'dolphin', id: 5)])], showAll: true),
      mode: SaveListMode.manage,
      nameOf: name,
      onRestore: (e) => restored.add(e.fileName),
      onDelete: (e) => deleted.add(e.fileName),
    ));
    Focus.of(tester.element(find.text('dolphin.gci'))).requestFocus();
    await tester.pumpAndSettle();
    await press(tester, GameAction.detail);
    expect(restored, isEmpty);
    await press(tester, GameAction.confirmHold);
    expect(deleted, ['dolphin.gci']);
    await tester.tap(find.text('dolphin.gci'));
    await tester.pumpAndSettle();
    expect(find.text('Put on this PC'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
  });
}
