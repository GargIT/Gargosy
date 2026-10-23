import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/dsi_title.dart';
import 'package:path/path.dart' as p;

/// A header with [unit] at 0x12, [regions] at 0x1B0 and [titleHigh] at 0x234.
Uint8List header({int unit = 3, int regions = 0x02, int titleHigh = 0x00030004}) {
  final h = Uint8List(0x1000);
  final d = ByteData.sublistView(h);
  h[0x12] = unit;
  d.setUint32(0x1B0, regions, Endian.little);
  d.setUint32(0x234, titleHigh, Endian.little);
  return h;
}

void main() {
  test("DSiWare and its regions (Zuma's Revenge: KZTV Europe and Australia, KZTE USA)", () {
    final eur = parseDsiHeader(header(regions: 0x0C))!;
    expect(eur.dsiWare, isTrue);
    expect(eur.regions, ['Europe', 'Australia']);
    expect(parseDsiHeader(header())!.regions, ['USA']);
    expect(dsiRegionLine(eur.regions), 'Europe or Australia');
    expect(dsiRegionLine(['USA', 'Europe', 'Australia']), 'USA, Europe or Australia');
  });

  test('a DSi cartridge is not DSiWare; a DS game is no DSi title; region free has no regions', () {
    expect(parseDsiHeader(header(titleHigh: 0x00030000))!.dsiWare, isFalse);
    expect(parseDsiHeader(header(unit: 0)), isNull);
    expect(parseDsiHeader(header(regions: 0xFFFFFFFF))!.regions, isEmpty);
    expect(parseDsiHeader(Uint8List(0x100)), isNull);
  });

  group('readDsiTitle', () {
    late io.Directory dir;
    setUp(() => dir = io.Directory.systemTemp.createTempSync('dsi_title'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a ROM file, a folder holding one, and a zip holding one', () async {
      final rom = io.File(p.join(dir.path, 'Game', 'Game.nds'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(header(regions: 0x0C));
      expect((await readDsiTitle(rom.path))!.regions, ['Europe', 'Australia']);
      expect((await readDsiTitle(rom.parent.path))!.dsiWare, isTrue);

      final zip = io.File(p.join(dir.path, 'Game.zip'))
        ..writeAsBytesSync(ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('Game.nds', header()))));
      expect((await readDsiTitle(zip.path))!.regions, ['USA']);
    });

    test("nothing there, or not a ROM: null", () async {
      expect(await readDsiTitle(p.join(dir.path, 'missing.nds')), isNull);
      final txt = io.File(p.join(dir.path, 'readme.txt'))..writeAsStringSync('hi');
      expect(await readDsiTitle(txt.path), isNull);
    });
  });
}
