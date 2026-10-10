import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/formats/ps2_memory_card.dart';
import 'package:gargosy/core/save/save_strategy.dart';
import 'package:gargosy/core/save/state_sync_capable.dart';
import 'package:gargosy/emulators/pcsx2_folder_card.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:gargosy/sigil/sigil_save_strategy.dart';
import 'package:gargosy/sigil/sigil_state_store.dart';
import 'package:gargosy/sigil/sigil_sync.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/ps1_card_builder.dart';

/// The emulator's old strategy: records what reaches it.
class _Base extends SaveStrategy {
  final calls = <String>[];
  @override
  String get strategyId => 'mgba';
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => r'C:\base';
  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async {
    calls.add('getSaveFiles ${game.platformSlug}');
    return [];
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    calls.add('restoreSave ${game.platformSlug}');
    return true;
  }
}

class _StateBase extends _Base with StateSyncCapable {
  @override
  String get strategyId => 'pcsx2';
  @override
  Future<String> stateDirectory(Game game, String romPath) async => r'C:\states';
  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async =>
      (n) => n == 'x.p2s';
}

Game _game(String slug, {String? titleId, String? saveTarget}) => Game.fromJson({
  ...gameJson(42, 'Tetris', fsName: 'Tetris (World).gb'),
  'platform_slug': slug,
  'title_id': ?titleId,
  'save_target': ?saveTarget,
});

