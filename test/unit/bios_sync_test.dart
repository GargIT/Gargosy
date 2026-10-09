import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/firmware_service.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/emulators/bios_sync.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

class _Romm extends Fake implements RommService {
  _Romm(this.platforms);
  final List<Platform> platforms;

  @override
  Future<List<Platform>> getPlatforms() async => platforms;

  @override
  Future<Uint8List?> downloadFirmware(Firmware firmware, {void Function(int received, int total)? onProgress}) async =>
      Uint8List.fromList([1, 2, 3, 4]);
}

Firmware _fw(int id, String name) => Firmware.fromJson({'id': id, 'file_name': name, 'file_size_bytes': 4});

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  FirmwareService service(List<Firmware> ps2) {
    final dirs = ProfileLaunchDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
    final registry = StrategyRegistry(dirs, MemoryPrefs());
    return FirmwareService(_Romm([Platform(id: 1, name: 'PlayStation 2', slug: 'ps2', firmware: ps2)]), dirs, registry);
  }

  test("PCSX2's BIOS files from RomM land in the shared bios folder itself, where PCSX2 looks", () async {
    await service([_fw(1, 'ps2-0230a-20080220.bin')]).syncFirmwareForEmulator('pcsx2');
    expect(io.File(p.join(root.bios, 'ps2-0230a-20080220.bin')).existsSync(), isTrue);
    expect(io.Directory(p.join(root.bios, 'bios')).existsSync(), isFalse);
  });

  test("a file name from the server can't put anything outside the bios folder", () async {
    await service([_fw(2, r'..\..\evil.bin')]).syncFirmwareForEmulator('pcsx2');
    expect(io.File(p.join(root.root, 'evil.bin')).existsSync(), isFalse);
    expect(io.File(p.join(p.dirname(root.root), 'evil.bin')).existsSync(), isFalse);
  });

  test('says how many files it brought down; a file already there is not fetched again', () async {
    final sync = BiosSync(service([_fw(1, 'ps2-0230a-20080220.bin')]));
    expect(await sync.forEmulator('pcsx2'), 1);
    expect(await sync.forEmulator('pcsx2'), 0);
  });
}
