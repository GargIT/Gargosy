import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';

/// The game page's tabs, each with a count badge when there is one (the
/// number of saves, achievements earned/total, notes).
class GameTabs extends StatelessWidget {
  const GameTabs({super.key, required this.tabs, required this.index, required this.onTab, this.badges = const {}});

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onTab;

  /// Tab index → badge text.
  final Map<int, String> badges;

  @override
  Widget build(BuildContext context) => Wrap(runSpacing: GSpace.s2, children: [
        for (var i = 0; i < tabs.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: GSpace.s2),
            child: GFocusable(
              borderRadius: GRadius.pill,
              onActivate: () => onTab(i),
              child: AnimatedContainer(
                duration: GMotion.fast,
                padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
                decoration: BoxDecoration(
                  color: i == index ? GColors.fg : GColors.surface,
                  borderRadius: BorderRadius.circular(GRadius.pill),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tabs[i],
                      style: TextStyle(fontWeight: FontWeight.w600, color: i == index ? GColors.bg : GColors.fgSecondary)),
                  if (badges[i] case final b?)
                    Container(
                      key: ValueKey('tab-badge-$i'),
                      margin: const EdgeInsets.only(left: GSpace.s2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: GColors.primary, borderRadius: BorderRadius.circular(GRadius.pill)),
                      child: Text(b, style: const TextStyle(fontSize: GFont.xs, fontWeight: FontWeight.w700, color: GColors.fg)),
                    ),
                ]),
              ),
            ),
          ),
      ]);
}
