import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/formats/ps2_memory_card.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:path/path.dart' as p;

void main() {
  late io.Directory data;
  setUp(() async => data = await io.Directory.systemTemp.createTemp('layout'));
  tearDown(() => data.delete(recursive: true));

  String card(String rel) => p.join(data.path, rel);

  test("a new profile's PCSX2 gets a formatted folder memory card before the first save goes in", () {
    EmulatorLayout.of('pcsx2').ensureFolders(data.path);
    final folder = io.Directory(card(r'PCSX2\memcards\Mcd001.ps2'));
    expect(folder.existsSync(), isTrue, reason: 'a folder card, as PCSX2 and Freegosy keep them');
    final sb = io.File(p.join(folder.path, '_pcsx2_superblock')).readAsBytesSync();
    expect(sb.length, 8192);
    expect(String.fromCharCodes(sb.sublist(0, 28)), 'Sony PS2 Memory Card Format ');
  });

  test("a folder card without its superblock (an earlier pull's) gets one; its saves stay", () {
    final save = io.File(card(r'PCSX2\memcards\Mcd001.ps2\BASLUS-21693\BASLUS-21693'))
      ..createSync(recursive: true)
      ..writeAsStringSync('progress');
    EmulatorLayout.of('pcsx2').ensureFolders(data.path);
    expect(io.File(card(r'PCSX2\memcards\Mcd001.ps2\_pcsx2_superblock')).existsSync(), isTrue);
    expect(save.readAsStringSync(), 'progress');
  });

  test("a file card is left as it is", () {
    final file = io.File(card(r'PCSX2\memcards\Mcd001.ps2'))
      ..createSync(recursive: true)
      ..writeAsStringSync('mine');
    EmulatorLayout.of('pcsx2').ensureFolders(data.path);
    expect(file.readAsStringSync(), 'mine');
  });

  test("RetroArch's PS2 core gets a formatted file card, as it makes itself", () {
    EmulatorLayout.of('retroarch').ensureFolders(data.path);
    final bytes = io.File(card(r'system\pcsx2\memcards\Mcd001.ps2')).readAsBytesSync();
    expect(bytes.length, Ps2MemoryCard.sizeWithEcc);
    expect(Ps2MemoryCard.parse(bytes).saves, isEmpty);
  });
}
