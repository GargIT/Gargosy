import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/storage_usage.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  void file(String path, int bytes) => io.File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(List<int>.filled(bytes, 1));

  test("the platforms' games largest first, a folder game counted whole; the other folders", () async {
    file(p.join(root.roms, 'psx', 'Crash.chd'), 300);
    file(p.join(root.roms, 'psx', 'FF7', 'disc1.chd'), 500);
    file(p.join(root.roms, 'psx', 'FF7', 'disc2.chd'), 500);
    file(p.join(root.roms, 'gba', 'Zelda.gba'), 2000);
    file(p.join(root.bios, 'scph1001.bin'), 50);
    file(p.join(root.appData, 'temp', 'download-1.part'), 70);
    final usage = await readStorage(root);
    expect(usage.platforms.map((x) => x.folder), ['gba', 'psx']);
    final psx = usage.platforms.last;
    expect(psx.entries.map((e) => (e.name, e.bytes)), [('FF7', 1000), ('Crash.chd', 300)]);
    expect(psx.bytes, 1300);
    expect(usage.folders['ROMs'], 3300);
    expect(usage.folders['BIOS'], 50);
    expect(usage.folders['Temp'], 70);
  });

  test('a folder link is not followed (an emulator folder pointing at a profile)', () async {
    final target = p.join(root.profiles, 'a', 'emulators', 'x');
    file(p.join(target, 'big.bin'), 1000);
    io.Directory(root.emulators).createSync(recursive: true);
    final r = await io.Process.run('cmd', ['/c', 'mklink', '/J', p.join(root.emulators, 'x'), target]);
    if (r.exitCode != 0) return markTestSkipped('no junctions here');
    expect(sizeOf(root.emulators), 0);
    expect(sizeOf(root.profiles), 1000);
  });
}
