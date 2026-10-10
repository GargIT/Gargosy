import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:gargosy/sigil/sigil_platforms.dart';
import 'package:path/path.dart' as p;

String fixture(String name) => p.absolute(p.join('test', 'fixtures', 'chd', name));

void main() {
  late io.Directory tmp;
  setUp(() => tmp = io.Directory.systemTemp.createTempSync('gargosy-sigil-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('sigil reports its version', () async => expect(await SigilEngine.version(), '1.0.0'));

  test('a PS2 DVD CHD gives its serial, read from the disc', () async {
    final id = await SigilEngine.identify(fixture('ps2_dvd_default.chd'), platform: 'ps2');
    expect(id!.titleId, 'SLUS-20328');
    expect(id.fromBinary, isTrue);
    expect(id.platform, 'ps2');
  });

  test('a PS1 CD CHD gives its serial', () async {
    expect((await SigilEngine.identify(fixture('ps1_cd_cdlz.chd'), platform: 'psx'))!.titleId, 'SCES-01237');
  });

  for (final (name, platform, want) in [
    ('ps2_dvd_none.chd', 'ps2', 'SLUS-20328'),
    ('ps2_dvd_zlib.chd', 'ps2', 'SLUS-20328'),
    ('ps2_dvd_lzma.chd', 'ps2', 'SLUS-20328'),
    ('ps2_dvd_huff.chd', 'ps2', 'SLUS-20328'),
    ('ps2_dvd_zstd.chd', 'ps2', 'SLUS-20328'), // sigil bundles zstd: no plugin needed
    ('ps1_cd_cdzl.chd', 'psx', 'SCES-01237'),
    ('ps1_cd_cdzs.chd', 'psx', 'SCES-01237'),
    ('ps1_cd_default.chd', 'psx', 'SCES-01237'),
  ]) {
    test('$name: $want', () async {
      expect((await SigilEngine.identify(fixture(name), platform: platform))?.titleId, want);
    });
  }

  test('a PS2 CD as a raw 2352-byte BIN (Redump BIN/CUE) gives its serial', () async {
    // The PS1 raw track with its boot line made a PS2 one (same length).
    final raw = io.gzip.decode(io.File(fixture('cd.bin.gz')).readAsBytesSync());
    final at = String.fromCharCodes(raw).indexOf('BOOT =');
    expect(at, greaterThan(0));
    raw.setRange(at, at + 6, 'BOOT2='.codeUnits);
    final bin = io.File(p.join(tmp.path, 'PS2 CD Game (Track 1).bin'))..writeAsBytesSync(raw);
    expect((await SigilEngine.identify(bin.path, platform: 'ps2'))?.titleId, 'SCES-01237');
  });

  test('not a disc, a missing file, a folder: no id, no exception', () async {
    final junk = io.File(p.join(tmp.path, 'junk.chd'))..writeAsBytesSync(List.filled(300, 9));
    expect(await SigilEngine.identify(junk.path, platform: 'ps2'), isNull);
    expect(await SigilEngine.identify(p.join(tmp.path, 'missing.iso'), platform: 'ps2'), isNull);
    expect(await SigilEngine.identify(tmp.path, platform: 'ps2'), isNull);
  });

  test('a path with non-ASCII characters is read', () async {
    final copy = io.File(fixture('ps2_dvd_default.chd')).copySync(p.join(tmp.path, 'Ōkami テスト.chd'));
    expect((await SigilEngine.identify(copy.path, platform: 'ps2'))?.titleId, 'SLUS-20328');
  });

  test("RomM's platform slugs map to sigil's", () {
    expect(sigilPlatformFor('ps2'), 'ps2');
    expect(sigilPlatformFor('psx'), 'psx');
    expect(sigilPlatformFor('ps'), 'psx');
    expect(sigilPlatformFor('ngc'), 'gamecube');
    expect(sigilPlatformFor('dc'), 'dreamcast');
    expect(sigilPlatformFor('amiga'), isNull);
  });
}
