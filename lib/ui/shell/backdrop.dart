import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// v2's dark page behind everything; milestone B puts the focused game's
/// art here. For now a soft glow in v2's cover-art colours.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: GColors.bg,
        gradient: RadialGradient(
          center: Alignment(-0.6, -0.9),
          radius: 1.4,
          colors: [Color(0x55553E98), Color(0x22371F69), Color(0x0007070F)],
          stops: [0, 0.45, 1],
        ),
      ),
      child: child,
    );
  }
}
