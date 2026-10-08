import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A short message at the bottom of the screen (a failed favourite, a note
/// that wasn't saved).
void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: GColors.fg)),
      backgroundColor: GColors.panel,
      behavior: SnackBarBehavior.floating,
    ));
}
