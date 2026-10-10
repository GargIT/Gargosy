import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/sigil/sigil_bindings.dart';

void main() {
  test('sigil_result has the layout MSVC gives it (x64)', () => expect(sizeOf<SigilResult>(), 220));

  test("the error codes are sigil.h's", () {
    expect(
      [sigilOk, sigilErrNotFound, sigilErrConflict, sigilErrDamaged, sigilErrKeysIncompatible],
      [0, -5, -9, -13, -17],
    );
  });

  test('the text fields read up to the first NUL, and the field offsets are right', () {
    final r = calloc<SigilResult>();
    addTearDown(() => calloc.free(r));
    final bytes = r.cast<Uint8>();
    void put(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes[offset + i] = text.codeUnitAt(i);
      }
    }

    put(4, 'SLUS-20328'); // title_id
    put(36, 'SLUS_203.28'); // raw_serial
    put(68, 'BASLUS-20328'); // save_id
    bytes[104] = 1; // source: filename
    expect(r.ref.titleIdText, 'SLUS-20328');
    expect(r.ref.rawSerialText, 'SLUS_203.28');
    expect(r.ref.saveIdText, 'BASLUS-20328');
    expect(r.ref.source, 1);
  });

  group('sync structs', () {
    test('sizes as MSVC gives them (x64)', () {
      expect(sizeOf<SigilSaveOption>(), 16);
      expect(sizeOf<SigilSaveRequest>(), 112);
      expect(sizeOf<SigilSyncRequest>(), 232);
      expect(sizeOf<SigilSyncResult>(), 1064);
      expect(sizeOf<SigilSyncCompanionResult>(), 88);
    });

    /// Where the field [set] writes lands: the first non-zero byte of a zeroed struct.
    int offsetOf<T extends Struct>(int size, void Function(Pointer<T>) set) {
      final s = calloc<Uint8>(size).cast<T>();
      try {
        set(s);
        final bytes = s.cast<Uint8>();
        for (var i = 0; i < size; i++) {
          if (bytes[i] != 0) return i;
        }
        return -1;
      } finally {
        calloc.free(s);
      }
    }

    final mark = Pointer<Never>.fromAddress(0xAB);

    test('request offsets', () {
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.save.layout = mark.cast()), 16);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.save.listing = mark.cast()), 72);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.save.open = mark.cast()), 88);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.save.rootPath = mark.cast()), 104);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.gameIds = mark.cast()), 120);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.mode = 0xAB), 136);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.state = mark.cast()), 144);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.overwriteLocal = 0xAB), 160);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.write = mark.cast()), 168);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.remove = mark.cast()), 200);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.companions = mark.cast()), 208);
      expect(offsetOf<SigilSyncRequest>(232, (s) => s.ref.repair = 0xAB), 224);
    });

    test('result offsets', () {
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.artifact[0] = 0xAB), 4);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.shape = 0xAB), 260);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.data = mark.cast()), 264);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.len = 0xAB), 272);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.contentHash[0] = 0xAB), 280);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.identityHash[0] = 0xAB), 313);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.changed = 0xAB), 348);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.state = mark.cast()), 360);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.holding = mark.cast()), 376);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.unowned = mark.cast()), 392);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.restoreAgain = 0xAB), 408);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.problem[0] = 0xAB), 432);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.blocksShort = 0xAB), 944);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.profile[0] = 0xAB), 968);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.hardcoreMarker = 0xAB), 1048);
      expect(offsetOf<SigilSyncResult>(1064, (s) => s.ref.unownedChanged = 0xAB), 1056);
    });
  });
}
