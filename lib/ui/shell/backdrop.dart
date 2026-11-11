import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const _glow = RadialGradient(
  center: Alignment(-0.6, -0.9),
  radius: 1.4,
  colors: [Color(0x55553E98), Color(0x22371F69), Color(0x0007070F)],
  stops: [0, 0.45, 1],
);

/// v2's dark page behind everything; milestone B puts the focused game's
/// art here. For now a soft glow in v2's cover-art colours.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: const _GlowPainter(), child: child);
}

/// The glow, painted once into an image a quarter of the page's size and
/// stretched over it (#308). A gradient drawn at full size is worked out for
/// every pixel on every frame, which cost a third of each frame on an
/// integrated GPU; the stretched image costs as little as a plain colour and
/// looks the same, since the glow has no edges.
class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  static const _scale = 4;

  // Pages mostly have the window's size; a few sizes are kept so backdrops
  // of different sizes on screen together don't make theirs every frame.
  static const _kept = 4;
  static final _images = <Size, ui.Image>{};

  static ui.Image _imageFor(Size small) {
    final kept = _images.remove(small);
    if (kept != null) return _images[small] = kept;
    // Only the gradient, as `BoxDecoration` drew it (it ignores its colour
    // when it has a gradient): the edge stays clear over the page's colour.
    final recorder = ui.PictureRecorder();
    final rect = Offset.zero & small;
    Canvas(recorder).drawRect(rect, Paint()..shader = _glow.createShader(rect));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(small.width.toInt(), small.height.toInt());
    picture.dispose();
    if (_images.length >= _kept) {
      // A frame already drawn keeps its own reference to the image.
      _images.remove(_images.keys.first)?.dispose();
    }
    return _images[small] = image;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final small = Size(
      (size.width / _scale).ceilToDouble().clamp(1, 4096),
      (size.height / _scale).ceilToDouble().clamp(1, 4096),
    );
    canvas.drawImageRect(
      _imageFor(small),
      Offset.zero & small,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => false;
}
