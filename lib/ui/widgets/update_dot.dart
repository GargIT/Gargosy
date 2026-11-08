import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulators/emulator_updates.dart';
import '../../providers/update_providers.dart';
import '../theme/tokens.dart';

/// A dot on [child] (the avatar) while an update of Gargosy (issue #16) or
/// of an installed emulator (#243) is available: the quiet sign of the
/// checks at start, never a popup.
class UpdateDot extends ConsumerWidget {
  const UpdateDot({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available =
        ref.watch(updateStateProvider.select((s) => s.available != null)) ||
        ref.watch(emulatorUpdatesProvider.select((s) => s.available.isNotEmpty));
    if (!available) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          top: -2,
          child: IgnorePointer(
            child: Container(
              key: const Key('update-dot'),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: GColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: GColors.bg, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
