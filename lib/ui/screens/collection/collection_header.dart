import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_library_api.dart';
import '../../../library/collection_list.dart';
import '../../../library/library_snapshot.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/collection_tile.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/toast.dart';
import '../game/open_game.dart';

/// A collection's page header (#121): its mosaic, the name with its kind,
/// whether it's shared and whose it is, its description (a smart one's
/// filters), how many games it has and how many are on this PC, and Random.
class CollectionHeader extends ConsumerStatefulWidget {
  const CollectionHeader({super.key, required this.collection});

  final RommCollection collection;

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
        showToast(context, 'No games here yet.');
      } else {
        openGame(context, game);
      }
    } on Object catch (e) {
      if (mounted) showToast(context, describeLoadError(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.collection;
    final userId = ref.watch(rommUserIdProvider);
    final downloaded = {for (final g in ref.watch(gamesOnThisPcProvider)) ?int.tryParse(g.id)};
    final platforms = ref.watch(collectionPlatformsProvider(c.query)).valueOrNull;
    final virtual = c.kind == CollectionKind.virtual;
    final whose = virtual || c.userId == null
        ? null
        : c.userId == userId
        ? 'By you'
        : 'By ${c.ownerUsername ?? 'another player'}';
    final about = c.kind == CollectionKind.smart && (c.filterSummary?.isNotEmpty ?? false)
        ? c.filterSummary!
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
                  c.isFavorite ? 'Favourites' : c.name,
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
                        CollectionKind.regular => c.isFavorite ? 'Favourites' : 'Collection',
                        CollectionKind.smart => 'Smart collection',
                        CollectionKind.virtual =>
                          'Virtual · ${virtualCollectionTypes[c.virtualType] ?? c.virtualType ?? 'RomM'}',
                      },
                    ),
                    if (c.isPublic && !virtual)
                      const _Chip(
                        key: ValueKey('collection-shared'),
                        icon: Icons.public,
                        text: 'Shared on RomM',
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
                    _Stat('${c.romCount}', 'GAMES'),
                    _Stat('${onThisPc(c, downloaded)}', 'ON THIS PC', color: GColors.gargosyTeal),
                    if (platforms != null && platforms.isNotEmpty)
                      _Stat('${platforms.length}', 'PLATFORMS', key: const ValueKey('collection-platforms')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: GSpace.s4),
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
                  const Text('Random', style: TextStyle(fontWeight: FontWeight.w600)),
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

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {super.key, this.color});
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
