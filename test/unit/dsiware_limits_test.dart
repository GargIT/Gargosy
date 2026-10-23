import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/play/dsiware_limits.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';

void main() {
  late io.Directory dir;
  setUp(() => dir = io.Directory.systemTemp.createTempSync('dsiware_limits'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A ROM whose header is DSi only (unit 3) with the title id's high word [titleHigh].
  String rom(String name, int titleHigh) {
    final h = Uint8List(0x1000);
    h[0x12] = 3;
    ByteData.sublistView(h).setUint32(0x234, titleHigh, Endian.little);
    return (io.File(p.join(dir.path, name))..writeAsBytesSync(h)).path;
  }

  test("DSiWare isn't played in melonDS (it can't keep the save); a DSi cartridge is", () async {
    final dsiWare = rom('Zuma.nds', 0x00030004);
    final cartridge = rom('Cart.nds', 0x00030000);
    expect(await emulatorsUnfitFor(game(1, 'Zuma', platform: 'nintendo-dsi'), dsiWare), {'melonds'});
    expect(await emulatorsUnfitFor(game(1, 'Zuma', platform: 'nds'), dsiWare), {'melonds'});
    expect(await emulatorsUnfitFor(game(2, 'Cart', platform: 'nintendo-dsi'), cartridge), isEmpty);
  });

  test('another platform, or no ROM on this PC: nothing is left out', () async {
    expect(await emulatorsUnfitFor(game(1, 'Zuma', platform: 'ps2'), rom('Zuma.nds', 0x00030004)), isEmpty);
    expect(await emulatorsUnfitFor(game(1, 'Zuma', platform: 'nintendo-dsi'), null), isEmpty);
  });
}
