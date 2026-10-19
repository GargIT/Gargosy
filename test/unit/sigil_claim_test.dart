// Issue #56: saves on Flycast's shared VMU that sigil can't tie to a game
// are listed, and the player claims one for the game.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:gargosy/sigil/sigil_save_strategy.dart';
import 'package:gargosy/sigil/sigil_state_store.dart';
import 'package:gargosy/sigil/sigil_sync.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';

Game _dc(int id, String name) => Game.fromJson({...gameJson(id, name, fsName: '$name.chd'), 'platform_slug': 'dc'});

void main() {
  late io.Directory tmp;
  late SigilStateStore states;
  late List<SigilSyncCall> calls;
  late List<String> unowned;
  setUp(() {
    tmp = io.Directory.systemTemp.createTempSync('gargosy-sigilclaim-');
    states = SigilStateStore(p.join(tmp.path, 'sigil'));
    calls = [];
    unowned = ['SONIC_01.SYS', 'MYSTERY.DAT'];
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  SigilSaveStrategy flycast() => SigilSaveStrategy.forEmulator(
    'flycast',
    base: null,
    emulatorDir: () => p.join(tmp.path, 'emulators', 'flycast'),
    states: states,
    unitsDir: p.join(tmp.path, 'units'),
    collect: (call) async {
      calls.add(call);
      final left = [
        for (final n in unowned)
          if (!call.claimed.contains(n)) n,
      ];
      return SigilCollected(
        artifact: 'vmu_save_A1.bin',
        data: Uint8List(4),
        contentHash: '',
        identityHash: '',
        changed: false,
        state: Uint8List(2),
        holding: null,
        unowned: left,
        restoreAgain: false,
      );
    },
  )!;

  const rom = r'D:\roms\dc\Crazy Taxi.chd';
  final taxi = _dc(1, 'Crazy Taxi');

  test("the shared VMU's unclaimed saves are listed for the game", () async {
    expect(await flycast().unclaimedSavesFor(taxi, rom), ['SONIC_01.SYS', 'MYSTERY.DAT']);
    expect(calls.single.claimed, isEmpty);
  });

  test("a claim goes to sigil on the game's next collects, and the save is no longer listed", () async {
    final s = flycast();
    await s.claimSave(taxi, rom, 'MYSTERY.DAT');
    expect(await s.unclaimedSavesFor(taxi, rom), ['SONIC_01.SYS']);
    await s.getSaveFiles(taxi, rom);
    expect(calls.map((c) => c.claimed), [
      ['MYSTERY.DAT'],
      ['MYSTERY.DAT'],
    ]);
  });

  test('a claim is kept until an upload commits it (it survives a restart)', () async {
    await flycast().claimSave(taxi, rom, 'MYSTERY.DAT');
    final again = flycast();
    await again.getSaveFiles(taxi, rom);
    expect(calls.last.claimed, ['MYSTERY.DAT']);
    await again.afterUpload(taxi, rom);
    await again.getSaveFiles(taxi, rom);
    expect(calls.last.claimed, isEmpty, reason: "from then on sigil's state knows the owner");
  });

  test("a claim is the game's own: another game's collect doesn't send it", () async {
    final s = flycast();
    await s.claimSave(taxi, rom, 'MYSTERY.DAT');
    await s.getSaveFiles(_dc(2, 'Soul Calibur'), r'D:\roms\dc\Soul Calibur.chd');
    expect(calls.last.claimed, isEmpty);
  });

  test('claiming the same save twice sends it once', () async {
    final s = flycast();
    await s.claimSave(taxi, rom, 'MYSTERY.DAT');
    await s.claimSave(taxi, rom, 'MYSTERY.DAT');
    await s.getSaveFiles(taxi, rom);
    expect(calls.last.claimed, ['MYSTERY.DAT']);
  });

  test('a game sigil doesn\'t sync there has no unclaimed saves', () async {
    final s = flycast();
    final gba = Game.fromJson({...gameJson(3, 'Zelda', fsName: 'Zelda.gba'), 'platform_slug': 'gba'});
    expect(await s.unclaimedSavesFor(gba, r'D:\roms\gba\Zelda.gba'), isEmpty);
    expect(calls, isEmpty);
  });

  test('a claim passes through sigil itself (an empty VMU folder: nothing to claim, no error)', () async {
    final root = io.Directory(p.join(tmp.path, 'vmu'))..createSync();
    final got = await SigilEngine.collect(
      SigilSyncCall(
        layout: 'flycast_standalone',
        platform: 'dreamcast',
        contentPath: rom,
        saveRoot: root.path,
        claimed: const ['MYSTERY.DAT'],
      ),
    );
    expect(got.data, isNull);
    expect(got.unowned, isEmpty);
  });

  test("a damaged claims file reads as no claims; none left removes the file", () async {
    states.setClaims('flycast', '1', ['A']);
    final file = io.File(p.join(tmp.path, 'sigil', 'flycast', '1.claims.json'));
    expect(file.existsSync(), isTrue);
    file.writeAsStringSync('{not json');
    expect(states.claims('flycast', '1'), isEmpty);
    states.setClaims('flycast', '1', const []);
    expect(file.existsSync(), isFalse);
  });
}
