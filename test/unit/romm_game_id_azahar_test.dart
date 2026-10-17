// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_strategy.dart';
import 'package:gargosy/core/save/strategies/azahar_save_strategy.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_id_test_env.dart';

void main() {
  const zeros = '00000000000000000000000000000000';
  late Directory dir;
  late String base; // Azahar's portable data folder: <exe folder>/user
  late AzaharSaveStrategy azahar;
  late List<String> read; // the ROMs sigil was asked about
  SigilId? fromRom; // what sigil reads from any ROM

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('romm_azahar');
    final exe = p.join(dir.path, 'azahar.exe');
    File(exe).writeAsStringSync('');
    base = p.join(dir.path, 'user');
    Directory(base).createSync();
    read = [];
    fromRom = null;
    azahar = AzaharSaveStrategy(await StubDirectoryService.create(exePath: exe),
        platform: const PlatformInfo('windows', environment: {}), identify: (path, {platform}) async {
      expect(platform, '3ds');
      read.add(path);
      return fromRom;
    });
  });
  tearDown(() => dir.delete(recursive: true));

  Game pilotwings({String? saveTarget = '00040000/00033500'}) =>
      Game(id: '3', name: 'Pilotwings Resort', platformSlug: '3ds', fileSize: 0, saveTarget: saveTarget);

  String titleFolder(String id0, String id1) =>
      p.join(base, 'sdmc', 'Nintendo 3DS', id0, id1, 'title', '00040000', '00033500', 'data', '00000001');

  test('no manual mapping: the save folder comes from RomM\'s save_target', () async {
    final id0 = 'a' * 32, id1 = 'b' * 32;
    Directory(titleFolder(id0, id1)).createSync(recursive: true);
    Directory(p.join(base, 'sdmc', 'Nintendo 3DS', 'c' * 32, 'd' * 32)).createSync(recursive: true);
    expect(await azahar.getSaveDir(pilotwings(), r'C:\nope\p.3ds'), titleFolder(id0, id1));
  });

  test('a title not saved yet goes where Azahar will put it', () async {
    expect(await azahar.getSaveDir(pilotwings(), r'C:\nope\p.3ds'), titleFolder(zeros, zeros));
    final id0 = 'c' * 32, id1 = 'd' * 32;
    Directory(p.join(base, 'sdmc', 'Nintendo 3DS', id0, id1)).createSync(recursive: true);
    expect(await azahar.getSaveDir(pilotwings(), r'C:\nope\p.3ds'), titleFolder(id0, id1));
  });

  test('a manual mapping still wins', () async {
    final mapping = p.join('Nintendo 3DS', zeros, zeros, 'title', '00040000', '00099999', 'data', '00000001');
    azahar.setManualMapping(mapping);
    expect(await azahar.getSaveDir(pilotwings(), r'C:\nope\p.3ds'), p.join(base, 'sdmc', mapping));
  });

  test('no RomM id: the ROM\'s own title id, read through sigil once', () async {
    fromRom = const SigilId(
        titleId: '0004000000033500', rawSerial: '', saveId: '00040000/00033500', platform: '3ds', fromBinary: true, usage: 4);
    expect(await azahar.getSaveDir(pilotwings(saveTarget: null), r'C:\roms\p.3ds'), titleFolder(zeros, zeros));
    expect(await azahar.getSaveDir(pilotwings(saveTarget: null), r'C:\roms\p.3ds'), titleFolder(zeros, zeros));
    expect(read, [r'C:\roms\p.3ds']);
  });

  test('RomM\'s id means the ROM is never read', () async {
    await azahar.getSaveDir(pilotwings(), r'C:\roms\p.3ds');
    expect(read, isEmpty);
  });

  test('neither RomM nor the ROM: asks for the folder, as before', () async {
    expect(() => azahar.getSaveDir(pilotwings(saveTarget: null), r'C:\nope\p.3ds'),
        throwsA(isA<SaveMappingRequiredException>()));
  });

  test('a ROM id that isn\'t a 3DS title path, or a failed read, asks for the folder', () async {
    fromRom = const SigilId(titleId: 'x', rawSerial: '', saveId: '../../x', platform: '3ds', fromBinary: false);
    expect(() => azahar.getSaveDir(pilotwings(saveTarget: null), r'C:\roms\a.3ds'),
        throwsA(isA<SaveMappingRequiredException>()));
    final failing = AzaharSaveStrategy(await StubDirectoryService.create(exePath: p.join(dir.path, 'azahar.exe')),
        platform: const PlatformInfo('windows', environment: {}),
        identify: (path, {platform}) async => throw const SigilException(-1, 'unreadable'));
    expect(() => failing.getSaveDir(pilotwings(saveTarget: null), r'C:\roms\b.3ds'),
        throwsA(isA<SaveMappingRequiredException>()));
  });

  group('RomM 3DS ids that need care', () {
    test('an update or DLC id points at the base game\'s save', () async {
      expect(await azahar.getSaveDir(pilotwings(saveTarget: '0004000e/00033500'), r'C:\nope\p.3ds'),
          titleFolder(zeros, zeros));
      expect(await azahar.getSaveDir(pilotwings(saveTarget: '0004008c/00033500'), r'C:\nope\p.3ds'),
          titleFolder(zeros, zeros));
    });

    test('a flat 16-hex title id is split into its two folders', () async {
      expect(await azahar.getSaveDir(pilotwings(saveTarget: '0004000000033500'), r'C:\nope\p.3ds'),
          titleFolder(zeros, zeros));
    });

    test('a RomM value that isn\'t a 3DS title is ignored (asks for the folder)', () async {
      expect(() => azahar.getSaveDir(pilotwings(saveTarget: '../../../x'), r'C:\nope\p.3ds'),
          throwsA(isA<SaveMappingRequiredException>()));
    });
  });

  test('an 8-hex 3DS id with no category is the game\'s (00040000)', () async {
    expect(await azahar.getSaveDir(pilotwings(saveTarget: '00033500'), r'C:\nope\p.3ds'), titleFolder(zeros, zeros));
  });
}
