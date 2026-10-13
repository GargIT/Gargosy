// Step 1 of issue #7: what sigil does with RetroArch's saves, on real files.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/formats/ps2_memory_card.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:gargosy/sigil/sigil_sync.dart';
import 'package:path/path.dart' as p;

import '../helpers/ps1_card_builder.dart';

Uint8List pattern(int seed, int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (seed * 31 + i) & 0xFF]);

/// [raw] as RetroArch's `save_file_compression` writes it (RZIP, deflate).
Uint8List rzip(Uint8List raw, {int chunk = 128 * 1024}) {
  final out = BytesBuilder()
    ..add('#RZIPv'.codeUnits)
    ..addByte(1)
    ..addByte('#'.codeUnitAt(0));
  final head = ByteData(12)
    ..setUint32(0, chunk, Endian.little)
    ..setUint64(4, raw.length, Endian.little);
  out.add(head.buffer.asUint8List());
  for (var at = 0; at < raw.length; at += chunk) {
    final part = raw.sublist(at, at + chunk > raw.length ? raw.length : at + chunk);
    final z = const ZLibEncoder().encode(part);
    out.add((ByteData(4)..setUint32(0, z.length, Endian.little)).buffer.asUint8List());
    out.add(z);
  }
  return out.toBytes();
}

/// A 32 KB Game Boy Color ROM header for MBC3 with a clock and battery
/// (cart type 0x10), as Pokémon Crystal has: sigil reads the clock from it.
Uint8List gbcRomWithClock() {
  final rom = Uint8List(32768);
  const logo = [
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D, //
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99, //
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
  ];
  rom.setAll(0x104, logo);
  rom.setAll(0x134, 'PM_CRYSTAL'.codeUnits);
  rom[0x143] = 0xC0; // CGB only
  rom[0x147] = 0x10; // MBC3 + timer + RAM + battery
  rom[0x148] = 0x06;
  rom[0x149] = 0x03; // 32 KB RAM
  var check = 0;
  for (var i = 0x134; i <= 0x14C; i++) {
    check = (check - rom[i] - 1) & 0xFF;
  }
  rom[0x14D] = check;
  return rom;
}

