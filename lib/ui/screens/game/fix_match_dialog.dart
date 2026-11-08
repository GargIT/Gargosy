import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_admin.dart';
import '../../../core/romm/romm_models.dart';
import '../../../l10n/tr.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/toast.dart';

/// The game page's ⋯ → Fix match (#245, a RomM admin's): RomM searches its
/// metadata sources for the game (its file name first, then any name typed),
/// the player picks the right one, and RomM takes its name, cover and
/// details from there. The file isn't renamed.
Future<void> fixMatch(BuildContext context, WidgetRef ref, Game game) async {
  final romm = ref.read(rommServiceProvider);
  if (romm == null) return;
  String? term;
  while (true) {
    if (!context.mounted) return;
    final List<MatchCandidate> found;
    try {
      found = await _whileWaiting(context, tr('Searching…'), romm.searchMatches(game.id, term: term));
    } on Object catch (e) {
      if (context.mounted) showToast(context, '$e', error: true);
      return;
    }
    if (!context.mounted) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => _MatchList(game: game, term: term, found: found),
    );
    if (picked == null || !context.mounted) return;
    if (picked < 0) {
      final typed = (await showOnScreenKeyboard(
        context,
        title: tr('Search for'),
        initial: term ?? game.displayName,
      ))?.trim();
      if (typed == null || typed.isEmpty) return;
      term = typed;
      continue;
    }
    final match = found[picked];
    final ok = await showConfirm(
      context,
      title: tr('Match {0} with {1}?', [game.displayName, match.name]),
      body: tr(
        'RomM takes the name, cover and details from {0}. The file on RomM keeps its name; your saves aren\'t touched.',
        [match.sources.join(', ')],
      ),
      yes: tr('Match'),
      no: tr('Cancel'),
    );
    if (!ok || !context.mounted) return;
    try {
      await _whileWaiting(context, tr('Matching…'), romm.applyMatch(game.id, match));
    } on Object catch (e) {
      if (context.mounted) showToast(context, '$e', error: true);
      return;
    }
    ref.invalidate(gameProvider(game.id));
    if (context.mounted) showToast(context, tr('Matched with {0}.', [match.name]));
    return;
  }
}

/// [work] with a small dialog saying [label] until it ends.
Future<T> _whileWaiting<T>(BuildContext context, String label, Future<T> work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final shown = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: GColors.panel,
          borderRadius: BorderRadius.circular(GRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(GSpace.s6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(width: GSpace.s4),
                Text(label, style: const TextStyle(fontSize: GFont.lg)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  try {
    return await work;
  } finally {
    navigator.pop();
    await shown;
  }
}

/// The games found, the first focused; "Search for another name" first.
/// Pops the picked index, or -1 to search again.
class _MatchList extends StatelessWidget {
  const _MatchList({required this.game, required this.term, required this.found});

  final Game game;
  final String? term;
  final List<MatchCandidate> found;

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: GColors.panel,
      borderRadius: BorderRadius.circular(GRadius.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.all(GSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Fix match: {0}', [game.displayName]),
                style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: GSpace.s1),
              Text(
                term == null ? tr('Found by its file name.') : tr('Found for "{0}".', [term]),
                style: const TextStyle(color: GColors.fgSecondary),
              ),
              const SizedBox(height: GSpace.s4),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _Row(
                      key: const ValueKey('match-search'),
                      autofocus: found.isEmpty,
                      onActivate: () => Navigator.of(context).pop(-1),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 20),
                          const SizedBox(width: GSpace.s3),
                          Text(tr('Search for another name…'), style: const TextStyle(fontSize: GFont.lg)),
                        ],
                      ),
                    ),
                    if (found.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(GSpace.s4),
                        child: Text(
                          tr('Nothing found. Try another name.'),
                          style: const TextStyle(color: GColors.fgSecondary),
                        ),
                      ),
                    for (var i = 0; i < found.length; i++)
                      _Row(
                        key: ValueKey('match-$i'),
                        autofocus: i == 0,
                        onActivate: () => Navigator.of(context).pop(i),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              found[i].name,
                              style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              found[i].sources.join(' · '),
                              style: const TextStyle(fontSize: GFont.sm, color: GColors.primaryHover),
                            ),
                            if (found[i].summary.isNotEmpty)
                              Text(
                                found[i].summary,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.autofocus, required this.onActivate, required this.child});

  final bool autofocus;
  final VoidCallback onActivate;
  final Widget child;

  @override
  Widget build(BuildContext context) => GFocusable(
    autofocus: autofocus,
    borderRadius: GRadius.md,
    onActivate: onActivate,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
      child: child,
    ),
  );
}
