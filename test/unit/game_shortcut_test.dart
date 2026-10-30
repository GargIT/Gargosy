import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/platform/shortcut_maker.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/game_shortcut.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

class _FakeMaker implements ShortcutMaker {
  _FakeMaker(this.desktop);
  final String? desktop;
  final made = <({String link, String target, List<String> args, String dir, String? icon})>[];

  @override
  String get extension => '.lnk';

  @override
  Future<String?> desktopDir() async => desktop;

  @override
  Future<void> make({
    required String linkPath,
    required String target,
    required List<String> args,
    required String workingDir,
    String? iconPath,
    String description = '',
  }) async {
    made.add((link: linkPath, target: target, args: args, dir: workingDir, icon: iconPath));
    io.File(linkPath).writeAsStringSync('link');
  }
}

void main() {
  late AppRoot root;
  late io.Directory desktop;
  final game = Game.fromJson(gameJson(7564, 'Burnout 3: Takedown', fsName: 'Burnout 3 (USA).chd'));

  setUp(() async {
    root = await tempAppRoot();
    desktop = await io.Directory.systemTemp.createTemp('desktop');
  });
  tearDown(() {
    io.Directory(root.root).deleteSync(recursive: true);
    desktop.deleteSync(recursive: true);
  });

  test('a name Windows takes', () {
    expect(shortcutName('Burnout 3: Takedown'), 'Burnout 3 Takedown');
    expect(shortcutName(r'A/B\C*?"<>|'), 'A B C');
    expect(shortcutName('Dots...'), 'Dots');
    expect(shortcutName(':::'), 'Game');
    expect(shortcutName('x' * 150).length, 100);
    expect(shortcutName('Con'), 'Con (game)');
    expect(shortcutName('lpt1'), 'lpt1 (game)');
    expect(shortcutName('Contra'), 'Contra');
  });

  test('a link never replaces a file on the desktop', () {
    expect(freeLinkPath(desktop.path, 'G', '.lnk'), p.join(desktop.path, 'G.lnk'));
    io.File(p.join(desktop.path, 'G.lnk')).writeAsStringSync('mine');
    io.File(p.join(desktop.path, 'G (2).lnk')).writeAsStringSync('mine');
    expect(freeLinkPath(desktop.path, 'G', '.lnk'), p.join(desktop.path, 'G (3).lnk'));
  });

  test('an .ico of one PNG: header, size, offset', () {
    final png = Uint8List.fromList(List.generate(40, (i) => i));
    final ico = icoOfPng(png);
    expect(ico.sublist(0, 6), [0, 0, 1, 0, 1, 0]);
    expect(ico.length, 22 + 40);
    expect(ByteData.sublistView(ico).getUint32(14, Endian.little), 40);
    expect(ByteData.sublistView(ico).getUint32(18, Endian.little), 22);
    expect(ico.sublist(22), png);
  });

  test('the link starts this game in this profile, its icon kept in the profile', () async {
    final maker = _FakeMaker(desktop.path);
    final paths = ProfilePaths(root, 'aaa');
    final exe = p.join(root.root, 'Gargosy.exe');
    final link = await createGameShortcut(
      game: game,
      profile: paths,
      maker: maker,
      exe: exe,
      iconPng: Uint8List.fromList([1, 2, 3]),
    );
    expect(link, p.join(desktop.path, 'Burnout 3 Takedown.lnk'));
    final m = maker.made.single;
    expect(m.target, exe);
    expect(m.args, ['--play=7564', '--profile=aaa']);
    expect(m.dir, root.root);
    expect(m.icon, p.join(paths.cache, 'shortcuts', '7564.ico'));
    expect(io.File(m.icon!).lengthSync(), 22 + 3);
  });

  test('a Gargosy on another folder than its exe passes it on with --root', () async {
    final maker = _FakeMaker(desktop.path);
    await createGameShortcut(game: game, profile: ProfilePaths(root, 'aaa'), maker: maker, exe: r'C:\dev\gargosy.exe');
    expect(maker.made.single.args, ['--play=7564', '--profile=aaa', '--root="${root.root}"']);
  });

  test('no cover: no icon; no desktop: refused', () async {
    final made = _FakeMaker(desktop.path);
    await createGameShortcut(game: game, profile: ProfilePaths(root, 'aaa'), maker: made, exe: 'G.exe');
    expect(made.made.single.icon, isNull);
    expect(
      () => createGameShortcut(game: game, profile: ProfilePaths(root, 'aaa'), maker: _FakeMaker(null), exe: 'G.exe'),
      throwsA(isA<io.FileSystemException>()),
    );
  });

  test('Windows: a real .lnk is made by the shell', () async {
    final maker = shortcutMakerFor(PlatformInfo.current);
    final link = p.join(desktop.path, 'Test${maker.extension}');
    await maker.make(
      linkPath: link,
      target: io.Platform.resolvedExecutable,
      args: const ['--play=1', '--profile=aaa'],
      workingDir: desktop.path,
    );
    expect(io.File(link).existsSync(), isTrue);
    // A file there already is never written over.
    final mine = p.join(desktop.path, 'Mine${maker.extension}');
    io.File(mine).writeAsStringSync('mine');
    await expectLater(
      maker.make(linkPath: mine, target: io.Platform.resolvedExecutable, args: const [], workingDir: desktop.path),
      throwsA(isA<io.FileSystemException>()),
    );
    expect(io.File(mine).readAsStringSync(), 'mine');
  }, skip: !io.Platform.isWindows);
}