void main() {
  late io.Directory tmp;
  setUp(() => tmp = io.Directory.systemTemp.createTempSync('gargosy-sigil-ra-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  io.Directory root(String name) => io.Directory(p.join(tmp.path, name))..createSync(recursive: true);
  void put(io.Directory dir, String rel, List<int> bytes) => io.File(p.join(dir.path, rel))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  Uint8List read(io.Directory dir, String rel) => io.File(p.join(dir.path, rel)).readAsBytesSync();
  List<String> files(io.Directory dir) =>
      dir.listSync(recursive: true).whereType<io.File>().map((f) => p.relative(f.path, from: dir.path)).toList()..sort();

  SigilSyncCall call(String layout, String platform, String content, io.Directory r,
          {Map<String, String> options = const {}, List<String> ids = const [], String? titleId, Uint8List? state}) =>
      SigilSyncCall(
        layout: layout,
        platform: platform,
        contentPath: content,
        saveRoot: r.path,
        gameIds: ids,
        titleId: titleId,
        options: options,
        state: state,
      );

  // sigil's sync covers the systems in docs/sync.md's "What syncs"; other
  // platforms are refused, and RetroArch keeps its own strategy for them.
  for (final (layout, platform, rom) in [
    ('snes9x', 'snes', r'D:\roms\snes\Super Metroid.sfc'),
    ('mgba', 'gba', r'D:\roms\gba\Golden Sun.gba'),
    ('genesis_plus_gx', 'genesis', r'D:\roms\genesis\Phantasy Star IV.md'),
    ('fceumm', 'nes', r'D:\roms\nes\Zelda.nes'),
    ('melonds', 'nds', r'D:\roms\nds\Mario.nds'),
    ('fbneo', 'arcade', r'D:\roms\arcade\sf2.zip'),
  ]) {
    test('$layout ($platform): refused by sigil (unsupported format)', () async {
      final a = root('a');
      put(a, '${p.basenameWithoutExtension(rom.split(r'\').last)}.srm', pattern(3, 8192));
      await expectLater(SigilEngine.collect(call(layout, platform, rom, a)),
          throwsA(isA<SigilSyncError>().having((e) => e.code, 'code', -4)));
    });
  }

  for (final layout in ['gambatte', 'sameboy', 'mgba', 'some_new_core']) {
    test('$layout (gb): <stem>.srm is the unit, restored under the same name', () async {
      final a = root('a');
      put(a, 'Tetris.srm', pattern(3, 8192));
      final got = await SigilEngine.collect(call(layout, 'gb', r'D:\roms\gb\Tetris.gb', a));
      expect(got.artifact, 'Tetris.srm');
      expect(got.data, pattern(3, 8192));
      final b = root('b');
      await SigilEngine.restore(call(layout, 'gb', r'D:\roms\gb\Tetris.gb', b), got.data!);
      expect(files(b), ['Tetris.srm']);
      expect(read(b, 'Tetris.srm'), pattern(3, 8192));
    });
  }

  test("other games' saves in saves\\ are never taken", () async {
    final a = root('a');
    put(a, 'Tetris.srm', pattern(1, 8192));
    put(a, 'Kirby.srm', pattern(2, 8192));
    final got = await SigilEngine.collect(call('gambatte', 'gb', r'D:\roms\gb\Tetris.gb', a));
    expect(got.data, pattern(1, 8192));
  });

  test('an RZIP save (save_file_compression): the raw save, the same hash; restore writes it plain', () async {
    final a = root('a');
    final raw = pattern(5, 32768);
    put(a, 'Tetris.srm', rzip(raw));
    final got = await SigilEngine.collect(call('gambatte', 'gb', r'D:\roms\gb\Tetris.gb', a));
    expect(got.data, raw);
    final plain = root('plain');
    put(plain, 'Tetris.srm', raw);
    expect((await SigilEngine.collect(call('gambatte', 'gb', r'D:\roms\gb\Tetris.gb', plain))).contentHash, got.contentHash);
    final b = root('b');
    await SigilEngine.restore(call('gambatte', 'gb', r'D:\roms\gb\Tetris.gb', b), got.data!);
    expect(read(b, 'Tetris.srm'), raw);
  });

  test('a zip ROM: the save is named after the member, as RetroArch does', () async {
    final a = root('a');
    put(a, 'Tetris (World).srm', pattern(4, 8192));
    final got = await SigilEngine.collect(call('gambatte', 'gb', r'D:\roms\gb\tetris.zip#Tetris (World).gb', a));
    expect(got.artifact, 'Tetris (World).srm');
    expect(got.data, pattern(4, 8192));
  });

  test('a Game Boy Color cart with a clock: the unit holds the RAM and the clock; restore writes .srm and .rtc', () async {
    final rom = io.File(p.join(tmp.path, 'Pokemon Crystal.gbc'))..writeAsBytesSync(gbcRomWithClock());
    final a = root('a');
    put(a, 'Pokemon Crystal.srm', pattern(6, 32768));
    put(a, 'Pokemon Crystal.rtc', pattern(7, 8));
    final got = await SigilEngine.collect(call('gambatte', 'gbc', rom.path, a));
    expect(got.artifact, 'Pokemon Crystal.zip');
    expect(ZipDecoder().decodeBytes(got.data!).files.map((f) => f.name).toSet(), {'save.sram', 'clock.rtc'});
    final b = root('b');
    await SigilEngine.restore(call('gambatte', 'gbc', rom.path, b), got.data!);
    expect(files(b), ['Pokemon Crystal.rtc', 'Pokemon Crystal.srm']);
    expect(read(b, 'Pokemon Crystal.srm'), pattern(6, 32768));
  });

  test("N64 (mupen64plus_next): the unit is sigil's zip of save types; restore writes <stem>.srm back", () async {
    final a = root('a');
    final srm = pattern(8, 296960); // eeprom + 4 paks + sram + flash, as Mupen64Plus-Next's .srm
    put(a, 'Paper Mario (USA).srm', srm);
    final got = await SigilEngine.collect(call('mupen64plus_next', 'n64', r'D:\roms\n64\Paper Mario (USA).z64', a));
    expect(got.artifact, 'Paper Mario (USA).zip');
    expect(ZipDecoder().decodeBytes(got.data!).files.map((f) => f.name).toSet(),
        {'eeprom', 'pak1', 'pak2', 'pak3', 'pak4', 'sram', 'flash'});
    final b = root('b');
    await SigilEngine.restore(call('mupen64plus_next', 'n64', r'D:\roms\n64\Paper Mario (USA).z64', b), got.data!);
    expect(files(b), ['Paper Mario (USA).srm']);
    expect(read(b, 'Paper Mario (USA).srm'), srm);
  });

  test("pcsx_rearmed (PS1): the game's card <stem>.srm", () async {
    final a = root('a');
    final card = buildPs1Card([(name: 'BASLUS-00594FF7', blocks: [1], fill: 0x33)]);
    put(a, 'Final Fantasy VII (USA) (Disc 1).srm', card);
    final c = call('pcsx_rearmed', 'psx', r'D:\roms\psx\Final Fantasy VII (USA) (Disc 1).chd', a,
        ids: const ['SLUS-00594'], titleId: 'SLUS-00594');
    final got = await SigilEngine.collect(c);
    expect(got.data, isNotNull);
    final b = root('b');
    await SigilEngine.restore(
        call('pcsx_rearmed', 'psx', r'D:\roms\psx\Final Fantasy VII (USA) (Disc 1).chd', b,
            ids: const ['SLUS-00594'], titleId: 'SLUS-00594'),
        got.data!);
    expect(files(b), ['Final Fantasy VII (USA) (Disc 1).srm']);
  });

  group('LRPS2 (layout pcsx2): cards in system\\pcsx2\\memcards', () {
    Uint8List cardWith(List<(String, int)> saves) => Ps2MemoryCard.parse(Ps2MemoryCard.formatted()).withSaves([
          for (final (name, seed) in saves)
            Ps2CardSave(name: name, files: [Ps2CardFile(name: 'SAVE.DAT', data: pattern(seed, 3000))]),
        ], (_) => false);
    SigilSyncCall lrps2(io.Directory r, {Map<String, String> options = const {}, Uint8List? state, bool overwrite = false}) =>
        SigilSyncCall(
          layout: 'pcsx2',
          platform: 'ps2',
          contentPath: r'D:\roms\ps2\Game A (USA).chd',
          saveRoot: r.path,
          gameIds: const ['SLUS-20328'],
          titleId: 'SLUS-20328',
          saveId: 'BASLUS-20328',
          usage: 1,
          options: options,
          state: state,
          overwriteLocal: overwrite,
        );

    test('shared card (the default): only this game travels; restore leaves the other game alone', () async {
      final a = root('a');
      put(a, 'Mcd001.ps2', cardWith([('BASLUS-20328SAVE', 1), ('BESLES-50123OTHER', 2)]));
      final got = await SigilEngine.collect(lrps2(a));
      expect(got.data, isNotNull);
      final unitCard = Ps2MemoryCard.parse(got.data!);
      expect(unitCard.saves.map((s) => s.name), ['BASLUS-20328SAVE']);

      // Another PC: its shared card has a third game and an older save of A.
      final b = root('b');
      put(b, 'Mcd001.ps2', cardWith([('BASLUS-20328SAVE', 9), ('BASLUS-20999THIRD', 3)]));
      await SigilEngine.restore(lrps2(b, overwrite: true), got.data!);
      final after = Ps2MemoryCard.parse(read(b, 'Mcd001.ps2'));
      expect(after.saves.map((s) => s.name).toSet(), {'BASLUS-20328SAVE', 'BASLUS-20999THIRD'});
      expect(after.saves.firstWhere((s) => s.name == 'BASLUS-20328SAVE').files.single.data, pattern(1, 3000));
    });

    test('per-game cards (pcsx2_shared_memory_cards=disabled): <stem>.ps2', () async {
      final a = root('a');
      put(a, 'Game A (USA).ps2', cardWith([('BASLUS-20328SAVE', 1)]));
      final got = await SigilEngine.collect(lrps2(a, options: const {'pcsx2_shared_memory_cards': 'disabled'}));
      expect(got.data, isNotNull);
      final b = root('b');
      await SigilEngine.restore(lrps2(b, options: const {'pcsx2_shared_memory_cards': 'disabled'}), got.data!);
      expect(files(b), ['Game A (USA).ps2']);
    });
  });
}
