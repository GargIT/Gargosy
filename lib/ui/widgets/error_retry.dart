import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'g_focusable.dart';

/// A page that couldn't load: what went wrong, and Retry (spec §8).
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Scrolls when the box is small; a long server error is cut to three lines.
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: GColors.fgMuted),
            const SizedBox(height: GSpace.s3),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: GFont.lg,
                color: GColors.fgSecondary,
              ),
            ),
            const SizedBox(height: GSpace.s4),
            GFocusable(
              autofocus: true,
              borderRadius: GRadius.pill,
              onActivate: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: GSpace.s6,
                  vertical: GSpace.s3,
                ),
                decoration: BoxDecoration(
                  color: GColors.surface,
                  borderRadius: BorderRadius.circular(GRadius.pill),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: GFont.lg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short reason for [error], for [ErrorRetry].
String describeLoadError(Object error) {
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('connection')) {
    return "Can't reach RomM. Check your network.";
  }
  return 'RomM could not be read ($text).';
}
