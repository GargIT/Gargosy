// Issue #8: a folder link next to an emulator's exe, pointed at the profile.
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/downloader/download_service.dart';
import 'package:gargosy/core/emulator/emulator_download_service.dart';
import 'package:gargosy/emulators/emulator_installer.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/emulators/folder_link.dart';
import 'package:gargosy/emulators/linked_folder_config.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

/// An update that unpacks a release with its own user\ folder into the install.
class _Unpacks extends Fake implements EmulatorDownloadService {
  _Unpacks(this.installDir);
  final String installDir;

  @override
  Stream<DownloadProgress> downloadEmulator(String emulatorId,
      {String? architecture, String? buildType, String? urlOverride, Object? cancelToken}) async* {
    io.File(p.join(installDir, 'user', 'config', 'qt-config.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('from the release zip');
    io.File(p.join(installDir, 'eden.exe')).writeAsStringSync('MZ new');
    yield DownloadProgress(id: emulatorId, gameName: 'Eden', percent: 1, isComplete: true, status: 'Done!');
  }
}

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => deleteTempDir(root.root));

  String install(String emu) => p.join(root.emulators, emu);
  String data(String profile, String emu) => ProfilePaths(root, profile).emulatorDir(emu);
  PathGuard guard(String profile) => PathGuard(root, activeProfileId: profile);
  String template(String emu, String folder) => p.join(root.templates, emu, folder);

  FolderLinkResult point(String profile, {String emu = 'eden', String folder = 'user'}) => pointFolderLink(
        link: p.join(install(emu), folder),
        target: p.join(data(profile, emu), folder),
        guard: guard(profile),
        templateDir: template(emu, folder),
      );

  void write(String path, String text) => io.File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  setUp(() => io.Directory(install('eden')).createSync(recursive: true));

  test('creates the link, and the profile\'s folder it points at', () {
    point('aaa');
    final link = p.join(install('eden'), 'user');
    expect(isFolderLink(link), isTrue);
    expect(io.Directory(p.join(data('aaa', 'eden'), 'user')).existsSync(), isTrue);
    write(p.join(link, 'nand', 'save.bin'), 'written through the link');
    expect(io.File(p.join(data('aaa', 'eden'), 'user', 'nand', 'save.bin')).readAsStringSync(), 'written through the link');
  });

  test('re-points to another profile; the first profile\'s data stays where it is', () {
    point('aaa');
    write(p.join(install('eden'), 'user', 'a.txt'), 'anna');
    point('bbb');
    final link = p.join(install('eden'), 'user');
    expect(io.File(p.join(link, 'a.txt')).existsSync(), isFalse, reason: "bbb doesn't see anna's file");
    expect(io.File(p.join(data('aaa', 'eden'), 'user', 'a.txt')).readAsStringSync(), 'anna');
  });

  test('pointing again at the same profile changes nothing', () {
    point('aaa');
    expect(point('aaa').movedToTemplate, isNull);
    expect(isFolderLink(p.join(install('eden'), 'user')), isTrue);
  });

  test('a real folder in the way is moved to the template, never deleted', () {
    write(p.join(install('eden'), 'user', 'nand', 'old.sav'), 'from an imported install');
    final result = point('aaa');
    expect(result.movedToTemplate, template('eden', 'user'));
    expect(io.File(p.join(template('eden', 'user'), 'nand', 'old.sav')).readAsStringSync(), 'from an imported install');
    expect(isFolderLink(p.join(install('eden'), 'user')), isTrue);
  });

  test('a second real folder, with the template taken, goes beside it: nothing is overwritten', () {
    write(p.join(template('eden', 'user'), 'keep.txt'), 'template');
    write(p.join(install('eden'), 'user', 'x.txt'), 'second');
    final result = point('aaa');
    expect(result.movedToTemplate, '${template('eden', 'user')} (2)');
    expect(io.File(p.join(template('eden', 'user'), 'keep.txt')).readAsStringSync(), 'template');
  });

  test('a file in the way is renamed aside', () {
    write(p.join(install('eden'), 'user'), 'a file named user');
    point('aaa');
    expect(io.File(p.join(install('eden'), 'user.gargosy-off')).readAsStringSync(), 'a file named user');
    expect(isFolderLink(p.join(install('eden'), 'user')), isTrue);
  });

  test("a link to somewhere outside the profile is replaced, and what it pointed at isn't touched", () {
    final elsewhere = io.Directory(p.join(root.root, 'elsewhere'))..createSync();
    write(p.join(elsewhere.path, 'precious.txt'), 'not ours');
    io.Link(p.join(install('eden'), 'user')).createSync(elsewhere.path);
    point('aaa');
    expect(io.Link(p.join(install('eden'), 'user')).targetSync(), p.join(data('aaa', 'eden'), 'user'));
    expect(io.File(p.join(elsewhere.path, 'precious.txt')).readAsStringSync(), 'not ours');
  });

