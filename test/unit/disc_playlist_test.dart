import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/storage/rom_lookup_service.dart';
import 'package:gargosy/library/disc_playlist.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
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

  void file(String name, [int size = 10]) => io.File(p.join(folder, name)).writeAsBytesSync(List<int>.filled(size, 1));

  test('the discs in disc order, a .cue per disc when there are cues', () {
    file('FF7 (Disc 3).cue');
    file('FF7 (Disc 1).cue');
    file('FF7 (Disc 2).cue');
    file('FF7 (Disc 1).bin', 900);
    file('FF7 (Disc 10).cue');
    expect(
      [for (final d in DiscPlaylist.discsIn(folder)) p.basename(d)],
      ['FF7 (Disc 1).cue', 'FF7 (Disc 2).cue', 'FF7 (Disc 3).cue', 'FF7 (Disc 10).cue'],
    );
  });

  test('none for one disc, or a folder with its own playlist', () {
    file('Game.chd');
    expect(DiscPlaylist.discsIn(folder), isEmpty);
    file('Game (Disc 2).chd');
    file('Game.m3u');
    expect(DiscPlaylist.discsIn(folder), isEmpty);
  });

  test("the playlist goes in temp, named after disc 1, with the discs' full paths; only for those that take one", () {
    file('FF7 (Disc 2).chd');
    file('FF7 (Disc 1).chd');
    final rom = p.join(folder, 'FF7 (Disc 1).chd');
    final guard = PathGuard(root);
    final m3u = DiscPlaylist.writeFor(rom, emulatorId: 'retroarch', gameId: '7', root: root, guard: guard)!;
    expect(p.isWithin(DiscPlaylist.dir(root), m3u), isTrue);
    expect(p.basename(m3u), 'FF7 (Disc 1).m3u');
    expect(io.File(m3u).readAsLinesSync(), [p.join(folder, 'FF7 (Disc 1).chd'), p.join(folder, 'FF7 (Disc 2).chd')]);
    expect(io.Directory(folder).listSync().where((e) => e.path.endsWith('.m3u')), isEmpty, reason: 'never in roms');
    expect(DiscPlaylist.writeFor(rom, emulatorId: 'pcsx2', gameId: '7', root: root, guard: guard), isNull);
  });

  test('numbered discs without a playlist start on disc 1, not the largest', () async {
    file('FF7 (Disc 1).chd', 10);
    file('FF7 (Disc 2).chd', 900);
    final found = await RomLookupService.findMainRomInFolder(game(1, 'FF7', platform: 'psx'), folder);
    expect(p.basename(found!), 'FF7 (Disc 1).chd');
  });
}
