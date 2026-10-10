import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/sigil/rom_game_ids.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

String fixture(String name) => p.absolute(p.join('test', 'fixtures', 'chd', name));

void main() {
  late io.Directory tmp;
  late MemoryPrefs prefs;
  setUp(() {
    tmp = io.Directory.systemTemp.createTempSync('gargosy-romids-');
    prefs = MemoryPrefs();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// The fixtures' source images, unpacked: a cooked PS2 ISO and a raw PS1 track.
  String unpack(String gz, String as) {
    final out = io.File(p.join(tmp.path, as));
    out.writeAsBytesSync(io.gzip.decode(io.File(fixture(gz)).readAsBytesSync()));
    return out.path;
  }

  group('normalizeSerial', () {
    test('underscore to dash', () => expect(RomGameIds.normalizeSerial('SLUS_20152'), 'SLUS-20152'));
    test('the dot before the last two digits goes', () {
      expect(RomGameIds.normalizeSerial('SLUS_201.52'), 'SLUS-20152');
      expect(RomGameIds.normalizeSerial('slus-201.52'), 'SLUS-20152');
    });
  });

  test('a PS2 CHD: its serial, read through sigil, and remembered for the file', () async {
    final rom = io.File(fixture('ps2_dvd_default.chd')).copySync(p.join(tmp.path, 'Game.chd')).path;
    expect(await RomGameIds(prefs).discSerial(rom, platform: 'ps2'), 'SLUS-20328');
    expect(prefs.getString('disc_serial_${p.absolute(rom)}'), 'SLUS-20328');
  });

  test('a PS1 CHD', () async {
    expect(await RomGameIds(prefs).discSerial(fixture('ps1_cd_cdlz.chd'), platform: 'psx'), 'SCES-01237');
  });

  test('a PS2 ISO and a PS1 raw BIN', () async {
    expect(await RomGameIds(prefs).discSerial(unpack('dvd.iso.gz', 'Game.iso'), platform: 'ps2'), 'SLUS-20328');
    expect(await RomGameIds(prefs).discSerial(unpack('cd.bin.gz', 'Game.bin'), platform: 'psx'), 'SCES-01237');
  });

  test("a remembered serial is used without reading the ROM (also one the old service remembered)", () async {
    final rom = p.join(tmp.path, 'Game.chd');
    io.File(rom).writeAsBytesSync([0]);
    await prefs.setString('disc_serial_${p.absolute(rom)}', 'SLUS-20152');
    var reads = 0;
    final ids = RomGameIds(
      prefs,
      identify: (path, {platform}) async {
        reads++;
        return null;
      },
    );
    expect(await ids.discSerial(rom, platform: 'ps2'), 'SLUS-20152');
    expect(reads, 0);
  });

  test("a later track of a .cue set is read through the set's data track", () async {
    unpack('cd.bin.gz', 'Game (Track 01).bin');
    final track2 = p.join(tmp.path, 'Game (Track 02).bin');
    io.File(track2).writeAsBytesSync(List.filled(4096, 0));
    io.File(p.join(tmp.path, 'Game.cue')).writeAsStringSync(
      'FILE "Game (Track 01).bin" BINARY\n'
      '  TRACK 01 MODE2/2352\n'
      '    INDEX 01 00:00:00\n'
      'FILE "Game (Track 02).bin" BINARY\n'
      '  TRACK 02 AUDIO\n'
      '    INDEX 01 00:02:00\n',
    );
    expect(await RomGameIds(prefs).discSerial(track2, platform: 'psx'), 'SCES-01237');
  });

  test("a serial in the file name is enough when the disc doesn't give one", () async {
    final rom = p.join(tmp.path, 'Ico (SCUS-97113).iso');
    io.File(rom).writeAsBytesSync(List.filled(4096, 0));
    expect(await RomGameIds(prefs).discSerial(rom, platform: 'ps2'), 'SCUS-97113');
  });

  test("a ROM sigil can't open (missing, not readable) still gives the serial in its name", () async {
    final missing = p.join(tmp.path, 'Colin McRae Rally 2.0 (Europe) (SLES-02605).chd');
    expect(await RomGameIds(prefs).discSerial(missing, platform: 'psx'), 'SLES-02605');
    final failing = RomGameIds(
      prefs,
      identify: (path, {platform}) async => throw const SigilException(-8, 'out of memory'),
    );
    expect(await failing.discSerial(missing, platform: 'psx'), 'SLES-02605');
  });

  test('nothing readable, or sigil failing: no serial, never an exception', () async {
    final junk = p.join(tmp.path, 'junk.chd');
    io.File(junk).writeAsBytesSync(List.filled(300, 9));
    expect(await RomGameIds(prefs).discSerial(junk, platform: 'ps2'), isNull);
    final failing = RomGameIds(
      prefs,
      identify: (path, {platform}) async => throw const SigilException(-8, 'out of memory'),
    );
    expect(await failing.discSerial(fixture('ps2_dvd_default.chd'), platform: 'ps2'), isNull);
  });
}
