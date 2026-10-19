// #61: mGBA's save states through RomM.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/mgba_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/strategies/mgba_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Uint8List _raw(int magic) => Uint8List(64)..buffer.asByteData().setUint32(0, magic, Endian.little);

void main() {
  const rom = r'D:\roms\gba\Metroid Fusion (USA).gba';
  final game = Game.fromJson({
    ...gameJson(1, 'Metroid Fusion', fsName: 'Metroid Fusion (USA).gba'),
    'platform_slug': 'gba',
  });
  final s = MgbaSaveStrategy(DirectoryService(MemoryPrefs()));

  test("the matcher: the ROM's stem and slots .ss0-.ss9; nothing else", () async {
    final match = (await s.stateFileMatcher(game, rom))!;
    for (final yes in [
      'Metroid Fusion (USA).ss1',
      'Metroid Fusion (USA).ss9',
      'Metroid Fusion (USA).ss0',
      'metroid fusion (usa).ss2',
    ]) {
      expect(match(yes), isTrue, reason: yes);
    }
    for (final no in [
      'Metroid Fusion (USA).ss10',
      'Metroid Fusion (USA).sav',
      'Metroid Fusion (USA).ss1.bak',
      'Metroid Fusion (USA) [b].ss1', // another dump
      'Metroid Fusion.ss1',
      r'..\Metroid Fusion (USA).ss1',
      'x/Metroid Fusion (USA).ss1',
    ]) {
      expect(match(no), isFalse, reason: no);
    }
  });

  test("a zip mGBA opens itself: the zip's stem, as mGBA names the state", () async {
    final zipped = Game.fromJson({...gameJson(2, 'Tetris', fsName: 'Tetris (World).zip'), 'platform_slug': 'gb'});
    final match = (await s.stateFileMatcher(zipped, r'D:\roms\gb\Tetris (World).zip'))!;
    expect(match('Tetris (World).ss1'), isTrue);
  });

  test('slots are the number in the name', () {
    expect(s.slotOf('Metroid Fusion (USA).ss3'), const NumberedStateSlot(3));
    expect(s.slotOf('Metroid Fusion (USA).sav'), isA<UnknownStateSlot>());
  });

  test('a state is a PNG or a raw GBA or GB state; anything else is not', () {
    expect(s.looksLikeValidState(Uint8List.fromList([..._pngSignature, 0, 0, 0, 13])), isTrue);
    expect(s.looksLikeValidState(_raw(0x0100000B)), isTrue, reason: 'GBA, version 11');
    expect(s.looksLikeValidState(_raw(0x00400003)), isTrue, reason: 'GB, version 3');
    expect(s.looksLikeValidState(_raw(0x12345678)), isFalse);
    expect(s.looksLikeValidState(Uint8List(3)), isFalse);
  });

  test('a PNG state is its own screenshot; a raw one has none', () async {
    final tmp = io.Directory.systemTemp.createTempSync('gargosy-mgbastate-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final png = io.File(p.join(tmp.path, 'a.ss1'))..writeAsBytesSync([..._pngSignature, 1, 2, 3]);
    expect(await s.stateScreenshot(png), [..._pngSignature, 1, 2, 3]);
    final raw = io.File(p.join(tmp.path, 'a.ss2'))..writeAsBytesSync(_raw(0x0100000B));
    expect(await s.stateScreenshot(raw), isNull);
    expect((await s.describeState(raw)).emulatorVersion, isNull, reason: 'mGBA records no build');
  });

  test('Resume: -t <file>', () {
    final emu = MGBAStrategy(DirectoryService(MemoryPrefs()));
    expect(emu.supportsStateSync, isTrue);
    expect(emu.supportsStateLoadOnLaunch, isTrue);
    expect(emu.stateLoadArgs(r'C:\s\a.ss1'), ['-t', r'C:\s\a.ss1']);
  });
}
