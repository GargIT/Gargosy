// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy (#57): DuckStation's cards sync through sigil; what's left of its
// strategy is the card setup sigil reads (sigilCard) and when a pull must
// finish before launch. The upload and restore tests went with that code.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/duckstation_config.dart';
import 'package:path/path.dart' as p;

import '../helpers/duckstation_test_env.dart';

void main() {
  late Directory base;
  late DuckstationTestEnv env;
  final game = Game(
    id: 'g1',
    name: 'Colin McRae Rally 2.0',
    fsName: 'Colin McRae Rally 2.0 (Europe) (SLES-02605).chd',
    platformSlug: 'psx',
    fileSize: 0,
  );
  const saveName = 'Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It)';
  const gamedb = 'SLES-02605:\n  name: "Colin McRae Rally 2.0"\n  saveName: "$saveName"\n';

  setUp(() async {
    DuckstationGameDb.clearCache();
    base = await Directory.systemTemp.createTemp('duckstation_memcards');
    env = await DuckstationTestEnv.create(base);
  });

  tearDown(() => base.delete(recursive: true));

  String romPath() => p.join(base.path, 'Colin McRae Rally 2.0 (Europe) (SLES-02605).chd');
  Future<void> cardTypes(String types) => env.writeSettings('[MemoryCards]\n$types\n');
  Future<String?> stem() async => (await env.strategy.sigilCard(game, romPath())).stem;

  group('for sigil (Gargosy): the card name, folder and types DuckStation uses', () {
    test("by title (DuckStation's default): the game database's save title, not the ROM name", () async {
      await cardTypes('Card1Type = PerGameTitle');
      await env.writeGameDb(gamedb);
      final card = await env.strategy.sigilCard(game, romPath());
      expect(card.stem, saveName);
      expect(card.root, p.dirname(env.memcardsDir));
      expect(card.options, {'Card1Type': 'PerGameTitle', 'Card2Type': 'None'});
    });

    test("a per-game setting wins, and by serial needs no title", () async {
      await cardTypes('Card1Type = PerGameTitle');
      await env.writeGameSettings('SLES-02605', '[MemoryCards]\nCard1Type = PerGame\n');
      final card = await env.strategy.sigilCard(game, romPath());
      expect(card.stem, isNull);
      expect(card.options['Card1Type'], 'PerGame');
    });

    test('by title, unknown to the database: the card found by its name', () async {
      await cardTypes('Card1Type = PerGameTitle');
      await env.writeCard('Colin McRae Rally 2.0 (Europe)_1.mcd');
      expect(await stem(), 'Colin McRae Rally 2.0 (Europe)');
    });

    group('by title, a multi-disc game', () {
      const discsets =
          '- name: "Colin Set"\n  saveName: "Colin Set Save"\n  serials:\n    - SLES-02605\n    - SLES-12605\n';
      setUp(() async {
        await cardTypes('Card1Type = PerGameTitle');
        await env.writeGameDb(gamedb, discsets: discsets);
      });

      test("the disc set's card", () async {
        expect(await stem(), 'Colin Set Save');
      });

      test("a card already made under the disc's own title wins, as in DuckStation", () async {
        await env.writeCard('Colin Set Save_1.mcd');
        await env.writeCard('${saveName}_1.mcd');
        expect(await stem(), saveName);
      });

      test("the disc's own card with playlist titles off", () async {
        await cardTypes('Card1Type = PerGameTitle\nUsePlaylistTitle = false');
        expect(await stem(), saveName);
      });
    });

    test('cards in a folder not called memcards (the Directory setting): no root for sigil', () async {
      final elsewhere = Directory(p.join(base.path, 'elsewhere'))..createSync();
      await cardTypes('Card1Type = PerGame\nDirectory = ${elsewhere.path}');
      expect((await env.strategy.sigilCard(game, romPath())).root, isNull);
    });
  });

  test('the pull must finish before launch only when a shared card may be patched', () async {
    await cardTypes('Card1Type = Shared');
    expect(await env.strategy.pullMustFinishBeforeLaunch(game, romPath()), isTrue);
    await cardTypes('Card1Type = PerGame');
    expect(await env.strategy.pullMustFinishBeforeLaunch(game, romPath()), isFalse);
  });
}
