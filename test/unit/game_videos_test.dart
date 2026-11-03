import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/game_videos.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

Game _game(String id, {String? video = 'roms/1/2/video/video.mp4'}) =>
    Game.fromJson({'id': int.parse(id), 'name': 'Game $id', 'platform_slug': 'ps2', 'path_video': video});

void main() {
  late String dir;
  late PathGuard guard;
  final fetched = <String>[];

  setUp(() async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    guard = PathGuard(root);
    dir = p.join(videoCacheDir(root), 'server');
    fetched.clear();
  });

  GameVideos videos({int maxBytes = GameVideos.defaultMaxBytes, bool fail = false, int bytes = 10}) => GameVideos(
    guard: guard,
    dir: dir,
    maxBytes: maxBytes,
    download: (path, to) async {
      fetched.add(path);
      if (fail) throw StateError('404');
      io.File(to).writeAsBytesSync(List.filled(bytes, 1));
    },
  );

  test('RomM\'s path_video (or ScreenScraper\'s video_path) is the game\'s video; an MP4 only', () {
    expect(_game('1').hasVideo, isTrue);
    expect(_game('1', video: null).hasVideo, isFalse);
    expect(_game('1', video: 'roms/1/2/video/clip.webm').hasVideo, isFalse);
    final nested = Game.fromJson({
      'id': 3,
      'name': 'x',
      'ss_metadata': {'video_path': 'roms/3/3/video/video.mp4'},
    });
    expect(nested.pathVideo, 'roms/3/3/video/video.mp4');
    expect(Game.fromJson(_game('1').toJson()).pathVideo, 'roms/1/2/video/video.mp4', reason: 'kept in the snapshot');
  });

  test('fetched once, kept on this PC, and played from there after', () async {
    final v = videos();
    final file = await v.fileFor(_game('1'));
    expect(file, p.join(dir, '1.mp4'));
    expect(io.File(file!).existsSync(), isTrue);
    expect(await v.fileFor(_game('1')), file);
    expect(fetched, hasLength(1));
    expect(v.kept(_game('1')), file);
  });

  test('two asks while it downloads are one download', () async {
    final v = videos();
    final both = await Future.wait([v.fileFor(_game('1')), v.fileFor(_game('1'))]);
    expect(both[0], both[1]);
    expect(fetched, hasLength(1));
  });

  test('a failed download leaves nothing and isn\'t asked again this session; without RomM none', () async {
    final v = videos(fail: true);
    expect(await v.fileFor(_game('1')), isNull);
    expect(await v.fileFor(_game('1')), isNull);
    expect(fetched, hasLength(1));
    expect(io.Directory(dir).listSync(), isEmpty);
    expect(await GameVideos(guard: guard, dir: dir).fileFor(_game('2')), isNull);
  });

  test('past the size limit the video played longest ago goes, never the one just fetched', () async {
    final v = videos(maxBytes: 25);
    await v.fileFor(_game('1'));
    io.File(p.join(dir, '1.mp4')).setLastModifiedSync(DateTime(2020));
    await v.fileFor(_game('2'));
    await v.fileFor(_game('3'));
    expect(io.File(p.join(dir, '1.mp4')).existsSync(), isFalse);
    expect(io.File(p.join(dir, '2.mp4')).existsSync(), isTrue);
    expect(io.File(p.join(dir, '3.mp4')).existsSync(), isTrue);
  });
}
