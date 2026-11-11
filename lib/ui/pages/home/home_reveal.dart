import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/tokens.dart';

/// How long Home waits before its first row, and between rows, the first
/// time it shows (#310); tests give zero, every row at once.
final homeRevealStepProvider = Provider<Duration>((ref) => const Duration(milliseconds: 120));

/// How many of Home's rows show. On the first start Home draws its header
/// and art first and then the rows one after another, so they don't all ask
/// RomM and decode covers in the same frames; a row not shown yet isn't
/// asked for. Kept for the run: going back to Home shows them all at once.
final homeRowsShownProvider = NotifierProvider<HomeRowsShown, int>(HomeRowsShown.new);

class HomeRowsShown extends Notifier<int> {
  /// More than Home has rows and widgets.
  static const all = 32;

  /// How many steps the rows wait for the header's art at most.
  static const waitSteps = 12;

  Timer? _wait;
  Timer? _steps;

  @override
  int build() {
    final step = ref.watch(homeRevealStepProvider);
    if (step == Duration.zero) return all;
    _wait = Timer(step * waitSteps, artShown);
    ref.onDispose(() {
      _wait?.cancel();
      _steps?.cancel();
    });
    return 0;
  }

  /// The header's art is drawn (or there's none): the rows may come, one a
  /// step.
  void artShown() {
    if (_steps != null || state >= all) return;
    _wait?.cancel();
    state = 1;
    _steps = Timer.periodic(ref.read(homeRevealStepProvider), (t) {
      if (state >= all) return t.cancel();
      state = state + 1;
    });
  }
}

/// [child] faded in the first time it's built.
class FadeInOnce extends StatelessWidget {
  const FadeInOnce({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: GMotion.med,
    curve: GMotion.easeOut,
    builder: (context, t, child) => Opacity(opacity: t, child: child),
    child: child,
  );
}
