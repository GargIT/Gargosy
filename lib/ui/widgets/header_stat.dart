import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A number over its label in a page's header (GAMES, ON THIS PC, PLATFORMS):
/// a collection's page and Search.
class HeaderStat extends StatelessWidget {
  const HeaderStat(this.value, this.label, {super.key, this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700, color: color),
      ),
      Text(
        label,
        style: const TextStyle(
          fontSize: GFont.sm,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: GColors.fgMuted,
        ),
      ),
    ],
  );
}
