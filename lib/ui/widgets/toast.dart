import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/ui_sound_service.dart';
import '../../providers/sound_providers.dart';
import '../theme/tokens.dart';

/// A toast's width at most, and its gap from the window's right and bottom
/// edges (above the hint bar).
const toastWidth = 440.0;
const toastRight = GSpace.s6;
const toastBottom = GSpace.s14;

/// A short message at the lower right of the screen (a failed favourite, a
/// note that wasn't saved, a notification), raised above the page with a
/// lit edge and an icon. [error]: something failed or was refused: red, and
/// the error sound plays (#237). [queued]: after the one showing, not
/// instead of it (#241's notices).
void showToast(BuildContext context, String message, {bool error = false, bool queued = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (error) _errorSound(context);
  final screen = MediaQuery.sizeOf(context).width;
  final width = min(toastWidth, screen - 2 * toastRight);
  final edge = error ? GColors.danger : GColors.primary;
  if (!queued) messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      key: const ValueKey('toast'),
      behavior: SnackBarBehavior.floating,
      // Its left gap puts it at the right; a narrow window gives it the width.
      margin: EdgeInsets.fromLTRB(max(toastRight, screen - width - toastRight), 0, toastRight, toastBottom),
      padding: EdgeInsets.zero,
      elevation: 12,
      backgroundColor: GColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GRadius.card),
        side: BorderSide(color: edge.withValues(alpha: 0.7), width: 1.5),
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
        child: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.notifications_none,
              key: ValueKey(error ? 'toast-error' : 'toast-info'),
              color: edge,
              size: 22,
            ),
            const SizedBox(width: GSpace.s3),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: GColors.fg, fontSize: GFont.lg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _errorSound(BuildContext context) {
  try {
    ProviderScope.containerOf(context, listen: false).read(uiSoundsProvider).play(UiSound.error);
  } on StateError {
    // No ProviderScope above (a test framing the toast alone): no sound.
  }
}
