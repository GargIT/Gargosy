import 'package:flutter/material.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/romm/romm_models.dart';
import '../theme/tokens.dart';
import 'g_focusable.dart';

/// What hides a gallery's games (#132): On this PC, a platform picked on the
/// bar (not [base]'s own, a platform's page), genres and regions.
List<String> hiddenBy(GalleryQuery query, GalleryQuery base, {required bool thisPc, List<Platform>? platforms}) {
  String some(String one, Set<String> values) =>
      '${values.length == 1 ? 'the $one' : 'the ${one}s'} ${joinAnd(values.toList())}';
  final platformId = query.platformId;
  return [
    if (thisPc) 'On this PC',
    if (platformId != null && platformId != base.platformId)
      'the platform ${platforms?.where((p) => p.id == platformId).firstOrNull?.nameForDisplay ?? ''}'.trim(),
    if (query.genres.isNotEmpty) some('genre', query.genres),
    if (query.regions.isNotEmpty) some('region', query.regions),
  ];
}

/// `a`, `a and b`, `a, b and c`.
String joinAnd(List<String> parts) =>
    parts.length < 2 ? parts.join() : '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';

/// An empty gallery whose games the bar's filters hide: what hides them, how
/// many RomM has ([count], null while unknown), and a button that clears them.
class NothingMatches extends StatelessWidget {
  const NothingMatches({super.key, this.term, required this.hidden, this.count, required this.onShowAll});

  final String? term;
  final List<String> hidden;
  final int? count;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final n = count;
    final by = joinAnd(hidden);
    final games = n == 1 ? '1 game' : '$n games';
    return Center(
      key: const ValueKey('nothing-matches'),
      child: Padding(
        padding: const EdgeInsets.all(GSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 56, color: GColors.fgFaint),
            const SizedBox(height: GSpace.s4),
            Text(
              term == null ? 'Nothing here with these filters.' : 'Nothing matches “$term” here.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: GSpace.s3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                n == null
                    ? 'Hidden by $by.'
                    : term == null
                    ? 'RomM has $games here, hidden by $by.'
                    : 'RomM has $games that ${n == 1 ? 'matches' : 'match'}, hidden by $by.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: GFont.md, color: GColors.fgSecondary),
              ),
            ),
            const SizedBox(height: GSpace.s5),
            GFocusable(
              key: const ValueKey('show-all'),
              borderRadius: GRadius.pill,
              onActivate: onShowAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
                decoration: BoxDecoration(color: GColors.fg, borderRadius: BorderRadius.circular(GRadius.pill)),
                child: Text(
                  n == null ? 'Clear filters' : 'Show all $n',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: GColors.bg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
