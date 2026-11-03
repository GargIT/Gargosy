import 'dart:async';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/game_videos.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

Game _game(String id, {String? video = 'roms/1/2/video/video.mp4'}) =>
    Game.fromJson({'id': int.parse(id), 'name': 'Game $id', 'platform_slug': 'ps2', 'path_video': video});

void main() {
  late String root;
  late PathGuard guard;
  final fetched = <String>[];

  setUp(() async {
    final at = await tempAppRoot();
    addTearDown(() => io.Directory(at.root).deleteSync(recursive: true));
    guard = PathGuard(at);
    root = videoCacheDir(at);
    fetched.clear();
  });

  GameVideos videos({
    int maxBytes = GameVideos.defaultMaxBytes,
    bool fail = false,
    int bytes = 10,
    String server = 'a',
    bool Function()? may,
    Completer<void>? hold,
  }) => GameVideos(
    guard: guard,
    root: root,
    dir: p.join(root, server),
    maxBytes: maxBytes,
    mayDownload: may,
    download: (path, to, {cancel}) async {
      fetched.add(path);
      if (hold != null) {
        await Future.any([hold.future, cancel!.whenCancel]);
        if (cancel.isCancelled) {
          throw DioException(requestOptions: RequestOptions(), type: DioExceptionType.cancel);
        }
      }
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
    expect(p.basename(file!), videoFileName(_game('1')));
    expect(io.File(file).existsSync(), isTrue);
    expect(await v.fileFor(_game('1')), file);
    expect(fetched, hasLength(1));
    expect(await v.kept(_game('1')), file);
  });

  test('a video RomM replaced is another file, fetched again', () {
    expect(videoFileName(_game('1')), isNot(videoFileName(_game('1', video: 'roms/1/2/video/new.mp4'))));
  });

  test('one download at a time: a second ask of the same game waits for it, another game gets none', () async {
    final hold = Completer<void>();
    final v = videos(hold: hold);
    final first = v.fileFor(_game('1'));
    final same = v.fileFor(_game('1'));
    expect(await v.fileFor(_game('2')), isNull);
    hold.complete();
    expect(await first, isNotNull);
    expect(await same, await first);
    expect(fetched, hasLength(1));
  });

  test('a page left stops its download, and it is asked again next time', () async {
    final hold = Completer<void>();
    final v = videos(hold: hold);
    final first = v.fileFor(_game('1'));
    await Future<void>.delayed(Duration.zero);
    v.cancel(_game('1'));
    expect(await first, isNull);
    hold.complete();
    expect(await v.fileFor(_game('1')), isNotNull, reason: 'a cancel is not a failure');
  });

  test('nothing is fetched while it may not download (a ROM downloading, limits, RomM away)', () async {
    final v = videos(may: () => false);
    expect(await v.fileFor(_game('1')), isNull);
    expect(fetched, isEmpty);
  });

  test('a failed download leaves nothing and isn\'t asked again this session; without RomM none', () async {
    final v = videos(fail: true);
    expect(await v.fileFor(_game('1')), isNull);
    expect(await v.fileFor(_game('1')), isNull);
    expect(fetched, hasLength(1));
    expect(io.Directory(p.join(root, 'a')).listSync(), isEmpty);
    expect(await GameVideos(guard: guard, root: root, dir: p.join(root, 'a')).fileFor(_game('2')), isNull);
  });

  test('past the limit, across servers, the video played longest ago goes, never the one just fetched; '
      'a partial one a crash left goes too', () async {
    final a = videos(maxBytes: 25), b = videos(maxBytes: 25, server: 'b');
    await a.fileFor(_game('1'));
    await a.trimmed;
    final old = io.File(p.join(root, 'a', videoFileName(_game('1'))))..setLastModifiedSync(DateTime(2020));
    final part = io.File(p.join(root, 'a', '9.mp4.part'))
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(DateTime(2020));
    await a.fileFor(_game('2'));
    await a.trimmed;
    await b.fileFor(_game('3'));
    await b.trimmed;
    expect(old.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
    expect(io.File(p.join(root, 'a', videoFileName(_game('2')))).existsSync(), isTrue);
    expect(io.File(p.join(root, 'b', videoFileName(_game('3')))).existsSync(), isTrue);
  });

  test('one server written two ways is one folder', () {
    expect(videoServerKey('https://romm.example/'), videoServerKey('https://ROMM.example'));
    expect(videoServerKey('https://romm.example:443'), videoServerKey('https://romm.example'));
    expect(videoServerKey('https://romm.example'), isNot(videoServerKey('https://other.example')));
  });
}
