import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One of the top bar's pages. Milestone A has only titles; B fills them.
class DestinationPage extends StatelessWidget {
  const DestinationPage({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: Key('page-$title'),
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GLayout.navHeight + GSpace.s8, GSpace.rowPad, GSpace.s14),
      children: [
        Text(message, style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800)),
        const SizedBox(height: GSpace.s2),
        Text('Your library arrives in the next milestone.', style: const TextStyle(fontSize: GFont.lg, color: GColors.fgMuted)),
        const SizedBox(height: 1600), // room to scroll; the bar's glass state needs it
      ],
    );
  }
}
