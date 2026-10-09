import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'g_focusable.dart';

/// The outlined Back at the bottom of the cover column, on the game page and
/// the play screen: what B / Esc does, for the mouse.
class OutlinedBackButton extends StatelessWidget {
  const OutlinedBackButton({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => GFocusable(
    borderRadius: GRadius.pill,
    onActivate: () => Navigator.of(context).maybePop(),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: GSpace.s3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GRadius.pill),
        border: Border.all(color: GColors.borderStrong, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.arrow_back, size: 20, color: GColors.fgSecondary),
          const SizedBox(width: GSpace.s2),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700, color: GColors.fgSecondary),
            ),
          ),
        ],
      ),
    ),
  );
}
