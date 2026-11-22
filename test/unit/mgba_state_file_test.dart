import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/strategies/mgba_state_file.dart';

/// A raw state's head: [magic] little-endian, then four zero bytes.
Uint8List _raw(int magic) {
  final head = ByteData(8)..setUint32(0, magic, Endian.little);
  return head.buffer.asUint8List();
}

final _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  group('MgbaStateFile.isPng', () {
    test('true for a state with its screenshot (the PNG signature)', () {
      expect(MgbaStateFile.isPng(Uint8List.fromList([..._pngSignature, 0, 0, 0, 13])), isTrue);
    });

    test('false for a raw state, a short head or a broken signature', () {
      expect(MgbaStateFile.isPng(_raw(0x01000001)), isFalse);
      expect(MgbaStateFile.isPng(Uint8List.fromList(_pngSignature.sublist(0, 7))), isFalse);
      expect(MgbaStateFile.isPng(Uint8List.fromList([..._pngSignature]..[7] = 0)), isFalse);
      expect(MgbaStateFile.isPng(Uint8List(0)), isFalse);
    });
  });

  group('MgbaStateFile.looksValid', () {
    test('a PNG state, or a raw GBA or GB state of any version', () {
      expect(MgbaStateFile.looksValid(Uint8List.fromList(_pngSignature)), isTrue);
      expect(MgbaStateFile.looksValid(_raw(0x01000000)), isTrue);
      expect(MgbaStateFile.looksValid(_raw(0x01000007)), isTrue);
      expect(MgbaStateFile.looksValid(_raw(0x00400000)), isTrue);
      expect(MgbaStateFile.looksValid(_raw(0x00400002)), isTrue);
    });

    test('not another magic, a big-endian magic or fewer than 4 bytes', () {
      expect(MgbaStateFile.looksValid(_raw(0x02000000)), isFalse);
      expect(MgbaStateFile.looksValid(Uint8List.fromList([0x01, 0x00, 0x00, 0x00])), isFalse);
      expect(MgbaStateFile.looksValid(Uint8List.fromList([0x00, 0x00, 0x00])), isFalse);
      expect(MgbaStateFile.looksValid(Uint8List(0)), isFalse);
    });
  });
}
