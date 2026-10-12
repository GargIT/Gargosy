// Issues #12–#15: Eden, Azahar, Cemu and melonDS on a profile's own data,
// through a folder link next to the exe (#8).
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/melonds_save_strategy.dart';
import 'package:gargosy/core/storage/ini_file.dart';
import 'package:gargosy/emulators/config_files.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/fullscreen.dart';
import 'package:gargosy/emulators/linked_emulators.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => deleteTempDir(root.root));

  LaunchContext ctx(String emu, {String profile = 'aaa', List<String> gameFolders = const []}) {
    final exeDir = p.join(root.emulators, emu);
    io.Directory(exeDir).createSync(recursive: true);
    return LaunchContext(
      data: ProfilePaths(root, profile).emulatorDir(emu),
      exeDir: exeDir,
      bios: root.bios,
      profileId: profile,
      profilesDir: root.profiles,
      guard: PathGuard(root, activeProfileId: profile),
      roms: root.roms,
      gameFolders: gameFolders,
    );
  }

  void write(String path, String text) => io.File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  String read(String path) => io.File(path).readAsStringSync();
  String linkTarget(String path) => io.Link(path).targetSync();

  test('all four are supported, each with a full-screen flag', () {
    for (final id in ['eden', 'azahar', 'cemu', 'melonds']) {
      expect(ProfileLaunchConfig.supported, contains(id));
      expect(Fullscreen.supports(id), isTrue, reason: id);
    }
  });

  group('Eden (#12)', () {
    test('user\\ is a link to the profile; the keys from bios\\ arrive in user\\keys', () async {
      write(p.join(root.bios, 'switch', 'prod.keys'), 'prod');
      write(p.join(root.bios, 'title.keys'), 'title');
      final c = ctx('eden');
      expect(await ProfileLaunchConfig.of('eden')!.prepare(c), isEmpty);
      expect(linkTarget(p.join(c.exeDir, 'user')), p.join(c.data, 'user'));
      expect(read(p.join(c.data, 'user', 'keys', 'prod.keys')), 'prod');
      expect(read(p.join(c.data, 'user', 'keys', 'title.keys')), 'title');
    });

    test("roms\\switch joins Eden's game list once it has one; other keys are kept", () async {
      final c = ctx('eden', gameFolders: [p.join(root.roms, 'switch')]);
      final ini = p.join(c.data, 'user', 'config', 'qt-config.ini');
      write(ini, '[UI]\nPaths\\gamedirs\\1\\path=SDMC\nPaths\\gamedirs\\2\\path=UserNAND\nPaths\\gamedirs\\size=2\ntheme=dark\n');
      await ProfileLaunchConfig.of('eden')!.prepare(c);
      await ProfileLaunchConfig.of('eden')!.prepare(c); // twice: listed once
      final text = IniFile(read(ini));
      expect(text.get('UI', r'Paths\gamedirs\size'), '3');
      expect(text.get('UI', r'Paths\gamedirs\3\path'), p.join(root.roms, 'switch').replaceAll(r'\', '/'));
      expect(text.get('UI', r'Paths\gamedirs\1\path'), 'SDMC');
      expect(text.get('UI', 'theme'), 'dark');
    });

    test('before its first run (no qt-config.ini) nothing is written: its own defaults come first', () async {
      final c = ctx('eden', gameFolders: [p.join(root.roms, 'switch')]);
      await ProfileLaunchConfig.of('eden')!.prepare(c);
      expect(io.File(p.join(c.data, 'user', 'config', 'qt-config.ini')).existsSync(), isFalse);
    });

    test("the save code's install is <data>, so its user\\nand\\user\\save is the profile's", () async {
      expect(EmulatorLayout.of('eden').saveView, '');
      final dirs = ProfileSaveDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
      final exe = await dirs.findEmulatorExecutable('eden', 'eden.exe');
      expect(p.dirname(exe!), ProfilePaths(root, 'aaa').emulatorDir('eden'));
    });
  });

  group('Azahar (#13)', () {
    test('user\\ is a link; aes_keys.txt and seeddb.bin arrive in user\\sysdata', () async {
      write(p.join(root.bios, '3ds', 'aes_keys.txt'), 'keys');
      write(p.join(root.bios, '3ds', 'seeddb.bin'), 'seeds');
      final c = ctx('azahar');
      await ProfileLaunchConfig.of('azahar')!.prepare(c);
      expect(linkTarget(p.join(c.exeDir, 'user')), p.join(c.data, 'user'));
      expect(read(p.join(c.data, 'user', 'sysdata', 'aes_keys.txt')), 'keys');
      expect(read(p.join(c.data, 'user', 'sysdata', 'seeddb.bin')), 'seeds');
    });

    test('no keys in bios\\: nothing placed, the launch still goes ahead', () async {
      final c = ctx('azahar');
      await ProfileLaunchConfig.of('azahar')!.prepare(c);
      expect(io.File(p.join(c.data, 'user', 'sysdata', 'aes_keys.txt')).existsSync(), isFalse);
    });
  });

  group('Cemu (#14)', () {
    test('portable\\ is a link; the MLC is the profile\'s own (-m); keys.txt arrives', () async {
      write(p.join(root.bios, 'wiiu', 'keys.txt'), 'wiiu keys');
      final c = ctx('cemu');
      final args = await ProfileLaunchConfig.of('cemu')!.prepare(c);
      expect(args, ['-m', p.join(c.data, 'mlc01')]);
      expect(linkTarget(p.join(c.exeDir, 'portable')), p.join(c.data, 'portable'));
      expect(read(p.join(c.data, 'portable', 'keys.txt')), 'wiiu keys');
      expect(io.Directory(p.join(c.data, 'mlc01')).existsSync(), isTrue);
    });

    test('a settings.xml beside the exe is turned off, never deleted', () async {
      final c = ctx('cemu');
      write(p.join(c.exeDir, 'settings.xml'), '<content/>');
      await ProfileLaunchConfig.of('cemu')!.prepare(c);
      expect(io.File(p.join(c.exeDir, 'settings.xml')).existsSync(), isFalse);
      expect(read(p.join(c.exeDir, 'settings.xml.gargosy-off')), '<content/>');
    });

    test('roms\\wiiu joins GamePaths in the profile\'s settings.xml', () async {
      final c = ctx('cemu', gameFolders: [p.join(root.roms, 'wiiu')]);
      write(p.join(c.data, 'portable', 'settings.xml'), '<?xml version="1.0"?><content><GamePaths/><fullscreen>true</fullscreen></content>');
      await ProfileLaunchConfig.of('cemu')!.prepare(c);
      final xml = read(p.join(c.data, 'portable', 'settings.xml'));
      expect(xml, contains('<GamePaths><Entry>${p.join(root.roms, 'wiiu')}</Entry></GamePaths>'));
      expect(xml, contains('<fullscreen>true</fullscreen>'));
    });

    test('addCemuGamePaths: kept entries, a missing GamePaths, escaping', () {
      expect(addCemuGamePaths('<content><GamePaths><Entry>D:\\roms\\wiiu</Entry></GamePaths></content>', [r'D:\roms\wiiu']),
          '<content><GamePaths><Entry>D:\\roms\\wiiu</Entry></GamePaths></content>');
      expect(addCemuGamePaths('<content><a/></content>', [r'D:\R&D']),
          '<content><a/><GamePaths><Entry>D:\\R&amp;D</Entry></GamePaths></content>');
      expect(addCemuGamePaths('<content><GamePaths><Entry>x</Entry></GamePaths></content>', ['y']),
          '<content><GamePaths><Entry>y</Entry><Entry>x</Entry></GamePaths></content>');
    });

    test("two profiles' MLCs differ", () async {
      final a = await ProfileLaunchConfig.of('cemu')!.prepare(ctx('cemu', profile: 'aaa'));
      final b = await ProfileLaunchConfig.of('cemu')!.prepare(ctx('cemu', profile: 'bbb'));
      expect(a.last, isNot(b.last));
    });
  });

  group('melonDS (#15)', () {
    test('portable\\ is a link; saves and states in the profile, never next to the ROM', () async {
      final c = ctx('melonds');
      await ProfileLaunchConfig.of('melonds')!.prepare(c);
      expect(linkTarget(p.join(c.exeDir, 'portable')), p.join(c.data, 'portable'));
      final toml = read(p.join(c.data, 'portable', 'melonDS.toml'));
      expect(toml, contains('[Instance0]'));
      expect(toml, contains("SaveFilePath = '${p.join(c.data, 'portable', 'saves')}'"));
      expect(toml, contains("SavestatePath = '${p.join(c.data, 'portable', 'states')}'"));
      expect(toml, isNot(contains(root.roms)));
    });

    test('BIOS paths only for the files that are there; other keys are kept', () async {
      write(p.join(root.bios, 'nds', 'bios7.bin'), '7');
      write(p.join(root.bios, 'nds', 'bios9.bin'), '9');
      final c = ctx('melonds');
      write(p.join(c.data, 'portable', 'melonDS.toml'), "[Instance0.Window0]\nWidth = 512\n\n[Emu]\nDirectBoot = true\n");
      await ProfileLaunchConfig.of('melonds')!.prepare(c);
      final toml = read(p.join(c.data, 'portable', 'melonDS.toml'));
      expect(toml, contains("BIOS7Path = '${p.join(root.bios, 'nds', 'bios7.bin')}'"));
      expect(toml, contains("BIOS9Path = '${p.join(root.bios, 'nds', 'bios9.bin')}'"));
      expect(toml, isNot(contains('FirmwarePath')));
      expect(toml, contains('Width = 512'));
      expect(toml, contains('DirectBoot = true'));
    });

    test("the save code reads the profile's saves folder, not roms\\", () async {
      final paths = ProfilePaths(root, 'aaa');
      final strategy = MelonDsSaveStrategy(ProfileSaveDirectories(root: root, paths: paths, prefs: MemoryPrefs()));
      final game = Game(id: '1', name: 'Mario', fsName: 'Mario.nds', platformSlug: 'nds', fileSize: 0);
      final dir = await strategy.getSaveDir(game, p.join(root.roms, 'nds', 'Mario.nds'));
      expect(dir, p.join(paths.emulatorDir('melonds'), 'portable', 'saves'));
      final other = await MelonDsSaveStrategy(
              ProfileSaveDirectories(root: root, paths: ProfilePaths(root, 'bbb'), prefs: MemoryPrefs()))
          .getSaveDir(game, p.join(root.roms, 'nds', 'Mario.nds'));
      expect(other, isNot(dir));
    });
  });

  group('addQtArrayPaths', () {
    test('appends after the last entry and updates size; a listed folder (any slash or case) is kept once', () {
      final ini = IniFile('[UI]\nPaths\\gamedirs\\1\\path=D:/Roms/Switch\nPaths\\gamedirs\\size=1\n');
      expect(addQtArrayPaths(ini, 'UI', r'Paths\gamedirs', [r'd:\roms\switch', r'E:\more']), isTrue);
      expect(ini.get('UI', r'Paths\gamedirs\size'), '2');
      expect(ini.get('UI', r'Paths\gamedirs\2\path'), 'E:/more');
      expect(ini.get('UI', r'Paths\gamedirs\2\deep_scan'), 'false');
    });

    test('no array yet: false, nothing written', () {
      final ini = IniFile('[UI]\ntheme=dark\n');
      expect(addQtArrayPaths(ini, 'UI', r'Paths\gamedirs', ['x']), isFalse);
      expect(ini.toText(), '[UI]\ntheme=dark\n');
    });
  });
}
