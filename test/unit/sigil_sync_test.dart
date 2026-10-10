import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/pcsx2_folder_card.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:gargosy/sigil/sigil_sync.dart';
import 'package:path/path.dart' as p;

import '../helpers/ps1_card_builder.dart';

Uint8List pattern(int seed, int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (seed * 31 + i) & 0xFF]);

void main() {
  late io.Directory tmp;
  setUp(() => tmp = io.Directory.systemTemp.createTempSync('gargosy-sigilsync-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  io.Directory root(String name) => io.Directory(p.join(tmp.path, name))..createSync(recursive: true);
  void put(io.Directory dir, String rel, List<int> bytes) => io.File(p.join(dir.path, rel))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  Uint8List read(io.Directory dir, String rel) => io.File(p.join(dir.path, rel)).readAsBytesSync();

  group('mGBA (Game Boy): one .sav', () {
    SigilSyncCall call(io.Directory r, {Uint8List? state}) => SigilSyncCall(
      layout: 'mgba_standalone',
      platform: 'gb',
      contentPath: r'D:\roms\gb\Tetris (World).gb',
      saveRoot: r.path,
      state: state,
    );

    test('collect gives the save as the unit; restore writes it; unchanged the second time', () async {
      final a = root('a');
      put(a, 'Tetris (World).sav', pattern(1, 32768));
      final collected = await SigilEngine.collect(call(a));
      expect(collected.artifact, 'Tetris (World).srm'); // the name RomM and Argosy use; restore writes mGBA's .sav
      expect(collected.data, pattern(1, 32768));
      expect(collected.contentHash, hasLength(32));
      expect(collected.changed, isTrue);

      final b = root('b');
      final restored = await SigilEngine.restore(call(b), collected.data!);
      expect(read(b, 'Tetris (World).sav'), pattern(1, 32768));
      expect(restored.state, isNotNull);

      final again = await SigilEngine.collect(call(a, state: collected.state));
      expect(again.changed, isFalse);
    });

    test('the collect says when the files it read were last written', () async {
      final a = root('a');
      put(a, 'Tetris (World).sav', pattern(1, 32768));
      final when = DateTime(2024, 3, 5, 10, 30);
      io.File(p.join(a.path, 'Tetris (World).sav')).setLastModifiedSync(when);
      expect((await SigilEngine.collect(call(a))).newestRead, when);
    });

    test('no save there: no unit', () async {
      final collected = await SigilEngine.collect(call(root('empty')));
      expect(collected.data, isNull);
    });
  });

  test("DuckStation (PS1): the game's card is the unit, and goes back into another profile", () async {
    final a = root('a');
    final card = buildPs1Card([
      (name: 'BESLES-02605CMR2', blocks: [1], fill: 0x42),
    ]);
    put(a, 'memcards/Colin McRae Rally 2.0 (Europe)_1.mcd', card);
    SigilSyncCall call(io.Directory r) => SigilSyncCall(
      layout: 'duckstation',
      platform: 'psx',
      contentPath: r'D:\roms\psx\Colin McRae Rally 2.0 (Europe).chd',
      saveRoot: r.path,
      gameIds: const ['SLES-02605'],
      titleId: 'SLES-02605',
    );
    final collected = await SigilEngine.collect(call(a));
    expect(collected.data, isNotNull);
    expect(collected.data!.length, 128 * 1024);
    final b = root('b');
    await SigilEngine.restore(call(b), collected.data!);
    expect(io.Directory(p.join(b.path, 'memcards')).listSync(), isNotEmpty);
  });

  group('PCSX2: a folder card with two games', () {
    late io.Directory r;
    const a = 'memcards/Mcd001.ps2/BASLUS-20328SAVE';
    const b = 'memcards/Mcd001.ps2/BESLES-50123OTHER';
    SigilSyncCall call({Uint8List? state, bool overwrite = false}) => SigilSyncCall(
      layout: 'pcsx2_standalone',
      platform: 'ps2',
      contentPath: r'D:\roms\ps2\Game A (USA).chd',
      saveRoot: r.path,
      gameIds: const ['SLUS-20328'],
      titleId: 'SLUS-20328',
      saveId: 'BASLUS-20328',
      usage: 1, // folder-prefix
      state: state,
      overwriteLocal: overwrite,
    );

    setUp(() {
      r = root('pcsx2');
      ensurePcsx2FolderCard(p.join(r.path, 'memcards', 'Mcd001.ps2'));
      put(r, '$a/SAVE.DAT', pattern(1, 4000));
      put(r, '$a/icon.sys', pattern(2, 964));
      put(r, '$b/SAVE.DAT', pattern(7, 5000));
    });

    test("restoring game A's older save leaves game B's untouched", () async {
      final first = await SigilEngine.collect(call());
      expect(first.data, isNotNull);
      put(r, '$a/SAVE.DAT', pattern(9, 4000)); // played on
      await SigilEngine.restore(call(state: first.state, overwrite: true), first.data!);
      expect(read(r, '$a/SAVE.DAT'), pattern(1, 4000));
      expect(read(r, '$b/SAVE.DAT'), pattern(7, 5000));
    });

    test('a local change since the last sync is a conflict unless told to overwrite; nothing written', () async {
      final first = await SigilEngine.collect(call());
      put(r, '$a/SAVE.DAT', pattern(9, 4000));
      await expectLater(
        SigilEngine.restore(call(state: first.state), first.data!),
        throwsA(isA<SigilSyncError>().having((e) => e.code, 'code', -9)),
      );
      expect(read(r, '$a/SAVE.DAT'), pattern(9, 4000));
    });
  });

  test("PPSSPP: the game's SAVEDATA folders, zipped", () async {
    final a = root('a');
    put(a, 'PSP/SAVEDATA/ULUS10064DATA00/PARAM.SFO', pattern(3, 4096));
    put(a, 'PSP/SAVEDATA/ULUS10064DATA00/DATA.BIN', pattern(4, 20000));
    put(a, 'PSP/SAVEDATA/NPUH10000OTHER/DATA.BIN', pattern(5, 100));
    SigilSyncCall call(io.Directory r) => SigilSyncCall(
      layout: 'ppsspp_standalone',
      platform: 'psp',
      contentPath: r'D:\roms\psp\Game.iso',
      saveRoot: r.path,
      gameIds: const ['ULUS10064'],
      titleId: 'ULUS10064',
      saveId: 'ULUS10064',
      usage: 1,
    );
    final collected = await SigilEngine.collect(call(a));
    final names = ZipDecoder().decodeBytes(collected.data!).files.where((f) => f.isFile).map((f) => f.name).toSet();
    expect(names, {'ULUS10064DATA00/PARAM.SFO', 'ULUS10064DATA00/DATA.BIN'});
    final b = root('b');
    await SigilEngine.restore(call(b), collected.data!);
    expect(read(b, 'PSP/SAVEDATA/ULUS10064DATA00/DATA.BIN'), pattern(4, 20000));
  });

  test("Dolphin (GameCube): the game's .gci files from the GCI folder, others left alone", () async {
    Uint8List gci(String code, String name, int fill) {
      final b = Uint8List(64 + 8192)..fillRange(64, 64 + 8192, fill);
      b.setRange(0, 4, code.codeUnits);
      b.setRange(4, 6, '01'.codeUnits);
      b[6] = 0xFF;
      b.setRange(8, 8 + name.length, name.codeUnits);
      b[0x39] = 1; // one block (big-endian u16 at 0x38)
      return b;
    }

    final a = root('a');
    put(a, 'GC/USA/Card A/01-GZLE-gczelda2.gci', gci('GZLE', 'gczelda2', 0x11));
    put(a, 'GC/USA/Card A/01-GALE-SuperSmash.gci', gci('GALE', 'SuperSmash', 0x22));
    SigilSyncCall call(io.Directory r) => SigilSyncCall(
      layout: 'dolphin_standalone',
      platform: 'gamecube',
      contentPath: r'D:\roms\ngc\Zelda (USA).rvz',
      saveRoot: r.path,
      gameIds: const ['GZLE'],
      titleId: '475A4C45',
      rawSerial: 'GZLE',
      saveId: 'GZLE',
      usage: 3, // file-prefix
    );
    final collected = await SigilEngine.collect(call(a));
    expect(collected.data, isNotNull);
    expect(collected.data!.sublist(0, 4), 'GZLE'.codeUnits, reason: 'one .gci travels raw');
    final b = root('b');
    await SigilEngine.restore(call(b), collected.data!);
    final written = io.Directory(p.join(b.path, 'GC', 'USA', 'Card A')).listSync().map((e) => p.basename(e.path));
    expect(written, ['01-GZLE-gczelda2.gci']);
  });

  test('the callbacks never reach outside the save root', () {
    final r = p.join(tmp.path, 'root');
    expect(sigilRootPath(r, 'memcards/Mcd001.ps2'), p.join(r, 'memcards', 'Mcd001.ps2'));
    expect(sigilRootPath(r, '../evil.txt'), isNull);
    expect(sigilRootPath(r, 'a/../../evil.txt'), isNull);
    expect(sigilRootPath(r, r'C:\Windows\evil.txt'), isNull);
    expect(sigilRootPath(r, '/etc/passwd'), isNull);
  });
}
