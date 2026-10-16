// Issue #11: ScummVM's saves, one folder per game, synced with RomM.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/scummvm_save_strategy.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late ScummVmSaveStrategy strategy;
  late String saves;
  setUp(() async {
    root = await tempAppRoot();
    final paths = ProfilePaths(root, 'aaa');
    strategy = ScummVmSaveStrategy(ProfileSaveDirectories(root: root, paths: paths, prefs: MemoryPrefs()));
    saves = p.join(paths.emulatorDir('scummvm'), 'saves');
  });
  tearDown(() => deleteTempDir(root.root));

  final game = Game(id: '7', name: 'Beneath a Steel Sky', fsName: 'bass-cd-1.2', platformSlug: 'scummvm', fileSize: 0);
  String rom(String name) => p.join(root.roms, 'scummvm', name);

  test("a game's save folder is named after it in roms\\scummvm, whatever path inside it is given", () {
    expect(scummVmSaveFolderName(rom('bass-cd-1.2')), 'bass-cd-1.2');
    expect(scummVmSaveFolderName(p.join(rom('Monkey Island'), 'monkey.scummvm')), 'Monkey Island');
    expect(scummVmSaveFolderName(p.join(rom('Monkey Island (1990)'), 'Monkey Island', 'MONKEY.000')), 'Monkey Island (1990)');
    expect(scummVmSaveFolderName(rom('Loom.zip')), 'Loom');
    expect(scummVmSaveFolderName(rom('loom.scummvm')), 'loom.scummvm');
  });

  test("the save code is registered: getSaveDir is the game's own folder in the profile", () async {
    expect(strategy.supportsSaveSync, isTrue);
    expect(await strategy.getSaveDir(game, rom('bass-cd-1.2')), p.join(saves, 'bass-cd-1.2'));
  });

  test("the game's saves are its folder's files; another game's and ScummVM's timestamps are left out", () async {
    final mine = io.Directory(p.join(saves, 'bass-cd-1.2'))..createSync(recursive: true);
    io.File(p.join(mine.path, 'SKY-VM.001')).writeAsStringSync('save 1');
    io.File(p.join(mine.path, 'SKY-VM.SAV')).writeAsStringSync('names');
    io.File(p.join(mine.path, 'timestamps')).writeAsStringSync('SKY-VM.001 1');
    io.File(p.join(saves, 'Monkey Island', 'monkey1.001')).createSync(recursive: true);
    io.File(p.join(saves, 'loose.001')).writeAsStringSync('before #11');
    final files = await strategy.getSaveFiles(game, rom('bass-cd-1.2'));
    expect(files.map((f) => p.basename(f.path)), ['SKY-VM.001', 'SKY-VM.SAV']);
  });

  test('nothing changed this session: nothing to upload', () async {
    io.File(p.join(saves, 'bass-cd-1.2', 'SKY-VM.001')).createSync(recursive: true);
    final later = DateTime.now().add(const Duration(minutes: 1));
    expect(await strategy.getSaveFiles(game, rom('bass-cd-1.2'), sessionStart: later), isEmpty);
    expect(await strategy.getSaveFiles(game, rom('bass-cd-1.2'), sessionStart: DateTime.now().subtract(const Duration(minutes: 1))),
        hasLength(1));
  });

  test("a pulled zip goes into the game's folder, plain names only, without the sync metadata", () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('SKY-VM.001', Uint8List.fromList([1, 2])))
      ..addFile(ArchiveFile.bytes('../../evil.001', Uint8List.fromList([3])))
      ..addFile(ArchiveFile.bytes('freegosy_sync.txt', Uint8List.fromList([4])));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(await strategy.restoreSave(game, rom('bass-cd-1.2'), zip, 'save.zip'), isTrue);
    final dir = p.join(saves, 'bass-cd-1.2');
    expect(io.File(p.join(dir, 'SKY-VM.001')).readAsBytesSync(), [1, 2]);
    expect(io.File(p.join(dir, 'evil.001')).existsSync(), isTrue, reason: 'its name only, inside the folder');
    expect(io.File(p.join(saves, 'evil.001')).existsSync(), isFalse);
    expect(io.File(p.join(dir, 'freegosy_sync.txt')).existsSync(), isFalse);
  });

  test('a pulled single file goes into the game\'s folder', () async {
    expect(await strategy.restoreSave(game, rom('bass-cd-1.2'), Uint8List.fromList([9]), 'SKY-VM.002'), isTrue);
    expect(io.File(p.join(saves, 'bass-cd-1.2', 'SKY-VM.002')).readAsBytesSync(), [9]);
  });
}
