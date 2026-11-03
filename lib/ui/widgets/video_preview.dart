import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/romm/romm_models.dart';
import '../../play/play_controller.dart';
import '../../providers/video_providers.dart';

/// How a video file is shown, muted and looping, filling its box; tests
/// replace it (no player there).
final videoSurfaceProvider = Provider<Widget Function(String file)>(
  (ref) =>
      (file) => _PlayerSurface(file: file),
);

/// A game's video behind its page or the screensaver (#238): after [delay],
/// when previews are on, the game has one and no game runs, it fades in,
/// muted and looping. [active] false (another tab, the page under another)
/// stops it. [keptOnly]: only a video already on this PC (the screensaver's
/// slides are too short to wait for a download).
class VideoPreview extends ConsumerStatefulWidget {
  const VideoPreview({
    super.key,
    required this.game,
    this.active = true,
    this.delay = const Duration(milliseconds: 1500),
    this.keptOnly = false,
  });

  final Game game;
  final bool active;
  final Duration delay;
  final bool keptOnly;

  @override
  ConsumerState<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends ConsumerState<VideoPreview> {
  Timer? _wait;
  String? _file;

  /// Bumped when what to show changes, so a late download doesn't show.
  int _ask = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(VideoPreview old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.game.id != widget.game.id) _start();
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  bool get _allowed =>
      widget.active &&
      widget.game.hasVideo &&
      ref.read(videoPreviewsOnProvider) &&
      ref.read(playControllerProvider).runningGameId == null;

  void _start() {
    _wait?.cancel();
    final ask = ++_ask;
    if (_file != null) setState(() => _file = null);
    if (!_allowed) return;
    _wait = Timer(widget.delay, () async {
      final videos = ref.read(gameVideosProvider);
      if (videos == null || !_allowed) return;
      final file = widget.keptOnly ? videos.kept(widget.game) : await videos.fileFor(widget.game);
      if (!mounted || ask != _ask || file == null || !_allowed) return;
      setState(() => _file = file);
    });
  }

  @override
  Widget build(BuildContext context) {
    // A game started stops it; previews turned off too.
    ref.listen(playControllerProvider.select((s) => s.runningGameId), (_, _) => _start());
    ref.listen(videoPreviewsOnProvider, (_, _) => _start());
    final file = _file;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: file == null
          ? const SizedBox.expand(key: ValueKey('no-video'))
          : KeyedSubtree(key: ValueKey('video:$file'), child: ref.read(videoSurfaceProvider)(file)),
    );
  }
}

class _PlayerSurface extends StatefulWidget {
  const _PlayerSurface({required this.file});

  final String file;

  @override
  State<_PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<_PlayerSurface> {
  late final _player = VideoPlayerController.file(io.File(widget.file));
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _player.initialize().then((_) async {
      if (!mounted) return;
      await _player.setVolume(0);
      await _player.setLooping(true);
      await _player.play();
      if (mounted) setState(() => _ready = true);
    }, onError: (Object e) => debugPrint('[Video] ${widget.file}: $e'));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    final size = _player.value.size;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(_player)),
      ),
    );
  }
}