void main() {
  late io.Directory tmp;
  late String emulatorDir;
  late SigilStateStore states;
  late _Base base;
  setUp(() {
    tmp = io.Directory.systemTemp.createTempSync('gargosy-sigilstrategy-');
    emulatorDir = p.join(tmp.path, 'emulators', 'mgba');
    states = SigilStateStore(p.join(tmp.path, 'sigil'));
    base = _Base();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  SigilSaveStrategy mgba({SaveStrategy? b}) => SigilSaveStrategy.forEmulator(
    'mgba',
    base: b ?? base,
    emulatorDir: () => emulatorDir,
    states: states,
    unitsDir: p.join(tmp.path, 'sigil', 'units'),
  )!;

  final rom = r'D:\roms\gb\Tetris (World).gb';

  void putSave(List<int> bytes) => io.File(p.join(emulatorDir, 'saves', 'Tetris (World).sav'))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  test("a Game Boy game's save comes as sigil's unit file, for the autosave slot", () async {
    putSave(List.filled(32768, 5));
    final s = mgba();
    final files = await s.getSaveFiles(_game('gb'), rom);
    expect(files.map((f) => p.basename(f.path)), ['Tetris (World).srm']);
    expect(files.single.readAsBytesSync(), List.filled(32768, 5));
    expect(s.uploadSlotFor(_game('gb')), 'autosave');
    expect(s.restoresUnitsItselfFor(_game('gb')), isTrue);
    expect(base.calls, isEmpty);
  });

  test("the unit file has the save's own time, not the time it was made (the play screen compares by it)", () async {
    putSave(List.filled(32768, 5));
    final when = DateTime(2024, 3, 5, 10, 30);
    io.File(p.join(emulatorDir, 'saves', 'Tetris (World).sav')).setLastModifiedSync(when);
    final unit = (await mgba().getSaveFiles(_game('gb'), rom)).single;
    expect(unit.lastModifiedSync(), when);
  });

  test("PCSX2: the game's own save folder gives the time, not another card sigil also read", () async {
    final dir = p.join(tmp.path, 'pcsx2');
    final card = p.join(dir, 'PCSX2', 'memcards', 'Mcd001.ps2');
    ensurePcsx2FolderCard(card);
    final save = io.File(p.join(card, 'BASLUS-20328SAVE', 'SAVE.DAT'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(4000, 6));
    final saved = DateTime(2024, 3, 5, 10, 30);
    save.setLastModifiedSync(saved);
    // Card 2, an 8 MB file card sigil also reads, written later by another game.
    io.File(p.join(dir, 'PCSX2', 'memcards', 'Mcd002.ps2'))
      ..writeAsBytesSync(Ps2MemoryCard.formatted())
      ..setLastModifiedSync(DateTime(2025, 1, 1));
    final game = Game.fromJson({
      ...gameJson(8, 'Game A', fsName: 'Game A (USA).chd'),
      'platform_slug': 'ps2',
      'title_id': 'SLUS-20328',
      'save_target': 'BASLUS-20328',
      'save_target_layout': 'folder-prefix',
    });
    final s = SigilSaveStrategy.forEmulator(
      'pcsx2',
      base: null,
      emulatorDir: () => dir,
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
    )!;
    final unit = (await s.getSaveFiles(game, r'D:\roms\Game A (USA).chd')).single;
    expect(unit.lastModifiedSync(), saved);
  });

  test('the sync state is stored only after the upload, never at collect', () async {
    putSave(List.filled(32768, 5));
    final s = mgba();
    final game = _game('gb');
    await s.getSaveFiles(game, rom);
    expect(states.read('mgba', game.id), isNull);
    await s.afterUpload(game, rom);
    expect(states.read('mgba', game.id), isNotNull);
  });

  group("this PC's newer save is protected", () {
    late List<bool> overwrites;
    SigilSaveStrategy watching({int failWith = 0}) => SigilSaveStrategy.forEmulator(
      'mgba',
      base: base,
      emulatorDir: () => emulatorDir,
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
      restore: (call, unit) async {
        overwrites.add(call.overwriteLocal);
        if (failWith != 0) throw SigilSyncError(failWith, 'conflict');
        return const SigilRestored(state: null, hardcoreMarker: false);
      },
    )!;
    setUp(() => overwrites = []);

    test("an automatic pull never overwrites a local change; a restore you chose does", () async {
      final s = watching();
      await s.restoreSave(_game('gb'), rom, Uint8List(10), 'x.srm');
      await SaveStrategy.chosenRestore(() => s.restoreSave(_game('gb'), rom, Uint8List(10), 'x.srm'));
      expect(overwrites, [false, true]);
    });

    test('a local change met by an automatic pull keeps the local save and says why', () async {
      await expectLater(
        watching(failWith: -9).restoreSave(_game('gb'), rom, Uint8List(10), 'x.srm'),
        throwsA(isA<SaveSyncNotPossibleException>().having((e) => e.message, 'message', contains('this PC'))),
      );
    });

    test(
      "the engine's newer-local guard stays on: the pull needn't finish first unless the old strategy says so",
      () async {
        expect(await watching().pullMustFinishBeforeLaunch(_game('gb'), rom), isFalse);
      },
    );
  });

  test('a unit from RomM is restored through sigil into the save root', () async {
    final s = mgba();
    expect(
      await s.restoreSave(_game('gb'), rom, Uint8List.fromList(List.filled(32768, 8)), 'Tetris (World).srm'),
      isTrue,
    );
    expect(io.File(p.join(emulatorDir, 'saves', 'Tetris (World).sav')).readAsBytesSync(), List.filled(32768, 8));
  });

  test("a backup (a zip of the unit) goes back through sigil, not unzipped into a folder", () async {
    final zip = Archive()..addFile(ArchiveFile.bytes('Tetris (World).srm', List.filled(32768, 3)));
    final s = mgba();
    expect(await s.restoreBackup(_game('gb'), rom, Uint8List.fromList(ZipEncoder().encodeBytes(zip)), 'b.zip'), isTrue);
    expect(io.File(p.join(emulatorDir, 'saves', 'Tetris (World).sav')).readAsBytesSync(), List.filled(32768, 3));
  });

  test("a platform sigil doesn't sync for this emulator (GBA in mGBA) stays with the old strategy", () async {
    final s = mgba();
    await s.getSaveFiles(_game('gba'), r'D:\roms\gba\Game.gba');
    await s.restoreSave(_game('gba'), r'D:\roms\gba\Game.gba', Uint8List(10), 'Game.sav');
    expect(base.calls, ['getSaveFiles gba', 'restoreSave gba']);
    expect(s.uploadSlotFor(_game('gba')), 'freegosy');
  });

  test('a state-capable old strategy keeps its save states (the wrapper is StateSyncCapable)', () async {
    final s = SigilSaveStrategy.forEmulator(
      'pcsx2',
      base: _StateBase(),
      emulatorDir: () => emulatorDir,
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
    )!;
    expect(s, isA<StateSyncCapable>());
    final st = s as StateSyncCapable;
    expect(await st.stateDirectory(_game('ps2'), 'x'), r'C:\states');
    expect((await st.stateFileMatcher(_game('ps2'), 'x'))!('x.p2s'), isTrue);
  });

  test("RomM's ids reach sigil (title_id, save_target and its layout), with the emulator's options", () async {
    SigilSyncCall? seen;
    io.File(p.join(tmp.path, 'emulators', 'pcsx2', 'PCSX2', 'inis', 'PCSX2.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[MemoryCards]\nSlot1_Filename = Mine.ps2\n');
    final s = SigilSaveStrategy.forEmulator(
      'pcsx2',
      base: _StateBase(),
      emulatorDir: () => p.join(tmp.path, 'emulators', 'pcsx2'),
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
      collect: (call) async {
        seen = call;
        return const SigilCollected(
          artifact: 'x',
          data: null,
          contentHash: '',
          identityHash: '',
          changed: false,
          state: null,
          holding: null,
          unowned: [],
          restoreAgain: false,
        );
      },
    )!;
    final game = Game.fromJson({
      ...gameJson(7, 'Ace Combat 5', fsName: 'Ace Combat 5 (USA).chd'),
      'platform_slug': 'ps2',
      'title_id': 'slus_208.51',
      'save_target': 'BASLUS-20851',
      'save_target_layout': 'folder-prefix',
    });
    await s.getSaveFiles(game, r'D:\roms\ps2\Ace Combat 5 (USA).chd');
    expect(seen!.layout, 'pcsx2_standalone');
    expect(seen!.saveRoot, p.join(tmp.path, 'emulators', 'pcsx2', 'PCSX2'));
    expect(seen!.titleId, 'SLUS-20851');
    expect(seen!.gameIds, ['SLUS-20851']);
    expect(seen!.saveId, 'BASLUS-20851');
    expect(seen!.usage, 1);
    expect(seen!.options, {'Slot1_Filename': 'Mine.ps2'});
  });

  test('PCSX2 with no memory card at all: an empty folder card is made, and the save goes onto it', () async {
    SigilSaveStrategy pcsx2(String dir) => SigilSaveStrategy.forEmulator(
      'pcsx2',
      base: null,
      emulatorDir: () => dir,
      states: SigilStateStore(p.join(dir, 'sigil')),
      unitsDir: p.join(dir, 'units'),
    )!;
    final a = p.join(tmp.path, 'a');
    ensurePcsx2FolderCard(p.join(a, 'PCSX2', 'memcards', 'Mcd001.ps2'));
    io.File(p.join(a, 'PCSX2', 'memcards', 'Mcd001.ps2', 'BASLUS-20328SAVE', 'SAVE.DAT'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(4000, 6));
    final game = Game.fromJson({
      ...gameJson(8, 'Game A', fsName: 'Game A (USA).chd'),
      'platform_slug': 'ps2',
      'title_id': 'SLUS-20328',
      'save_target': 'BASLUS-20328',
      'save_target_layout': 'folder-prefix',
    });
    final unit = (await pcsx2(a).getSaveFiles(game, r'D:\roms\Game A (USA).chd')).single;
    final b = p.join(tmp.path, 'b'); // a profile whose card is gone
    expect(await pcsx2(b).restoreSave(game, r'D:\roms\Game A (USA).chd', unit.readAsBytesSync(), 'x.ps2'), isTrue);
    final card = p.join(b, 'PCSX2', 'memcards', 'Mcd001.ps2');
    expect(io.File(p.join(card, '_pcsx2_superblock')).existsSync(), isTrue, reason: 'a folder card');
    expect(io.File(p.join(card, 'BASLUS-20328SAVE', 'SAVE.DAT')).readAsBytesSync(), List.filled(4000, 6));
  });

  group('DuckStation names its card after the game database, not the ROM', () {
    final ff7 = Game.fromJson({
      ...gameJson(11, 'Final Fantasy VII', fsName: 'Final Fantasy VII (USA) (Disc 1).chd'),
      'platform_slug': 'psx',
      'title_id': 'SCUS-94163',
    });
    const disc1 = r'D:\roms\psx\Final Fantasy VII (USA) (Disc 1).chd';
    late String dir;
    SigilSaveStrategy duck() => SigilSaveStrategy.forEmulator(
      'duckstation',
      base: null,
      emulatorDir: () => dir,
      states: SigilStateStore(p.join(tmp.path, 'st')),
      unitsDir: p.join(tmp.path, 'un'),
      content: (game, romPath) async =>
          (root: dir, stem: 'Final Fantasy VII (USA)', options: const {'Card1Type': 'PerGameTitle'}),
    )!;
    setUp(() {
      dir = p.join(tmp.path, 'duckstation');
      io.File(p.join(dir, 'memcards', 'Final Fantasy VII (USA)_1.mcd'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(
          buildPs1Card([
            (name: 'BASCUS-94163FF7', blocks: [1], fill: 0x33),
          ]),
        );
    });

    test("the database-named card is found and collected", () async {
      expect(await duck().getSaveFiles(ff7, disc1), hasLength(1));
    });

    test('and a restore on a new PC writes the card DuckStation will open', () async {
      final unit = (await duck().getSaveFiles(ff7, disc1)).single.readAsBytesSync();
      io.Directory(p.join(dir, 'memcards')).deleteSync(recursive: true);
      await duck().restoreSave(ff7, disc1, unit, 'x.mcd');
      expect(io.File(p.join(dir, 'memcards', 'Final Fantasy VII (USA)_1.mcd')).existsSync(), isTrue);
    });

    test("on disc 2 the saves are found too: they're under disc 1's code, so both ids go to sigil", () async {
      SigilSyncCall? seen;
      final s = SigilSaveStrategy.forEmulator(
        'duckstation',
        base: null,
        emulatorDir: () => dir,
        states: SigilStateStore(p.join(tmp.path, 'st2')),
        unitsDir: p.join(tmp.path, 'un2'),
        identify: (path, {platform}) async => const SigilId(
          titleId: 'SCUS-94164',
          rawSerial: 'SCUS_941.64',
          saveId: 'BASCUS-94164',
          platform: 'psx',
          fromBinary: true,
        ),
        collect: (call) async {
          seen = call;
          return const SigilCollected(
            artifact: 'x',
            data: null,
            contentHash: '',
            identityHash: '',
            changed: false,
            state: null,
            holding: null,
            unowned: [],
            restoreAgain: false,
          );
        },
      )!;
      await s.getSaveFiles(ff7, r'D:\roms\psx\Final Fantasy VII (USA) (Disc 2).chd');
      expect(seen!.titleId, 'SCUS-94164', reason: "this disc's own id");
      expect(seen!.gameIds, containsAll(['SCUS-94163', 'SCUS-94164']));
    });
  });

  test("GameCube: RomM's hex title_id is the game id, its save_target the disc code; the save is found", () async {
    final dir = p.join(tmp.path, 'dolphin');
    final gci = Uint8List(64 + 8192)
      ..setRange(0, 4, 'GZLE'.codeUnits)
      ..setRange(4, 6, '01'.codeUnits)
      ..[6] = 0xFF
      ..setRange(8, 16, 'gczelda2'.codeUnits)
      ..[0x39] = 1;
    io.File(p.join(dir, 'GC', 'USA', 'Card A', '01-GZLE-gczelda2.gci'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(gci);
    final zelda = Game.fromJson({
      ...gameJson(12, 'Zelda', fsName: 'Zelda (USA).rvz'),
      'platform_slug': 'ngc',
      'title_id': '475A4C45',
      'save_target': 'GZLE',
      'save_target_layout': 'file-prefix',
    });
    final s = SigilSaveStrategy.forEmulator(
      'dolphin',
      base: null,
      emulatorDir: () => dir,
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
    )!;
    expect(await s.getSaveFiles(zelda, r'D:\roms\ngc\Zelda (USA).rvz'), hasLength(1));
  });

  test("PSP: RomM's id as it may send it (ULUS-10064, no save_target) becomes the save folder prefix", () async {
    SigilSyncCall? seen;
    final s = SigilSaveStrategy.forEmulator(
      'ppsspp',
      base: null,
      emulatorDir: () => emulatorDir,
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
      collect: (call) async {
        seen = call;
        return const SigilCollected(
          artifact: 'x',
          data: null,
          contentHash: '',
          identityHash: '',
          changed: false,
          state: null,
          holding: null,
          unowned: [],
          restoreAgain: false,
        );
      },
    )!;
    final game = Game.fromJson({
      ...gameJson(13, 'Daxter', fsName: 'Daxter (USA).iso'),
      'platform_slug': 'psp',
      'title_id': 'ULUS-10064',
    });
    await s.getSaveFiles(game, r'D:\roms\psp\Daxter (USA).iso');
    expect((seen!.titleId, seen!.saveId, seen!.usage), ('ULUS10064', 'ULUS10064', 1));
    expect(seen!.gameIds, ['ULUS10064']);
  });

  test("the old strategy's zipping stays for the games it keeps (Wii in Dolphin zips as before)", () {
    final zipping = _Base(); // SaveStrategy's default: zip
    expect(
      SigilSaveStrategy.forEmulator(
        'dolphin',
        base: zipping,
        emulatorDir: () => '',
        states: states,
        unitsDir: '',
      )!.shouldZip,
      isTrue,
    );
  });

  test('a backup made before sigil (a zip of save folders) goes back whole, as sigil reads that shape', () async {
    final dir = p.join(tmp.path, 'ppsspp');
    final old = Archive()
      ..addFile(ArchiveFile.bytes('ULUS10064DATA00/PARAM.SFO', List.filled(4096, 3)))
      ..addFile(ArchiveFile.bytes('ULUS10064DATA00/DATA.BIN', List.filled(20000, 4)));
    final daxter = Game.fromJson({
      ...gameJson(14, 'Daxter', fsName: 'Daxter (USA).iso'),
      'platform_slug': 'psp',
      'title_id': 'ULUS10064',
      'save_target': 'ULUS10064',
      'save_target_layout': 'folder-prefix',
    });
    final s = SigilSaveStrategy.forEmulator(
      'ppsspp',
      base: null,
      emulatorDir: () => dir,
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
    )!;
    expect(
      await s.restoreBackup(
        daxter,
        r'D:\roms\psp\Daxter (USA).iso',
        Uint8List.fromList(ZipEncoder().encodeBytes(old)),
        'b.zip',
      ),
      isTrue,
    );
    expect(
      io.File(p.join(dir, 'PSP', 'SAVEDATA', 'ULUS10064DATA00', 'DATA.BIN')).readAsBytesSync(),
      List.filled(20000, 4),
    );
  });

  test("a collect sigil refuses (a damaged card) is said, not a silent 'nothing to upload'", () async {
    final s = SigilSaveStrategy.forEmulator(
      'mgba',
      base: base,
      emulatorDir: () => emulatorDir,
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
      collect: (call) async => throw const SigilSyncError(-13, 'damaged', problem: 'Tetris (World).sav'),
    )!;
    await expectLater(
      s.getSaveFiles(_game('gb'), rom),
      throwsA(isA<SaveSyncNotPossibleException>().having((e) => e.message, 'message', contains('damaged'))),
    );
  });

  test('Flycast, which had no save strategy, gets one (Dreamcast only)', () {
    final s = SigilSaveStrategy.forEmulator(
      'flycast',
      base: null,
      emulatorDir: () => emulatorDir,
      states: states,
      unitsDir: p.join(tmp.path, 'u'),
    );
    expect(s, isNotNull);
    expect(
      SigilSaveStrategy.forEmulator('retroarch', base: base, emulatorDir: () => '', states: states, unitsDir: ''),
      isNull,
    );
  });
}
