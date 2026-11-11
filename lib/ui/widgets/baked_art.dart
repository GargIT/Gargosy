import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'romm_images.dart';

/// How an art URL becomes an image to bake: through the RomM image cache,
/// decoded no larger than a baked picture needs. Tests give null: no art.
final artImageProvider = Provider<ImageProvider? Function(String url)>((ref) {
  final cache = ref.watch(rommImageCacheProvider);
  return (url) => ResizeImage(
    CachedNetworkImageProvider(url, cacheManager: cache),
    width: 640,
    policy: ResizeImagePolicy.fit,
    allowUpscaling: false,
  );
});

/// A game's art, blurred, dimmed and (with [shade]) darkened towards the
/// bottom, the way `GameArtBackdrop` shows it behind a page (#310).
///
/// Drawn once into a picture an eighth of the page's size and stretched over
/// it: a blur and a gradient worked out over the whole window on every frame
/// made Home half as fast again on an integrated GPU. The art is soft, so the
/// stretched picture looks the same.
class BakedArt extends ConsumerStatefulWidget {
  const BakedArt({super.key, required this.url, this.quick, required this.blur, required this.shade, this.onShown});

  final String url;

  /// A picture likely at hand already (the game's cover, which the page
  /// shows), drawn the same way until [url]'s has come.
  final String? quick;

  /// Once something is drawn, or nothing can be.
  final VoidCallback? onShown;

  /// The blur's sigma at the page's size.
  final double blur;

  /// The page's shade over the art: clear-ish at the top, the page's colour
  /// at the bottom.
  final bool shade;

  /// The shade [BakedArt] draws, for pages that draw it themselves (over a
  /// video).
  static const shadeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x6607070F), GColors.bg],
  );

  @override
  ConsumerState<BakedArt> createState() => _BakedArtState();
}

class _BakedArtState extends ConsumerState<BakedArt> {
  late final _art = _Loaded(_changed);
  late final _quick = _Loaded(_changed);
  var _told = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(BakedArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.quick != widget.quick) {
      _told = false;
      _load();
    }
  }

  void _load() {
    final image = ref.read(artImageProvider);
    final config = createLocalImageConfiguration(context);
    _art.load(image(widget.url), config);
    final quick = widget.quick;
    _quick.load(quick == null || quick == widget.url ? null : image(quick), config);
    // Nothing to wait for (tests, a game without pictures): said now.
    if (!_art.waiting && !_quick.waiting) _tell();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_art.info != null || _quick.info != null || (!_art.waiting && !_quick.waiting)) _tell();
  }

  void _tell() {
    if (_told) return;
    _told = true;
    final onShown = widget.onShown;
    if (onShown != null) WidgetsBinding.instance.addPostFrameCallback((_) => onShown());
  }

  @override
  void dispose() {
    _art.stop();
    _quick.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (url, info) = _art.info != null ? (widget.url, _art.info) : (widget.quick, _quick.info);
    return AnimatedSwitcher(
      duration: GMotion.slow,
      child: info == null || url == null
          ? const SizedBox.expand()
          : CustomPaint(
              key: ValueKey(url),
              size: Size.infinite,
              painter: _BakedArtPainter(
                key: (url, widget.blur, widget.shade),
                art: info.image,
                blur: widget.blur,
                shade: widget.shade,
              ),
            ),
    );
  }
}

/// One picture being loaded for [BakedArt].
class _Loaded {
  _Loaded(this.onChange);

  final VoidCallback onChange;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? info;

  /// Asked for and neither come nor failed.
  bool get waiting => _stream != null && info == null;

  void load(ImageProvider? provider, ImageConfiguration config) {
    final stream = provider?.resolve(config);
    if (stream != null && stream.key == _stream?.key) return;
    stop();
    if (stream == null) return;
    _listener = ImageStreamListener(
      (image, _) {
        _set(image);
        onChange();
      },
      onError: (_, _) {
        stop();
        onChange();
      },
    );
    _stream = stream..addListener(_listener!);
  }

  void _set(ImageInfo? image) {
    info?.dispose();
    info = image;
  }

  void stop() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
    _set(null);
  }
}

class _BakedArtPainter extends CustomPainter {
  _BakedArtPainter({required this.key, required this.art, required this.blur, required this.shade});

  final Object key;
  final ui.Image art;
  final double blur;
  final bool shade;

  static const _scale = 8;

  // A few pictures kept: the game page and the play screen share one, Home
  // has another.
  static const _kept = 4;
  static final _baked = <(Object, Size), ui.Image>{};

  ui.Image _bake(Size small) {
    final id = (key, small);
    final kept = _baked.remove(id);
    if (kept != null) return _baked[id] = kept;
    final recorder = ui.PictureRecorder();
    final rect = Offset.zero & small;
    final canvas = Canvas(recorder)..drawRect(rect, Paint()..color = GColors.bg);
    final sigma = blur / _scale;
    canvas.saveLayer(rect, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
    paintImage(canvas: canvas, rect: rect, image: art, fit: BoxFit.cover, opacity: 0.35);
    canvas.restore();
    if (shade) canvas.drawRect(rect, Paint()..shader = BakedArt.shadeGradient.createShader(rect));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(small.width.toInt(), small.height.toInt());
    picture.dispose();
    if (_baked.length >= _kept) {
      // A frame already drawn keeps its own reference to the picture.
      _baked.remove(_baked.keys.first)?.dispose();
    }
    return _baked[id] = image;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final small = Size(
      (size.width / _scale).ceilToDouble().clamp(1, 4096),
      (size.height / _scale).ceilToDouble().clamp(1, 4096),
    );
    canvas.drawImageRect(
      _bake(small),
      Offset.zero & small,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_BakedArtPainter old) => old.key != key || old.art != art;
}
