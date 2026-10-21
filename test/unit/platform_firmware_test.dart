import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/emulators/bios_links.dart';
import 'package:gargosy/library/platform_firmware.dart';
import 'package:path/path.dart' as p;

Firmware _fw(String name) => Firmware.fromJson({'id': name.hashCode, 'file_name': name, 'file_size_bytes': 4});

void main() {
  late io.Directory bios;
  setUp(() => bios = io.Directory.systemTemp.createTempSync('gargosy-bios-'));
  tearDown(() => bios.deleteSync(recursive: true));

  test('a file is on this PC by name, in the bios folder or a subfolder, in any case; the list is sorted by name', () {
    io.File(p.join(bios.path, 'scph-70012.bin')).writeAsBytesSync([1]);
    io.Directory(p.join(bios.path, 'dc')).createSync();
    io.File(p.join(bios.path, 'dc', 'DC_BOOT.BIN')).writeAsBytesSync([1]);
    final list = firmwareOnThisPc([
      _fw('SCPH-70012.bin'),
      _fw('missing.bin'),
      _fw('dc_boot.bin'),
    ], BiosFiles(bios.path));
    expect(
      [for (final f in list) (f.firmware.fileName, f.onThisPc)],
      [('dc_boot.bin', true), ('missing.bin', false), ('SCPH-70012.bin', true)],
    );
  });

  test('no bios folder: everything is missing', () {
    final list = firmwareOnThisPc([_fw('a.bin')], BiosFiles(p.join(bios.path, 'nowhere')));
    expect(list.single.onThisPc, isFalse);
  });
}
