import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/game_videos.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/providers/video_providers.dart';
import 'package:gargosy/ui/widgets/video_preview.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

final _okami = Game.fromJson({'id': 7, 'name': 'Okami', 'path_video': 'roms/1/7/video/video.mp4'});
final _ico = Game.fromJson({'id': 8, 'name': 'Ico'});

void main() {
  late GameVideos videos;

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Game game, {
    bool on = true,
    bool active = true,
    bool keptOnly = false,
  }) async {
    final root = await tester.runAsync(tempAppRoot);
    addTearDown(() => io.Directory(root!.root).deleteSync(recursive: true));
    videos = GameVideos(
      guard: PathGuard(root!),
      dir: p.join(videoCacheDir(root), 's'),
      download: (path, to) async => io.File(to).writeAsBytesSync([1, 2, 3]),
    );
    await tester.pumpWidget(
      testApp(
        SizedBox(
          width: 400,
          height: 300,
          child: VideoPreview(game: game, active: active, keptOnly: keptOnly),
        ),
        overrides: [
          videoSurfaceProvider.overrideWithValue((file) => Text('video:${p.basename(file)}')),
          gameVideosProvider.overrideWithValue(videos),
          videoPreviewsOnProvider.overrideWithValue(on),
        ],
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(VideoPreview)));
  }

  Future<void> wait(WidgetTester tester, Duration d) async {
    await tester.pump(d);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('after 1.5 s the game\'s video fades in; not before', (tester) async {
    await pump(tester, _okami);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('video:7.mp4'), findsNothing);
    await wait(tester, const Duration(milliseconds: 600));
    expect(find.text('video:7.mp4'), findsOneWidget);
  });

  testWidgets('nothing for a game without a video, with previews off, or on another tab', (tester) async {
    await pump(tester, _ico);
    await wait(tester, const Duration(seconds: 2));
    expect(find.textContaining('video:'), findsNothing);

    await pump(tester, _okami, on: false);
    await wait(tester, const Duration(seconds: 2));
    expect(find.textContaining('video:'), findsNothing);

    await pump(tester, _okami, active: false);
    await wait(tester, const Duration(seconds: 2));
    expect(find.textContaining('video:'), findsNothing);
  });

  testWidgets('a game started stops it', (tester) async {
    final c = await pump(tester, _okami);
    await wait(tester, const Duration(seconds: 2));
    expect(find.text('video:7.mp4'), findsOneWidget);
    c.read(playControllerProvider.notifier).state = const PlayState(runningGameId: '9');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('video:'), findsNothing);
  });

  testWidgets('the screensaver plays only a video already on this PC', (tester) async {
    await pump(tester, _okami, keptOnly: true);
    await wait(tester, const Duration(seconds: 2));
    expect(find.textContaining('video:'), findsNothing, reason: 'not downloaded for a slide');
  });
}
