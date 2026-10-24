import 'package:flutter/material.dart';

import '../../providers/library_providers.dart';
import '../theme/tokens.dart';
import '../widgets/header_stat.dart';

/// Search's header (#132): the heading, the search [box], and what the box
/// matches: GAMES, ON THIS PC and PLATFORMS ([scope] while it loads is null).
class SearchHeader extends StatelessWidget {
  const SearchHeader({super.key, required this.box, required this.scope, required this.onThisPc});

  final Widget box;
  final GalleryScope? scope;
  final int onThisPc;

  @override
  Widget build(BuildContext context) {
    final scope = this.scope;
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s5, GSpace.rowPad, GSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search',
            style: TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800, height: 1.1),
          ),
          const SizedBox(height: GSpace.s4),
          Wrap(
            spacing: GSpace.s8,
            runSpacing: GSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: 620, child: box),
              Wrap(
                spacing: GSpace.s10,
                runSpacing: GSpace.s3,
                children: [
                  HeaderStat(scope == null ? '–' : '${scope.total}', 'GAMES', key: const ValueKey('search-games')),
                  HeaderStat(
                    '$onThisPc',
                    'ON THIS PC',
                    color: GColors.gargosyTeal,
                    key: const ValueKey('search-on-pc'),
                  ),
                  if (scope != null && scope.platforms.isNotEmpty)
                    HeaderStat('${scope.platforms.length}', 'PLATFORMS', key: const ValueKey('search-platforms')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
