import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/ui_sound_service.dart';
import '../../providers/sound_providers.dart';
import '../theme/tokens.dart';

/// A short message at the bottom of the screen (a failed favourite, a note
/// that wasn't saved). [error]: something failed or was refused, and the
/// error sound plays (#237). [queued]: after the one showing, not instead
/// of it (#241's notices).
void showToast(BuildContext context, String message, {bool error = false, bool queued = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (error) _errorSound(context);
  if (!queued) messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: GColors.fg)),
      backgroundColor: GColors.panel,
      behavior: SnackBarBehavior.floating,
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
