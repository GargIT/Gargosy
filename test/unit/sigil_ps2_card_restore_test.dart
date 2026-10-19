// A PS2 memory card file through sigil, collect then restore: sigil reads the
// card back after writing it, and an MSVC-optimized card_ps2.c failed that
// check every time (windows/sigil_msvc.cmake).
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/formats/ps2_memory_card.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:gargosy/sigil/sigil_sync.dart';
import 'package:path/path.dart' as p;

void main() {
  late io.Directory tmp;
  setUp(() => tmp = io.Directory.systemTemp.createTempSync('gargosy-sigil-ps2-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Uint8List data(int seed) => Uint8List.fromList([for (var i = 0; i < 3000; i++) (seed * 31 + i) & 0xFF]);
  Uint8List card(List<(String, int)> saves) => Ps2MemoryCard.parse(Ps2MemoryCard.formatted()).withSaves([
    for (final (name, seed) in saves)
      Ps2CardSave(
        name: name,
        files: [Ps2CardFile(name: 'SAVE.DAT', data: data(seed))],
      ),
  ], (_) => false);
  io.Directory root(String name) => io.Directory(p.join(tmp.path, name))..createSync(recursive: true);
  void put(io.Directory r, Uint8List bytes) =>
      (io.File(p.join(r.path, 'memcards', 'Mcd001.ps2'))..createSync(recursive: true)).writeAsBytesSync(bytes);
  SigilSyncCall pcsx2(io.Directory r) => SigilSyncCall(
    layout: 'pcsx2_standalone',
    platform: 'ps2',
    contentPath: r'D:\roms\ps2\Game A (USA).chd',
    saveRoot: r.path,
    gameIds: const ['SLUS-20328'],
    titleId: 'SLUS-20328',
    saveId: 'BASLUS-20328',
    usage: 1,
    options: const {'pcsx2_slot1': 'Mcd001.ps2'},
    overwriteLocal: true,
  );

  test("a shared card's save goes to another PC's card, and that card's other game stays", () async {
    final a = root('a');
    put(a, card([('BASLUS-20328SAVE', 1), ('BESLES-50123OTHER', 2)]));
    final got = await SigilEngine.collect(pcsx2(a));
    expect(got.data, isNotNull);

    final b = root('b');
    put(b, card([('BASLUS-20328SAVE', 9), ('BASLUS-20999THIRD', 3)]));
    await SigilEngine.restore(pcsx2(b), got.data!);
    final after = Ps2MemoryCard.parse(io.File(p.join(b.path, 'memcards', 'Mcd001.ps2')).readAsBytesSync());
    expect(after.saves.map((s) => s.name).toSet(), {'BASLUS-20328SAVE', 'BASLUS-20999THIRD'});
    expect(after.saves.firstWhere((s) => s.name == 'BASLUS-20328SAVE').files.single.data, data(1));
  });
}
