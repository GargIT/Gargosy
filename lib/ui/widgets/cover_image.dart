import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'romm_images.dart';

/// How a cover URL becomes a picture: through the RomM image cache (the
/// server's certificate setting, kept on disk); tests swap in a plain box.
final coverImageBuilderProvider = Provider<Widget Function(String url)>((ref) {
  final cache = ref.watch(rommImageCacheProvider);
  return (url) => CachedNetworkImage(
    imageUrl: url,
    cacheManager: cache,
    fit: BoxFit.cover,
    fadeInDuration: GMotion.fast,
    errorWidget: (context, url, error) => const SizedBox.shrink(),
  );
});

/// A cover, or v2's placeholder art with the title when there is none.
class CoverImage extends ConsumerWidget {
  const CoverImage({super.key, this.url, this.title, this.width, this.height, this.radius = GRadius.card});

  final String? url;
  final String? title;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CoverArt(),
            if (url == null && title != null)
              Padding(
                padding: const EdgeInsets.all(GSpace.s3),
                child: Center(
                  child: Text(
                    title!,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            if (url != null) ref.watch(coverImageBuilderProvider)(url!),
          ],
        ),
      ),
    );
  }
}

/// v2's placeholder art, under every cover: what shows while it loads, when it
/// doesn't, and through a transparent one. The gradient is painted once into a
/// small 3:4 picture and stretched (exact for a cover's shape, close for
/// others): drawn as a gradient behind every cover it cost a Collections frame
/// about 25 ms (#315).
class CoverArt extends StatelessWidget {
  const CoverArt({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _CoverArtPainter(), child: SizedBox.expand());
}

class _CoverArtPainter extends CustomPainter {
  const _CoverArtPainter();

  static const _w = 48, _h = 64;
  static ui.Image? _image;

  static ui.Image get image => _image ??= () {
    final recorder = ui.PictureRecorder();
    final rect = Rect.fromLTWH(0, 0, _w.toDouble(), _h.toDouble());
    Canvas(recorder).drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GColors.coverArtBase, GColors.coverArtShade],
        ).createShader(rect),
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(_w, _h);
    } finally {
      picture.dispose();
    }
  }();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final src = Rect.fromLTWH(0, 0, _w.toDouble(), _h.toDouble());
    canvas.drawImageRect(image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.low);
  }

  @override
  bool shouldRepaint(_CoverArtPainter oldDelegate) => false;
}
