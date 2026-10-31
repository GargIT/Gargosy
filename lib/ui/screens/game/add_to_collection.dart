import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/romm/romm_library_api.dart';
import '../../../core/romm/romm_models.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/hint_bar.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// The game page's ⋯ → Add to collection… (#144): the user's own
/// collections, Favourites first, ✓ on those [game] is in; A puts it in or
/// takes it out. New collection… makes one with the game in it.
Future<void> showAddToCollection(BuildContext context, Game game) => showDialog<void>(
  context: context,
  builder: (_) => _AddToCollection(game: game),
);

/// Asks a name and who sees it, then makes the collection (with [gameId]
/// when given). Returns it, or null when the player backed out or RomM
/// refused (said in a toast).
Future<RommCollection?> createCollection(BuildContext context, WidgetRef ref, {String? gameId}) async {
  final edits = ref.read(collectionEditsProvider);
  if (edits == null) return null;
  final name = (await showOnScreenKeyboard(context, title: tr('New collection')))?.trim();
  if (name == null || name.isEmpty || !context.mounted) return null;
  final who = await showChoice(
    context,
    title: tr('Who sees {0}?', [name]),
    labels: [tr('Only you'), tr('Every player on RomM (shared)')],
    current: 0,
  );
  if (who == null) return null;
  try {
    final made = await edits.create(name, shared: who == 1, gameId: gameId);
    ref.invalidate(collectionsProvider);
    return made;
  } on Object catch (e) {
    if (context.mounted) showToast(context, tr('Couldn\'t make {0}: {1}', [name, e]));
    return null;
  }
}

class _AddToCollection extends ConsumerStatefulWidget {
  const _AddToCollection({required this.game});

  final Game game;

  @override
  ConsumerState<_AddToCollection> createState() => _AddToCollectionState();
}

class _AddToCollectionState extends ConsumerState<_AddToCollection> {
  final _busy = <int>{};

  int? get _gameId => int.tryParse(widget.game.id);

  Future<void> _toggle(RommCollection c, bool inIt) async {
    if (_busy.contains(c.id)) return;
    setState(() => _busy.add(c.id));
    try {
      if (c.isFavorite) {
        final failed = await toggleFavourite(ref, widget.game);
        if (failed != null) throw failed;
      } else {
        await ref.read(collectionEditsProvider)!.setIn(c.id, widget.game.id, !inIt);
        ref.invalidate(collectionsProvider);
      }
      await ref.read(collectionsProvider.future);
    } on Object catch (e) {
      if (mounted) showToast(context, tr('Couldn\'t change {0}: {1}', [c.isFavorite ? 'Favourites' : c.name, e]));
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(rommUserIdProvider);
    final all = ref.watch(collectionsProvider).value ?? const <RommCollection>[];
    final own = [
      for (final c in all)
        if (c.userId == userId && c.kind == CollectionKind.regular) c,
    ]..sort((a, b) => a.isFavorite != b.isFavorite ? (a.isFavorite ? -1 : 1) : a.name.compareTo(b.name));
    // Favourites before the user has one: made on the first ♥.
    if (!own.any((c) => c.isFavorite)) own.insert(0, const RommCollection(id: -1, name: 'Favorites', isFavorite: true));

    Widget row(
      String label,
      String line,
      IconData icon,
      Color color,
      VoidCallback onPress, {
      Key? key,
      bool busy = false,
    }) => GFocusable(
      key: key,
      autofocus: key == const ValueKey('collection-pick-0'),
      borderRadius: GRadius.md,
      onActivate: onPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s2),
        child: Row(
          children: [
            busy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, color: color),
            const SizedBox(width: GSpace.s3),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: GFont.lg),
              ),
            ),
            Text(
              line,
              style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
            ),
          ],
        ),
      ),
    );

    return Center(
      child: Material(
        color: GColors.panel,
        borderRadius: BorderRadius.circular(GRadius.lg),
        child: SizedBox(
          width: 480,
          child: Padding(
            padding: const EdgeInsets.all(GSpace.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Add {0} to', [widget.game.displayName]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: GSpace.s3),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < own.length; i++)
                          () {
                            final c = own[i];
                            final inIt = c.romIds.contains(_gameId);
                            return row(
                              c.isFavorite ? tr('Favourites') : c.name,
                              '${c.romCount} ${c.romCount == 1 ? 'game' : 'games'}${c.isPublic ? ' · shared' : ''}',
                              inIt ? Icons.check_box : Icons.check_box_outline_blank,
                              inIt ? GColors.primary : GColors.fgMuted,
                              () => _toggle(c, inIt),
                              key: ValueKey('collection-pick-$i'),
                              busy: _busy.contains(c.id),
                            );
                          }(),
                        row(tr('New collection…'), '', Icons.add, GColors.fgSecondary, () async {
                          final made = await createCollection(context, ref, gameId: widget.game.id);
                          if (made != null && context.mounted) showToast(context, tr('Added to {0}.', [made.name]));
                        }, key: const ValueKey('collection-new')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: GSpace.s3),
                HintBar(hints: [Hint(GameAction.confirm, tr('In / out')), Hint(GameAction.back, tr('Done'))]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
