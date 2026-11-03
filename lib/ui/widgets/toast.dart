import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/ui_sound_service.dart';
import '../../providers/sound_providers.dart';
import '../theme/text_size.dart';
import '../theme/tokens.dart';

/// A short message at the lower right of the screen (a failed favourite, a
/// note that wasn't saved, a notification), raised above the page with a
/// lit edge and an icon. [error]: something failed or was refused: red, and
/// the error sound plays (#237). [queued]: after the one showing, not
/// instead of it (#241's notices). The snack bar spans the window (its look
/// is the theme's, see `gargosy_theme.dart`); the toast sits at its right,
/// worked out as it's drawn, so a resize while it shows keeps it there.
void showToast(BuildContext context, String message, {bool error = false, bool queued = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (error) _errorSound(context);
  final edge = error ? GColors.danger : GColors.primary;
  if (!queued) messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      key: const ValueKey('toast'),
      // Floating and clear here too: a frame without Gargosy's theme still shows it right.
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Above the hint bar, which grows with the text size (#240).
      margin: EdgeInsets.only(bottom: GSpace.s4 + scaledText(context, GToast.hintBarText)),
      padding: EdgeInsets.zero,
      content: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GToast.edgeGap),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: GToast.width),
            child: Material(
              key: const ValueKey('toast-box'),
              color: GColors.panel,
              elevation: GToast.elevation,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GRadius.card),
                side: BorderSide(
                  color: edge.withValues(alpha: GToast.edgeAlpha),
                  width: GToast.edgeWidth,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
                child: Row(
                  children: [
                    Icon(
                      error ? Icons.error_outline : Icons.notifications_none,
                      key: ValueKey(error ? 'toast-error' : 'toast-info'),
                      color: edge,
                      size: GToast.iconSize,
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
          ),
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
