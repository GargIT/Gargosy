// #59: PPSSPP's save states through RomM.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/ppsspp_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/strategies/ppsspp_save_strategy.dart';
import 'package:gargosy/core/save/strategies/ppsspp_state_file.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

/// A state header as PPSSPP writes it: revision, compression, two sizes,
/// the git version, then the title and data.
Uint8List ppst({int revision = 5, int compress = 2, String version = 'v1.20.4', int size = 400}) {
  final b = Uint8List(size);
  final d = ByteData.sublistView(b);
  d.setInt32(0, revision, Endian.little);
  d.setInt32(4, compress, Endian.little);
  d.setUint32(8, size, Endian.little);
  d.setUint32(12, size * 2, Endian.little);
  b.setAll(16, version.codeUnits);
  return b;
}

Game _game({String? titleId}) =>
    Game.fromJson({...gameJson(1, 'Daxter', fsName: 'Daxter (USA).iso'), 'platform_slug': 'psp', 'title_id': ?titleId});

void main() {
  const rom = r'D:\roms\psp\Daxter (USA).iso';
  late List<String> read;
  late PpssppSaveStrategy s;
  setUp(() {
    read = [];
    s = PpssppSaveStrategy(
      DirectoryService(MemoryPrefs()),
      identify: (path, {platform}) async {
        expect(platform, 'psp');
        read.add(path);
        return const SigilId(titleId: 'UCUS-98618', rawSerial: '', saveId: '', platform: 'psp', fromBinary: true);
      },
    );
  });

  group('the matcher', () {
    test("the game's states, any slot and disc version; nothing else", () async {
      final match = (await s.stateFileMatcher(_game(titleId: 'UCUS98618'), rom))!;
      expect(match('UCUS98618_1.00_0.ppst'), isTrue);
      expect(match('UCUS98618_1.01_4.ppst'), isTrue);
      expect(match('ucus98618_1.00_2.ppst'), isTrue);
      for (final no in [
        'UCUS98618_1.00_0.undo.ppst', // the undo copy
        'load_undo.ppst',
        'UCUS98618_1.00_0.jpg',
        'UCUS98618_1.00_0.name.txt',
        'UCUS98618_1.00_0.ppst.bak',
        'UCUS98618_1.00_0.ppst.tmp',
        'UCUS986180_1.00_0.ppst', // another game with a similar id
        'ULUS10041_1.00_0.ppst',
        r'..\UCUS98618_1.00_0.ppst',
        'sub/UCUS98618_1.00_0.ppst',
      ]) {
        expect(match(no), isFalse, reason: no);
      }
    });

    test("RomM's id (a dash in it too) means the ROM is never read", () async {
      expect(await s.stateFileMatcher(_game(titleId: 'UCUS-98618'), rom), isNotNull);
      expect(read, isEmpty);
    });

    test('no RomM id: the disc id comes from the ROM through sigil, once', () async {
      final match = (await s.stateFileMatcher(_game(), rom))!;
      expect(match('UCUS98618_1.00_0.ppst'), isTrue);
      await s.stateFileMatcher(_game(), rom);
      expect(read, [rom]);
    });

    test('no id anywhere: no matcher (the game has no state sync)', () async {
      final none = PpssppSaveStrategy(DirectoryService(MemoryPrefs()), identify: (path, {platform}) async => null);
      expect(await none.stateFileMatcher(_game(), rom), isNull);
    });
  });

  test('slots are shown from 1, as PPSSPP shows them', () {
    expect(s.slotOf('UCUS98618_1.00_0.ppst'), const NumberedStateSlot(1));
    expect(s.slotOf('UCUS98618_1.00_4.ppst'), const NumberedStateSlot(5));
    expect(s.slotOf('other.ppst'), isA<UnknownStateSlot>());
  });

  group('the header', () {
    test('a real header is a state; too short, an old revision or a strange compression is not', () {
      expect(s.looksLikeValidState(ppst()), isTrue);
      expect(s.looksLikeValidState(ppst(revision: 4)), isTrue);
      expect(s.looksLikeValidState(ppst().sublist(0, 47)), isFalse);
      expect(s.looksLikeValidState(ppst(revision: 3)), isFalse);
      expect(s.looksLikeValidState(ppst(revision: 9999)), isFalse);
      expect(s.looksLikeValidState(ppst(compress: 7)), isFalse);
      expect(s.looksLikeValidState(Uint8List(400)), isFalse);
    });

    test('the version is the build that wrote it; none when the field is empty or not text', () {
      expect(PpssppStateFile.parseVersion(ppst()), 'v1.20.4');
      expect(PpssppStateFile.parseVersion(ppst(version: '')), isNull);
      final junk = ppst()..[17] = 0x01;
      expect(PpssppStateFile.parseVersion(junk), isNull);
    });
  });

  group('on disk', () {
    late io.Directory tmp;
    setUp(() => tmp = io.Directory.systemTemp.createTempSync('gargosy-ppst-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test("describeState gives the build, and the .jpg beside it is the screenshot", () async {
      final state = io.File(p.join(tmp.path, 'UCUS98618_1.00_0.ppst'))..writeAsBytesSync(ppst(version: 'v1.19.3'));
      expect((await s.describeState(state)).emulatorVersion, 'v1.19.3');
      expect(await s.stateScreenshot(state), isNull);
      io.File(p.join(tmp.path, 'UCUS98618_1.00_0.jpg')).writeAsBytesSync([0xFF, 0xD8, 0xFF]);
      expect(await s.stateScreenshot(state), [0xFF, 0xD8, 0xFF]);
    });

    test('an unreadable state describes with no version, never throwing', () async {
      final state = io.File(p.join(tmp.path, 'UCUS98618_1.00_0.ppst'))..writeAsBytesSync([1, 2, 3]);
      expect((await s.describeState(state)).emulatorVersion, isNull);
    });
  });

  test('Resume: --state=<file>, PPSSPP loads it at boot', () {
    final emu = PPSSPPStrategy(DirectoryService(MemoryPrefs()));
    expect(emu.supportsStateSync, isTrue);
    expect(emu.supportsStateLoadOnLaunch, isTrue);
    expect(emu.stateLoadArgs(r'C:\p\UCUS98618_1.00_0.ppst'), [r'--state=C:\p\UCUS98618_1.00_0.ppst']);
    expect(emu.canLoadState('UCUS98618_1.00_0.ppst'), isTrue);
  });
}