  test('the link goes only in emulators\\, and points only into the active profile', () {
    expect(
      () => pointFolderLink(
          link: p.join(root.bios, 'user'), target: p.join(data('aaa', 'eden'), 'user'), guard: guard('aaa'), templateDir: template('eden', 'user')),
      throwsA(isA<PathGuardException>()),
    );
    expect(
      () => pointFolderLink(
          link: p.join(install('eden'), 'user'), target: p.join(data('bbb', 'eden'), 'user'), guard: guard('aaa'), templateDir: template('eden', 'user')),
      throwsA(isA<PathGuardException>()),
      reason: "another profile's folder",
    );
    expect(
      () => pointFolderLink(
          link: p.join(install('eden'), 'user'), target: p.join(root.roms, 'user'), guard: guard('aaa'), templateDir: template('eden', 'user')),
      throwsA(isA<PathGuardException>()),
    );
  });

  test('removeFolderLink removes the link only; a real folder is left', () {
    point('aaa');
    write(p.join(data('aaa', 'eden'), 'user', 'save.bin'), 'mine');
    expect(removeFolderLink(p.join(install('eden'), 'user')), isTrue);
    expect(io.FileSystemEntity.typeSync(p.join(install('eden'), 'user'), followLinks: false), io.FileSystemEntityType.notFound);
    expect(io.File(p.join(data('aaa', 'eden'), 'user', 'save.bin')).readAsStringSync(), 'mine');
    io.Directory(p.join(install('eden'), 'real')).createSync();
    expect(removeFolderLink(p.join(install('eden'), 'real')), isFalse);
    expect(io.Directory(p.join(install('eden'), 'real')).existsSync(), isTrue);
  });

  group('what must never follow the link', () {
    setUp(() {
      write(p.join(install('eden'), 'eden.exe'), 'MZ');
      point('aaa');
      write(p.join(data('aaa', 'eden'), 'user', 'nand', 'save.bin'), 'the profile\'s save');
    });

    test('Remove emulator deletes the install and keeps the profile\'s data', () async {
      await EmulatorLibrary(root, const []).remove('eden');
      expect(io.Directory(install('eden')).existsSync(), isFalse);
      expect(io.File(p.join(data('aaa', 'eden'), 'user', 'nand', 'save.bin')).readAsStringSync(), 'the profile\'s save');
    });

    test("an update whose zip has its own user\\ doesn't write into the profile", () async {
      final lib = EmulatorLibrary(root, const []);
      await GargosyEmulatorInstaller(_Unpacks(install('eden')), lib).install('eden', 'https://dl/eden.zip').toList();
      expect(io.File(p.join(data('aaa', 'eden'), 'user', 'config', 'qt-config.ini')).existsSync(), isFalse);
      expect(io.File(p.join(data('aaa', 'eden'), 'user', 'nand', 'save.bin')).readAsStringSync(), 'the profile\'s save');
    });

    test('importing over an install with a link keeps the profile\'s data', () async {
      final elsewhere = p.join(root.root, 'my-eden');
      write(p.join(elsewhere, 'eden.exe'), 'MZ imported');
      await EmulatorLibrary(root, const []).importFrom('eden', elsewhere).catchError((_) {});
      expect(io.File(p.join(data('aaa', 'eden'), 'user', 'nand', 'save.bin')).readAsStringSync(), 'the profile\'s save');
    });

    test('finding the exe never walks into the profile through the link', () async {
      write(p.join(data('aaa', 'eden'), 'user', 'eden.exe'), 'not the program');
      io.File(p.join(install('eden'), 'eden.exe')).deleteSync();
      final launch = ProfileLaunchDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
      expect(await launch.findEmulatorExecutable('eden', 'eden.exe'), isNull,
          reason: "the profile's file isn't the program");
      write(p.join(install('eden'), 'eden.exe'), 'MZ');
      expect(await launch.findEmulatorExecutable('eden', 'eden.exe'), p.join(install('eden'), 'eden.exe'));
    });

    test('removeFolderLinks: every link in the install, nothing else', () {
      io.Directory(p.join(install('eden'), 'sub')).createSync();
      io.Link(p.join(install('eden'), 'sub', 'portable')).createSync(p.join(data('aaa', 'eden'), 'user'));
      expect(EmulatorLibrary(root, const []).removeFolderLinks('eden'), 2);
      expect(io.File(p.join(install('eden'), 'eden.exe')).existsSync(), isTrue);
      expect(io.File(p.join(data('aaa', 'eden'), 'user', 'nand', 'save.bin')).existsSync(), isTrue);
    });
  });

  test('LinkedFolderConfig: prepare and repoint point the link, then run the emulator\'s own step', () async {
    LaunchContext ctx(String profile) => LaunchContext(
          data: data(profile, 'eden'),
          exeDir: install('eden'),
          bios: root.bios,
          profileId: profile,
          profilesDir: root.profiles,
          guard: guard(profile),
        );
    const config = LinkedFolderConfig('user');
    expect(await config.prepare(ctx('aaa')), isEmpty);
    expect(io.Link(p.join(install('eden'), 'user')).targetSync(), p.join(data('aaa', 'eden'), 'user'));
    config.repoint(ctx('bbb'));
    expect(io.Link(p.join(install('eden'), 'user')).targetSync(), p.join(data('bbb', 'eden'), 'user'));
    expect(config.gameArgs(ctx('bbb'), 'game.nsp'), ['game.nsp']);
  });
}
