import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/widgets/ico_png.dart';

const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// An .ico with the given entries: (width, bytes).
Uint8List ico(List<(int, List<int>)> entries) {
  final b = BytesBuilder()..add([0, 0, 1, 0, entries.length, 0]);
  var offset = 6 + 16 * entries.length;
  for (final (w, data) in entries) {
    final dir = ByteData(16)
      ..setUint8(0, w == 256 ? 0 : w)
      ..setUint8(1, w == 256 ? 0 : w)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, data.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    b.add(dir.buffer.asUint8List());
    offset += data.length;
  }
  for (final (_, data) in entries) {
    b.add(data);
  }
  return b.toBytes();
}

void main() {
  test("RomM's icons: the one PNG inside", () {
    final png = [..._png, 1, 2, 3];
    expect(pngFromIco(ico([(256, png)])), png);
  });

  test('several sizes: the largest PNG', () {
    final small = [..._png, 16];
    final big = [..._png, 99];
    expect(
      pngFromIco(
        ico([
          (16, small),
          (256, big),
          (48, [..._png, 48]),
        ]),
      ),
      big,
    );
  });

  test('only old-style bitmaps, or not an .ico at all: none', () {
    expect(pngFromIco(ico([(32, List.filled(40, 0))])), isNull);
    expect(pngFromIco(Uint8List.fromList('<html>'.codeUnits)), isNull);
    expect(pngFromIco(Uint8List(3)), isNull);
  });

  test('an entry pointing past the end is skipped', () {
    final bad = ico([
      (256, [..._png, 1]),
    ]);
    ByteData.view(bad.buffer).setUint32(6 + 8, 9999, Endian.little);
    expect(pngFromIco(bad), isNull);
  });
}
