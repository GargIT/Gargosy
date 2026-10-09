import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/catalog/save_catalog.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/play/play_menu.dart';
import 'package:gargosy/play/save_actions.dart';

import '../helpers/game_fixtures.dart';
import 'play_controller_test.dart' show FakeEngine;

void main() {
  late FakeEngine engine;
  late ProviderContainer c;
  const pcsx2 = SaveMaker('pcsx2');
  final rommSave = SaveEntry(source: SaveSource.romm, fileName: 'g.ps2', savedAt: DateTime(2026), maker: pcsx2, rommSave: const {'id': 4});
  final g = game(1, 'G');

  setUp(() {
    engine = FakeEngine()
      ..menu = const PlayMenu(
        emulators: [EmulatorOption(pcsx2, 'PCSX2')],
        platformDefault: pcsx2,
        catalog: SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false),
      );
    c = ProviderContainer(overrides: [playEngineProvider.overrideWithValue(engine)]);
  });
  tearDown(() => c.dispose());

  test('restore, delete, upload and back-up go through the engine and re-read the list', () async {
    c.listen(playMenuProvider(PlayMenuKey(g)), (_, _) {});
    await c.read(playMenuProvider(PlayMenuKey(g)).future);
    final before = engine.menuReads;
    final a = c.read(saveActionsProvider);
    expect(await a.restore(g, rommSave, pcsx2), isNull);
    expect(await a.delete(g, rommSave), isNull);
    expect(await a.upload(g, pcsx2), isNull);
    expect(await a.backUpNow(g, pcsx2), isNull);
    expect(engine.steps, ['restore', 'delete', 'upload', 'backup']);
    await c.read(playMenuProvider(PlayMenuKey(g)).future);
    expect(engine.menuReads, greaterThan(before), reason: 'after a change the list is read again');
  });

  test('manage actions are refused while a game runs', () async {
    await c.read(playControllerProvider.notifier).play(game(2, 'H'));
    final a = c.read(saveActionsProvider);
    expect(await a.delete(g, rommSave), contains('Close the game first'));
    expect(await a.restore(g, rommSave, pcsx2), contains('Close the game first'));
    expect(engine.steps, isNot(contains('delete')));
    expect(engine.steps, isNot(contains('restore')));
  });

  test('a failure says why and changes nothing else', () async {
    engine.failDelete = true;
    expect(await c.read(saveActionsProvider).delete(g, rommSave), contains("Couldn't delete"));
  });

  test('syncing save states says what moved', () async {
    expect(await c.read(saveActionsProvider).syncStates(g), '1 state down, 0 up');
  });
}
