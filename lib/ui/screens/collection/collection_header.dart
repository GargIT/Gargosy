import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_library_api.dart';
import '../../../core/romm/romm_models.dart';
import '../../../library/collection_list.dart';
import '../../../library/library_snapshot.dart';
import '../../../library/smart_criteria.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/collection_tile.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/header_stat.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/toast.dart';
import '../game/open_game.dart';
import '../../../l10n/tr.dart';

/// A collection's page header (#121): its mosaic, the name with its kind,
/// whether it's shared and whose it is, its description (a smart one's
/// filters), how many games it has and how many are on this PC, and Random.
class CollectionHeader extends ConsumerStatefulWidget {
  const CollectionHeader({super.key, required this.collection, this.onChanged});

  final RommCollection collection;

  /// The collection after a rename or a share from ⋯ (#144).
  final ValueChanged<RommCollection>? onChanged;

  @override
  ConsumerState<CollectionHeader> createState() => _CollectionHeaderState();
}

class _CollectionHeaderState extends ConsumerState<CollectionHeader> {
  bool _picking = false;

  Future<void> _random() async {
    final api = ref.read(libraryApiProvider);
    if (api == null || _picking) return;
    setState(() => _picking = true);
    try {
      final game = await api.randomGame(within: widget.collection.query);
      if (!mounted) return;
      if (game == null) {
        showToast(context, tr('No games here yet.'));
      } else {
        openGame(context, game);
      }
    } on Object catch (e) {
      if (mounted) showToast(context, describeLoadError(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// ⋯ on the user's own collection (#144), regular or smart (#188): Rename,
  /// Share or Stop sharing, Delete (its games stay in RomM).
  Future<void> _more() async {
    final c = widget.collection;
    final edits = ref.read(collectionEditsProvider);
    if (edits == null) return;
    final pick = await showChoice(
      context,
      title: c.name,
      labels: [
        tr('Rename…'),
        c.isPublic ? tr('Stop sharing') : tr('Share with every player'),
        tr('Delete collection…'),
      ],
    );
    if (pick == null || !mounted) return;
    try {
      switch (pick) {
        case 0:
          final name = (await showOnScreenKeyboard(
            context,
            title: tr('Rename {0}', [c.name]),
            initial: c.name,
          ))?.trim();
          if (name == null || name.isEmpty || name == c.name) return;
          widget.onChanged?.call(await edits.rename(c, name));
        case 1:
          widget.onChanged?.call(await edits.setShared(c, !c.isPublic));
        case 2:
          final ok = await showConfirm(
            context,
            title: tr('Delete {0}?', [c.name]),
            body: tr('The collection goes from RomM for every player. Its games stay in the library.'),
            yes: tr('Delete'),
            no: tr('Keep'),
            focusYes: false,
            danger: true,
          );
          if (!ok) return;
          await edits.delete(c);
          ref.invalidate(collectionsProvider);
          ref.invalidate(smartCollectionsProvider);
          if (mounted) Navigator.of(context).pop();
          return;
      }
      ref.invalidate(collectionsProvider);
      ref.invalidate(smartCollectionsProvider);
    } on Object catch (e) {
      if (mounted) showToast(context, tr('Couldn\'t change {0}: {1}', [c.name, e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.collection;
    final userId = ref.watch(rommUserIdProvider);
    final downloaded = {for (final g in ref.watch(gamesOnThisPcProvider)) ?int.tryParse(g.id)};
    final platforms = ref.watch(galleryScopeProvider(c.query)).valueOrNull?.platforms;
    final virtual = c.kind == CollectionKind.virtual;
    final whose = virtual || c.userId == null
        ? null
        : c.userId == userId
        ? tr('By you')
        : tr('By {0}', [c.ownerUsername ?? 'another player']);
    final names = {for (final p in ref.watch(platformsProvider).valueOrNull ?? const <Platform>[]) p.id: p.name};
    final filters = c.kind == CollectionKind.smart ? describeCriteria(c.filterCriteria, platformNames: names) : '';
    // RomM's filter_summary is its criteria as JSON; said in words when they read back.
    final summary = c.filterSummary ?? '';
    final about = filters.isNotEmpty
        ? filters
        : c.kind == CollectionKind.smart && summary.isNotEmpty && !summary.startsWith('{')
        ? summary
        : c.description;
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s5, GSpace.rowPad, GSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: AspectRatio(
              aspectRatio: CollectionTile.coverAspect,
              child: CollectionMosaic(
                urls: [for (final path in c.coverPaths.take(4)) assetUrl(ref, path)],
                favourite: c.isFavorite,
                radius: GRadius.card,
              ),
            ),
          ),
          const SizedBox(width: GSpace.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.isFavorite ? tr('Favourites') : c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800, height: 1.1),
                ),
                const SizedBox(height: GSpace.s3),
                Wrap(
                  spacing: GSpace.s2,
                  runSpacing: GSpace.s2,
                  children: [
                    _Chip(
                      key: const ValueKey('collection-kind'),
                      icon: switch (c.kind) {
                        CollectionKind.regular => Icons.bookmark_border,
                        CollectionKind.smart => Icons.bolt,
                        CollectionKind.virtual => Icons.collections_bookmark_outlined,
                      },
                      text: switch (c.kind) {
                        CollectionKind.regular => c.isFavorite ? tr('Favourites') : tr('Collection'),
                        CollectionKind.smart => tr('Smart collection'),
                        CollectionKind.virtual => tr('Virtual · {0}', [
                          switch (virtualCollectionTypes[c.virtualType]) {
                            final t? => tr(t),
                            null => c.virtualType ?? 'RomM',
                          },
                        ]),
                      },
                    ),
                    if (c.isPublic && !virtual)
                      _Chip(
                        key: const ValueKey('collection-shared'),
                        icon: Icons.public,
                        text: tr('Shared on RomM'),
                        color: GColors.gargosyTeal,
                      ),
                    if (whose != null) _Chip(text: whose),
                  ],
                ),
                if (about.trim().isNotEmpty) ...[
                  const SizedBox(height: GSpace.s3),
                  Text(
                    about.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary),
                  ),
                ],
                const SizedBox(height: GSpace.s4),
                Wrap(
                  spacing: GSpace.s10,
                  runSpacing: GSpace.s3,
                  children: [
                    HeaderStat('${c.romCount}', tr('GAMES')),
                    HeaderStat('${onThisPc(c, downloaded)}', tr('ON THIS PC'), color: GColors.gargosyTeal),
                    if (platforms != null && platforms.isNotEmpty)
                      HeaderStat('${platforms.length}', tr('PLATFORMS'), key: const ValueKey('collection-platforms')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: GSpace.s4),
          if (c.kind != CollectionKind.virtual && !c.isFavorite && c.userId != null && c.userId == userId) ...[
            GFocusable(
              key: const ValueKey('collection-more'),
              borderRadius: GRadius.pill,
              onActivate: _more,
              semanticLabel: 'More',
              child: Container(
                padding: const EdgeInsets.all(GSpace.s3),
                decoration: BoxDecoration(
                  color: GColors.surface,
                  borderRadius: BorderRadius.circular(GRadius.pill),
                  border: Border.all(color: GColors.borderStrong),
                ),
                child: const Icon(Icons.more_horiz, size: 18),
              ),
            ),
            const SizedBox(width: GSpace.s2),
          ],
          GFocusable(
            key: const ValueKey('collection-random'),
            borderRadius: GRadius.pill,
            onActivate: _random,
            semanticLabel: 'Random game',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
              decoration: BoxDecoration(
                color: GColors.surface,
                borderRadius: BorderRadius.circular(GRadius.pill),
                border: Border.all(color: GColors.borderStrong),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _picking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.shuffle, size: 18),
                  const SizedBox(width: GSpace.s2),
                  Text(tr('Random'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text, this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s1),
    decoration: BoxDecoration(
      color: color?.withValues(alpha: 0.14) ?? GColors.surface,
      borderRadius: BorderRadius.circular(GRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color ?? GColors.fgSecondary),
          const SizedBox(width: GSpace.s1 + 2),
        ],
        Text(
          text,
          style: TextStyle(fontSize: GFont.md, color: color ?? GColors.fgSecondary),
        ),
      ],
    ),
  );
}
