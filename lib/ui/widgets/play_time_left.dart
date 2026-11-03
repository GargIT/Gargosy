import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/tr.dart';
import '../../play/play_limits.dart';
import '../../play/play_time_left.dart';
import '../../profiles/play_limit.dart';
import '../theme/tokens.dart';
import 'format.dart';

/// What [allowance] says at [now]: `42 min left`, `Back at 15:00`; null
/// when there's nothing to say (no limit today).
String? playTimeLeftLabel(PlayAllowance? allowance, DateTime now) => switch (allowance) {
  null || PlayAllowed(until: null) => null,
  PlayAllowed(:final until?) => tr('{0} left', [formatPlayTime(until.difference(now))]),
  PlayRefused(:final backAt) when backAt.isAfter(now) => tr('Back at {0}', [playClockLabel(backAt, now)]),
  PlayRefused() => tr('Play time not counted'),
};

/// The open profile's play time left under its limit (#235), counting down
/// (the top bar, the play screen); nothing without a limit. Amber in the
/// last minutes, red once it's used up or outside the hours. Not focusable:
/// it only tells.
class PlayTimeLeftChip extends ConsumerWidget {
  const PlayTimeLeftChip({super.key, this.gap = 0, this.top = 0, this.maxWidth = 260});

  /// Space after it (the top bar) and above it (the play screen), only when shown.
  final double gap;
  final double top;

  /// At most this wide: a long translation is cut, not pushed out of the bar.
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowance = ref.watch(playTimeLeftProvider);
    final now = ref.read(playClockProvider)();
    final label = playTimeLeftLabel(allowance, now);
    if (label == null) return const SizedBox.shrink();
    final color = switch (allowance) {
      PlayAllowed(:final until?) when until.difference(now) <= PlayLimit.warnBefore => GColors.warning,
      PlayRefused() => GColors.danger,
      _ => GColors.fgSecondary,
    };
    return Padding(
      padding: EdgeInsets.only(right: gap, top: top),
      child: Container(
        key: const ValueKey('play-time-left'),
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s1),
        decoration: BoxDecoration(
          color: GColors.surface,
          borderRadius: BorderRadius.circular(GRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_bottom, size: 16, color: color),
            const SizedBox(width: GSpace.s1),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
