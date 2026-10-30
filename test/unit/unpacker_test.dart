import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/extraction/unpacker.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:path/path.dart' as p;

void main() {
  late io.Directory dir;
  late Unpacker unpacker;
  late String zip;
  setUp(() {
    dir = io.Directory.systemTemp.createTempSync('unpacker_test');
    unpacker = unpackerFor(PlatformInfo.current);
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('Game.iso', List.filled(3000, 7)))
      ..addFile(ArchiveFile.bytes('extra/readme.txt', 'hi'.codeUnits));
    zip = p.join(dir.path, 'game.zip');
    io.File(zip).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('unpackerFor (#200)', () {
    test("Windows gets Windows' own tar.exe, by its path", () {
      final u = unpackerFor(const PlatformInfo('windows', environment: {'SystemRoot': r'D:\Win'}));
      expect((u as TarUnpacker).tar, r'D:\Win\System32\tar.exe');
    });

    test('an OS without an unpacker yet is refused', () {
      expect(() => unpackerFor(const PlatformInfo('linux')), throwsUnsupportedError);
    });
  });

  test("lists a zip's files with their sizes", () async {
    final entries = await unpacker.list(zip);
    expect(entries, containsAll([(name: 'Game.iso', size: 3000), (name: 'extra/readme.txt', size: 2)]));
  });

  test('unpacks into a folder, leaving out what is excluded', () async {
    final into = io.Directory(p.join(dir.path, 'out'))..createSync();
    await unpacker.unpack(zip, into.path, exclude: const ['Game.iso']);
    expect(io.File(p.join(into.path, 'extra', 'readme.txt')).readAsStringSync(), 'hi');
    expect(io.File(p.join(into.path, 'Game.iso')).existsSync(), isFalse);
  });

  test("streams one file's bytes", () async {
    final bytes = [await for (final chunk in unpacker.open(zip, 'Game.iso')) ...chunk];
    expect(bytes, List.filled(3000, 7));
  });

  test('a name is only itself, never a pattern: `[`, `*` and `?` too', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('Halo [!] (a*b?).ISO', [1]))
      ..addFile(ArchiveFile.bytes('Halo x (aab).ISO', [2]));
    final odd = p.join(dir.path, 'odd.zip');
    io.File(odd).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    expect([await for (final chunk in unpacker.open(odd, 'Halo [!] (a*b?).ISO')) ...chunk], [1]);
    final into = io.Directory(p.join(dir.path, 'odd'))..createSync();
    await unpacker.unpack(odd, into.path, exclude: const ['Halo [!] (a*b?).ISO']);
    expect(into.listSync().map((e) => p.basename(e.path)), ['Halo x (aab).ISO']);
  });

  test('a zip that is not one fails with what the unpacker said', () async {
    final bad = p.join(dir.path, 'bad.zip');
    io.File(bad).writeAsStringSync('not a zip');
    await expectLater(unpacker.list(bad), throwsA(isA<UnpackException>()));
    await expectLater(unpacker.open(bad, 'Game.iso').drain<void>(), throwsA(isA<UnpackException>()));
  });
}
