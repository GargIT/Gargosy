import 'package:flutter/material.dart';

import '../../core/input/gamepad_service.dart';
import '../shell/backdrop.dart';
import '../theme/tokens.dart';
import '../widgets/hint_bar.dart';
import 'settings/about_section.dart';

/// About, opened from the user menu: B goes back (the router pops the route).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Backdrop(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s10, GSpace.rowPad, GSpace.s4),
              child: Text('About', style: TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800)),
            ),
            const Expanded(
              child: Padding(padding: EdgeInsets.symmetric(horizontal: GSpace.rowPad), child: AboutSection(autofocus: true)),
            ),
            const HintBar(hints: [Hint(GameAction.confirm, 'Open'), Hint(GameAction.back, 'Back')]),
          ]),
        ),
      );
}
