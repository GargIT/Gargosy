// #60: Dolphin's save states through RomM.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/dolphin_strategy.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/strategies/dolphin_save_strategy.dart';
import 'package:gargosy/core/save/strategies/dolphin_state_file.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

/// A state as Dolphin writes it (State.cpp `WriteHeadersToFile`): the legacy
/// header, the version header and the build string, then the payload.
Uint8List dolphinState({String gameId = 'GZLE01', int lzo = 0, int stateVersion = 170, String version = 'Dolphin 2609a'}) {
  final b = Uint8List(32 + version.length + 64);
  final d = ByteData.sublistView(b);
  b.setAll(0, gameId.codeUnits);
  d.setUint32(8, lzo, Endian.little);
  d.setFloat64(16, 7.5e8, Endian.little);
  d.setUint32(24, 0xBAADBABE + stateVersion, Endian.little);
  d.setUint32(28, version.length, Endian.little);
  b.setAll(32, version.codeUnits);
  return b;
}

Game _gc({String? saveTarget, String slug = 'ngc'}) =>
    Game.fromJson({...gameJson(1, 'Zelda', fsName: 'Zelda.wbfs'), 'platform_slug': slug, 'save_target': ?saveTarget});

void main() {
  const rom = r'D:\roms\ngc\Zelda.wbfs';
  late List<String> read;
  late DolphinSaveStrategy s;
  setUp(() {
    read = [];
    s = DolphinSaveStrategy(DirectoryService(MemoryPrefs()), identify: (path, {platform}) async {
      read.add('$platform $path');
      return const SigilId(titleId: '475A4C45', rawSerial: 'GZLE', saveId: '', platform: 'gamecube', fromBinary: true);
    });
  });

  group('the matcher', () {
    test("the game's ten slots under any maker code; nothing else", () async {
      final match = (await s.stateFileMatcher(_gc(saveTarget: 'GZLE'), rom))!;
      for (final yes in ['GZLE01.s01', 'GZLE01.s10', 'GZLE8P.s05', 'gzle01.s03']) {
        expect(match(yes), isTrue, reason: yes);
      }
      for (final no in [
        'GZLE01.s00',
        'GZLE01.s11',
        'lastState.sav', // the undo of a load
        'undo.dtm',
        'GZLE01.s01.dtm', // a movie beside a state
        'GZLE01.s01.bak',
        'GZLF01.s01', // another game
        'GZL01.s01',
        r'..\GZLE01.s01',
        'sub/GZLE01.s01',
      ]) {
        expect(match(no), isFalse, reason: no);
      }
      expect(read, isEmpty, reason: "RomM's id: the ROM isn't read");
    });

    test("a Wii game: RomM's hex save_target is its id", () async {
      final match = (await s.stateFileMatcher(_gc(saveTarget: '52534245', slug: 'wii'), r'D:\roms\wii\Sports.wbfs'))!;
      expect(match('RSBE01.s02'), isTrue);
    });

    test('no RomM id and none from the file: sigil reads the disc, once', () async {
      final match = (await s.stateFileMatcher(_gc(), rom))!;
      expect(match('GZLE01.s01'), isTrue);
      await s.stateFileMatcher(_gc(), rom);
      expect(read, ['gamecube $rom']);
    });

    test('no id anywhere: no matcher', () async {
      final none = DolphinSaveStrategy(DirectoryService(MemoryPrefs()), identify: (path, {platform}) async => null);
      expect(await none.stateFileMatcher(_gc(), rom), isNull);
    });
  });

  test('slots are the file number', () {
    expect(s.slotOf('GZLE01.s01'), const NumberedStateSlot(1));
    expect(s.slotOf('GZLE01.s10'), const NumberedStateSlot(10));
    expect(s.slotOf('lastState.sav'), isA<UnknownStateSlot>());
  });

  group('the header', () {
    test("a state; an old LZO state too; not a cookie that isn't Dolphin's, a bad game id or too few bytes", () {
      expect(s.looksLikeValidState(dolphinState()), isTrue);
      expect(s.looksLikeValidState(dolphinState(lzo: 1234)), isTrue);
      final badCookie = dolphinState();
      ByteData.sublistView(badCookie).setUint32(24, 0x12345678, Endian.little);
      expect(s.looksLikeValidState(badCookie), isFalse);
      expect(s.looksLikeValidState(dolphinState(gameId: 'GZ\u0000E01')), isFalse);
      expect(s.looksLikeValidState(dolphinState().sublist(0, 20)), isFalse);
      expect(s.looksLikeValidState(Uint8List(200)), isFalse);
    });

    test('the build that wrote it; none for an old state or a garbled string', () {
      expect(DolphinStateFile.parseVersion(dolphinState()), 'Dolphin 2609a');
      expect(DolphinStateFile.parseVersion(dolphinState(lzo: 99)), isNull);
      final garbled = dolphinState()..[33] = 0x02;
      expect(DolphinStateFile.parseVersion(garbled), isNull);
      final tooLong = dolphinState();
      ByteData.sublistView(tooLong).setUint32(28, 5000, Endian.little);
      expect(DolphinStateFile.parseVersion(tooLong), isNull);
    });

    test('describeState reads it from the file, never throwing', () async {
      final tmp = io.Directory.systemTemp.createTempSync('gargosy-dolphinstate-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final state = io.File(p.join(tmp.path, 'GZLE01.s01'))..writeAsBytesSync(dolphinState(version: 'Dolphin 2606'));
      expect((await s.describeState(state)).emulatorVersion, 'Dolphin 2606');
      state.writeAsBytesSync([1, 2]);
      expect((await s.describeState(state)).emulatorVersion, isNull);
    });
  });

  group('Resume', () {
    final emu = DolphinStrategy(DirectoryService(MemoryPrefs()), platform: const PlatformInfo('windows'));

    test('--save_state=<file>', () {
      expect(emu.supportsStateSync, isTrue);
      expect(emu.supportsStateLoadOnLaunch, isTrue);
      expect(emu.stateLoadArgs(r'C:\s\GZLE01.s01'), [r'--save_state=C:\s\GZLE01.s01']);
    });

    test('the state goes before -b -e, which takes the game as its value', () {
      expect(emu.argsWith(emu.stateLoadArgs(r'C:\s\GZLE01.s01')), [r'--save_state=C:\s\GZLE01.s01', '-b', '-e']);
      expect(emu.argsWith(const []), ['-b', '-e']);
    });
  });
}
