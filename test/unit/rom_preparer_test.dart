import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/library/rom_preparer.dart';
import 'package:gargosy/library/xbox_disc.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

/// A small stand-in for the 387 MB video partition.
const gp = 0x30000;

Uint8List xiso() {
  final b = Uint8List(xdvdfsDescriptor + 20 + 4000);
  b.setAll(xdvdfsDescriptor, xdvdfsMagic.codeUnits);
  for (var i = xdvdfsDescriptor + 20; i < b.length; i++) {
    b[i] = i % 251;
  }
  return b;
}

Uint8List redump(Uint8List game) => Uint8List(gp + game.length)..setAll(gp, game);

void main() {
  late AppRoot root;
  late RomFiles files;
  late RomPreparer preparer;
  setUp(() async {
    root = await tempAppRoot();
    files = RomFiles(root);
    preparer = RomPreparer(files: files, guard: PathGuard(root), tempDir: p.join(root.appData, 'temp'), gamePartition: gp);
  });
  tearDown(() => deleteTempDir(root.root));

  final halo = game(1, 'Halo', platform: 'xbox', fsName: 'Halo (USA).zip');

  String zipWith(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)));
    final path = files.pathFor(halo);
    io.Directory(p.dirname(path)).createSync(recursive: true);
    io.File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    return path;
  }

  test('xemu: a zipped Redump disc is unpacked once into the game folder, as an XISO, and the zip goes', () async {
    final zip = zipWith({'Halo (USA).iso': redump(xiso())});
    final said = <String>[];
    final folder = await preparer.ready(halo, zip, 'xemu', onProgress: said.add);
    expect(folder, p.join(root.roms, 'xbox', 'Halo (USA)'));
    expect(io.File(p.join(folder!, 'Halo (USA).iso')).readAsBytesSync(), xiso());
    expect(io.File(zip).existsSync(), isFalse);
    expect(said, isNotEmpty);
    // The game is still "downloaded", now as its folder, and nothing is left in temp.
    expect(files.pathFor(halo), folder);
    expect(files.isDownloaded(halo), isTrue);
    expect(io.Directory(p.join(root.appData, 'temp')).listSync(), isEmpty);
    // A second play finds nothing to do.
    expect(await preparer.ready(halo, p.join(folder, 'Halo (USA).iso'), 'xemu'), isNull);
  });

  test('xemu: the other files in the zip come along', () async {
    final zip = zipWith({'Halo (USA).iso': xiso(), 'readme.txt': [1, 2]});
    final folder = await preparer.ready(halo, zip, 'xemu');
    expect(io.File(p.join(folder!, 'Halo (USA).iso')).readAsBytesSync(), xiso());
    expect(io.File(p.join(folder, 'readme.txt')).readAsBytesSync(), [1, 2]);
  });

  test('an emulator that reads zips keeps the zip', () async {
    final snes = game(2, 'Mario', platform: 'snes', fsName: 'Mario.zip');
    final path = files.pathFor(snes);
    io.Directory(p.dirname(path)).createSync(recursive: true);
    io.File(path).writeAsBytesSync(ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('Mario.sfc', [1]))));
    expect(await preparer.ready(snes, path, 'retroarch'), isNull);
    expect(io.File(path).existsSync(), isTrue);
  });

  test('an arcade set stays a zip whatever plays it (the zip is the game)', () async {
    final set = game(3, '1943', platform: 'arcade', fsName: '1943.zip');
    final path = files.pathFor(set);
    io.Directory(p.dirname(path)).createSync(recursive: true);
    io.File(path).writeAsBytesSync(ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('bm01.12d', [1]))));
    expect(await preparer.ready(set, path, 'flycast'), isNull);
    expect(io.File(path).existsSync(), isTrue);
  });

  test('an emulator that cannot read zips gets the zip unpacked, as it is', () async {
    final ps2 = game(4, 'Okami', platform: 'ps2', fsName: 'Okami.zip');
    final path = files.pathFor(ps2);
    io.Directory(p.dirname(path)).createSync(recursive: true);
    io.File(path).writeAsBytesSync(ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('Okami.iso', [7, 7, 7]))));
    final folder = await preparer.ready(ps2, path, 'pcsx2');
    expect(io.File(p.join(folder!, 'Okami.iso')).readAsBytesSync(), [7, 7, 7]);
    expect(io.File(path).existsSync(), isFalse);
  });

  test('xemu: a zip whose disc is no Xbox image is refused and left as it was', () async {
    final zip = zipWith({'Halo (USA).iso': Uint8List(gp * 2)});
    await expectLater(preparer.ready(halo, zip, 'xemu'), throwsA(isA<NotAnXboxDisc>()));
    expect(io.File(zip).existsSync(), isTrue);
    expect(io.Directory(p.join(root.roms, 'xbox', 'Halo (USA)')).existsSync(), isFalse);
    expect(io.Directory(p.join(root.appData, 'temp')).listSync(), isEmpty);
  });

  test('a damaged zip is refused and left as it was', () async {
    final path = files.pathFor(halo);
    io.Directory(p.dirname(path)).createSync(recursive: true);
    io.File(path).writeAsBytesSync([1, 2, 3, 4]);
    await expectLater(preparer.ready(halo, path, 'xemu'), throwsA(isA<RomPrepareException>()));
    expect(io.File(path).existsSync(), isTrue);
  });

  test('xemu: a Redump .iso already on disk becomes an XISO in place', () async {
    final iso = p.join(root.roms, 'xbox', 'Halo (USA)', 'Halo (USA).iso');
    io.Directory(p.dirname(iso)).createSync(recursive: true);
    io.File(iso).writeAsBytesSync(redump(xiso()));
    expect(await preparer.ready(halo, iso, 'xemu'), isNull);
    expect(io.File(iso).readAsBytesSync(), xiso());
    expect(io.Directory(p.join(root.appData, 'temp')).listSync(), isEmpty);
  });

  test('xemu: an .iso that is no Xbox image is refused and left as it was', () async {
    final iso = p.join(root.roms, 'xbox', 'x.iso');
    io.Directory(p.dirname(iso)).createSync(recursive: true);
    io.File(iso).writeAsBytesSync(Uint8List(gp * 2));
    await expectLater(preparer.ready(halo, iso, 'xemu'), throwsA(isA<NotAnXboxDisc>()));
    expect(io.File(iso).lengthSync(), gp * 2);
  });

  test('RomFiles: an unpacked zip game is found, counted as downloaded and deleted as its folder', () async {
    final folder = io.Directory(p.join(root.roms, 'xbox', 'Halo (USA)'))..createSync(recursive: true);
    io.File(p.join(folder.path, 'Halo (USA).iso')).writeAsBytesSync([1]);
    expect(files.pathFor(halo), folder.path);
    expect(files.isDownloaded(halo), isTrue);
    await files.delete(halo, PathGuard(root));
    expect(folder.existsSync(), isFalse);
    expect(files.isDownloaded(halo), isFalse);
    // Not downloaded at all: the download still goes to the zip's name.
    expect(files.pathFor(halo), p.join(root.roms, 'xbox', 'Halo (USA).zip'));
  });
}
