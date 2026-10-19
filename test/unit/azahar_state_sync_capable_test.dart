// #64: Azahar's save states through RomM (sync only: no Resume).
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/azahar_strategy.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/strategies/azahar_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/sigil/sigil_engine.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_id_test_env.dart';
import '../helpers/profile_test_env.dart';

/// A state's 256-byte header as Azahar writes it (src/core/savestate.cpp).
Uint8List cst({int programId = 0x000400000009F300, String buildVersion = '2124', bool magic = true}) {
  final b = Uint8List(400);
  final d = ByteData.sublistView(b);
  if (magic) b.setAll(0, [0x43, 0x53, 0x54, 0x1B]);
  d.setUint64(4, programId, Endian.little);
  b.setAll(40, 'Azahar 2124'.codeUnits);
  b.setAll(64, buildVersion.codeUnits);
  return b;
}

void main() {
  late io.Directory dir;
  late AzaharSaveStrategy azahar;
  late List<String> read;
  setUp(() async {
    dir = await io.Directory.systemTemp.createTemp('gargosy-azaharstate');
    final exe = p.join(dir.path, 'azahar.exe');
    io.File(exe).writeAsStringSync('');
    io.Directory(p.join(dir.path, 'user')).createSync();
    read = [];
    azahar = AzaharSaveStrategy(
      await StubDirectoryService.create(exePath: exe),
      platform: const PlatformInfo('windows', environment: {}),
      identify: (path, {platform}) async {
        read.add(path);
        return const SigilId(
          titleId: '000400000009F300',
          rawSerial: '',
          saveId: '00040000/0009f300',
          platform: '3ds',
          fromBinary: true,
          usage: 4,
        );
      },
    );
  });
  tearDown(() => dir.delete(recursive: true));

  Game wipeout({String? saveTarget}) =>
      Game(id: '9', name: 'Wipeout 3', platformSlug: '3ds', fileSize: 0, saveTarget: saveTarget);
  const rom = r'D:\roms\3ds\Wipeout 3 (USA).3ds';

  test("states are in user\\states, where Azahar keeps them", () async {
    expect(await azahar.stateDirectory(wipeout(), rom), p.join(dir.path, 'user', 'states'));
  });

  test("the matcher: the game's program id, slots 0-11; not a movie's states or another game's", () async {
    final match = (await azahar.stateFileMatcher(wipeout(), rom))!;
    for (final yes in [
      '000400000009F300.01.cst',
      '000400000009F300.00.cst',
      '000400000009F300.11.cst',
      '000400000009f300.02.cst',
    ]) {
      expect(match(yes), isTrue, reason: yes);
    }
    for (final no in [
      '000400000009F300.12.cst',
      '000400000009F300.movie0000000000000001.01.cst',
      '0004000000033500.01.cst',
      '000400000009F300.01.cst.bak',
      r'..\000400000009F300.01.cst',
    ]) {
      expect(match(no), isFalse, reason: no);
    }
    expect(read, [rom], reason: 'no RomM id: the ROM gives it');
  });

  test("RomM's save_target gives the id; the ROM isn't read", () async {
    final match = (await azahar.stateFileMatcher(wipeout(saveTarget: '00040000/0009f300'), rom))!;
    expect(match('000400000009F300.01.cst'), isTrue);
    expect(read, isEmpty);
  });

  test('slots, header and the build version', () async {
    expect(azahar.slotOf('000400000009F300.03.cst'), const NumberedStateSlot(3));
    expect(azahar.looksLikeValidState(cst()), isTrue);
    expect(azahar.looksLikeValidState(cst(magic: false)), isFalse);
    expect(azahar.looksLikeValidState(cst().sublist(0, 200)), isFalse);
    final state = io.File(p.join(dir.path, 's.cst'))..writeAsBytesSync(cst(buildVersion: '2125'));
    expect((await azahar.describeState(state)).emulatorVersion, '2125');
  });

  test('state sync without Resume: Azahar has no option to load a state at start', () {
    final emu = AzaharStrategy(DirectoryService(MemoryPrefs()));
    expect(emu.supportsStateSync, isTrue);
    expect(emu.supportsStateLoadOnLaunch, isFalse);
  });
}
