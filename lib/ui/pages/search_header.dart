import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_providers.dart';
import '../../providers/ui_provider.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/header_stat.dart';
import '../../l10n/tr.dart';

/// Search's header (#132): the heading, the search [box], what the box
/// matches: GAMES, ON THIS PC and PLATFORMS ([scope] while it loads is null),
/// and the profile's [recent] searches under it.
class SearchHeader extends StatelessWidget {
  const SearchHeader({
    super.key,
    required this.box,
    required this.scope,
    required this.onThisPc,
    this.recent = const [],
    this.onRecent,
    this.onForget,
  });

  final Widget box;
  final GalleryScope? scope;
  final int onThisPc;
  final List<String> recent;

  /// A runs a recent search; hold A (or its ×) forgets it.
  final ValueChanged<String>? onRecent;
  final ValueChanged<String>? onForget;

  @override
  Widget build(BuildContext context) {
    final scope = this.scope;
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s5, GSpace.rowPad, GSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Search'),
            style: const TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800, height: 1.1),
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
                    tr('ON THIS PC'),
                    color: GColors.gargosyTeal,
                    key: const ValueKey('search-on-pc'),
                  ),
                  if (scope != null && scope.platforms.isNotEmpty)
                    HeaderStat('${scope.platforms.length}', 'PLATFORMS', key: const ValueKey('search-platforms')),
                ],
              ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: GSpace.s4),
            Wrap(
              key: const ValueKey('search-recent'),
              spacing: GSpace.s2,
              runSpacing: GSpace.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: GSpace.s1),
                  child: Text(
                    tr('RECENT'),
                    style: const TextStyle(
                      fontSize: GFont.sm,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                      color: GColors.fgSecondary,
                    ),
                  ),
                ),
                for (final r in recent)
                  _RecentChip(r, onRun: () => onRecent?.call(r), onForget: () => onForget?.call(r)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentChip extends ConsumerWidget {
  const _RecentChip(this.term, {required this.onRun, required this.onForget});

  final String term;
  final VoidCallback onRun;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mouse = ref.watch(inputModeProvider) == InputMode.mouse;
    return GFocusable(
      key: ValueKey('recent-$term'),
      borderRadius: GRadius.pill,
      onActivate: onRun,
      onLongActivate: onForget,
      child: Container(
        padding: EdgeInsets.fromLTRB(GSpace.s3, 5, mouse ? GSpace.s2 : GSpace.s3, 5),
        decoration: BoxDecoration(
          color: GColors.bgElevated,
          border: Border.all(color: GColors.borderStrong),
          borderRadius: BorderRadius.circular(GRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              term,
              style: const TextStyle(fontSize: GFont.md, color: GColors.fgSecondary),
            ),
            if (mouse) ...[
              const SizedBox(width: GSpace.s1),
              GestureDetector(
                key: ValueKey('recent-forget-$term'),
                onTap: onForget,
                child: const Icon(Icons.close, size: 14, color: GColors.fgMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
