import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/disc_playlist.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late String folder;

  setUp(() async {
    root = await tempAppRoot();
    folder = p.join(root.roms, 'psx', 'Final Fantasy VII');
    io.Directory(folder).createSync(recursive: true);
  });
  tearDown(() => io.Directory(root.root).deleteSync(recursive: true));

  void file(String name, {String? dir}) => io.File(p.join(dir ?? folder, name)).writeAsBytesSync([1]);
  List<String> names(List<String> paths) => [for (final d in paths) p.basename(d)];

  test('one game\'s numbered discs in disc order, a .cue per disc when there are cues', () {
    for (final n in [3, 1, 10, 2]) {
      file('FF7 (Disc $n).cue');
    }
    file('FF7 (Disc 1).bin');
    expect(names(DiscPlaylist.discsIn(folder)), [
      'FF7 (Disc 1).cue',
      'FF7 (Disc 2).cue',
      'FF7 (Disc 3).cue',
      'FF7 (Disc 10).cue',
    ]);
  });

  test('a CloneCD disc counts once (its .ccd), not with its .img', () {
    file('Game (Disc 1).ccd');
    file('Game (Disc 1).img');
    file('Game (Disc 2).ccd');
    file('Game (Disc 2).img');
    expect(names(DiscPlaylist.discsIn(folder)), ['Game (Disc 1).ccd', 'Game (Disc 2).ccd']);
  });

  test("none for one disc, its own playlist, discs without numbers, or a platform's folder of games", () {
    file('Game.chd');
    expect(DiscPlaylist.discsIn(folder), isEmpty);
    file('Other.chd');
    expect(DiscPlaylist.discsIn(folder), isEmpty, reason: 'no numbers');
    final platform = p.join(root.roms, 'psx');
    file('Crash (Disc 1).chd', dir: platform);
    file('Spyro (Disc 1).chd', dir: platform);
    expect(DiscPlaylist.discsIn(platform), isEmpty, reason: 'two games, not one');
    file('A (CD32).iso');
    file('B (CD32).iso');
    expect(DiscPlaylist.discNumber('Game (CD32)'), isNull);
    io.Directory(folder).deleteSync(recursive: true);
    io.Directory(folder).createSync();
    file('Game (Disc 1).chd');
    file('Game (Disc 2).chd');
    file('Game.m3u');
    expect(DiscPlaylist.discsIn(folder), isEmpty, reason: 'its own playlist');
  });

  test('the playlist goes in temp, named after the disc it starts from, the discs in order; never in roms', () {
    file('FF7 (Disc 2).chd');
    file('FF7 (Disc 1).chd');
    final started = p.join(folder, 'FF7 (Disc 2).chd');
    final m3u = DiscPlaylist.writeFor(started, gameId: '7', root: root, guard: PathGuard(root))!;
    expect(p.isWithin(DiscPlaylist.dir(root), m3u), isTrue);
    expect(p.basename(m3u), 'FF7 (Disc 2).m3u', reason: 'saves keep the name they had');
    expect(io.File(m3u).readAsLinesSync(), [p.join(folder, 'FF7 (Disc 1).chd'), started]);
    expect(io.Directory(folder).listSync().where((e) => e.path.endsWith('.m3u')), isEmpty);
    DiscPlaylist.remove(m3u);
    expect(io.Directory(p.dirname(m3u)).existsSync(), isFalse);
  });

  test("a ROM that isn't one of the folder's discs, or a folder that can't be read: no playlist", () {
    file('FF7 (Disc 1).chd');
    file('FF7 (Disc 2).chd');
    file('Readme.chd');
    expect(
      DiscPlaylist.writeFor(p.join(folder, 'FF7 (Disc 1).chd'), gameId: '7', root: root, guard: PathGuard(root)),
      isNull,
      reason: 'Readme has no number: not one game of numbered discs',
    );
    expect(
      DiscPlaylist.writeFor(p.join(root.roms, 'nowhere', 'x.chd'), gameId: '7', root: root, guard: PathGuard(root)),
      isNull,
    );
  });
}
