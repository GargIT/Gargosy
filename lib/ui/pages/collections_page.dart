import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/save/catalog/save_entry.dart';
import '../../library/collection_list.dart';
import '../../library/library_snapshot.dart';
import '../../providers/library_providers.dart';
import '../../providers/romm_providers.dart';
import '../input/wrap_grid_policy.dart';
import '../screens/collection/collection_screen.dart';
import '../screens/game/open_game.dart';
import '../theme/tokens.dart';
import '../widgets/collection_tile.dart';
import '../widgets/error_retry.dart';
import '../widgets/g_dropdown.dart';
import '../widgets/g_focusable.dart';
import '../widgets/gallery_bar.dart';
import '../../l10n/tr.dart';

/// The Collections tab (#121), after RomM v2's: the players' collections
/// (yours first, favourites at the front, and the ones others share) in a
/// panel, then RomM's virtual ones by type. A bar filters them by name,
/// kind and whose, and sorts them.
class CollectionsPage extends ConsumerStatefulWidget {
  const CollectionsPage({super.key});

  @override
  ConsumerState<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends ConsumerState<CollectionsPage> {
  String _filter = '';
  var _kind = CollectionKindFilter.all;
  var _whose = CollectionWhose.everyone;
  var _sort = CollectionSort.name;
  final _sortField = GlobalKey();
  bool _sortOpen = false;

  /// A tile is about this wide; the row takes as many as fit.
  static const _tileWidth = 160.0;

  /// The name and the line under the cover.
  static const _textHeight = 48.0;

  Future<void> _pickSort() async {
    setState(() => _sortOpen = true);
    final i = await showDropdown(
      context,
      field: _sortField,
      labels: [for (final s in CollectionSort.values) s.label],
      current: _sort.index,
    );
    if (!mounted) return;
    setState(() {
      _sortOpen = false;
      if (i != null) _sort = CollectionSort.values[i];
    });
  }

  void _open(RommCollection c) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionScreen(collection: c)));

  Future<void> _random(RommCollection c) async {
    final game = await ref.read(libraryApiProvider)?.randomGame(within: c.query);
    if (game != null && mounted) await openGame(context, game);
  }

  @override
  Widget build(BuildContext context) {
    final regular = ref.watch(collectionsProvider);
    return Padding(
      key: const Key('page-Collections'),
      padding: const EdgeInsets.only(top: GLayout.navHeight + GSpace.s6),
      child: regular.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(message: describeLoadError(e), onRetry: () => ref.invalidate(collectionsProvider)),
        data: _body,
      ),
    );
  }

  Widget _body(List<RommCollection> regular) {
    final userId = ref.watch(rommUserIdProvider);
    final smart = ref.watch(smartCollectionsProvider).value ?? const [];
    final virtual = {
      for (final type in virtualCollectionTypes.keys)
        type: ref.watch(virtualCollectionsProvider(type)).value ?? const <RommCollection>[],
    };
    final onPc = {for (final g in ref.watch(gamesOnThisPcProvider)) ?int.tryParse(g.id)};
    final curated = curatedCollections(
      regular,
      smart,
      userId: userId,
      filter: _filter,
      kind: _kind,
      whose: _whose,
      sort: _sort,
    );
    // Virtual collections are no one's: Whose doesn't apply to them.
    final whose = _kind == CollectionKindFilter.virtual ? CollectionWhose.everyone : _whose;
    final groups = virtualGroups(virtual, filter: _filter, kind: _kind, whose: whose, sort: _sort);
    final virtualCount = virtual.values.fold<int>(0, (n, l) => n + l.length);
    final ownCount = regular.where((c) => !c.isFavorite || c.userId == userId).length + smart.length;
    final empty = curated.isEmpty && groups.isEmpty;

    Widget tile(RommCollection c, {bool first = false}) {
      final others = c.kind != CollectionKind.virtual && userId != null && c.userId != null && c.userId != userId;
      return CollectionTile(
        collection: c,
        coverUrls: [for (final path in c.coverPaths.take(4)) assetUrl(ref, path)],
        line: [
          '${c.romCount} ${c.romCount == 1 ? 'game' : 'games'}',
          if (others && c.ownerUsername != null) c.ownerUsername!,
        ].join(' · '),
        owner: others ? SaveOwner(userId: c.userId!, username: c.ownerUsername ?? '?') : null,
        onPc: onThisPc(c, onPc),
        autofocus: first,
        onOpen: () => _open(c),
        onRandom: () => _random(c),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(tr('{0} collections · {1} virtual', [ownCount, virtualCount])),
        _bar(),
        Expanded(
          child: empty
              ? Center(
                  child: Text(
                    regular.isEmpty && smart.isEmpty && virtualCount == 0
                        ? tr('No collections yet.')
                        : tr('No collections match.'),
                    style: const TextStyle(color: GColors.fgMuted),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) {
                    final inner = box.maxWidth - 2 * GSpace.rowPad;
                    final columns = ((inner + GSpace.s4) / (_tileWidth + GSpace.s4)).floor().clamp(2, 12);
                    final tileW = (inner - GSpace.s4 * (columns - 1)) / columns;
                    final grid = SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: GSpace.s5,
                      crossAxisSpacing: GSpace.s4,
                      mainAxisExtent: tileW / CollectionTile.coverAspect + _textHeight,
                    );
                    return FocusTraversalGroup(
                      policy: WrapGridTraversalPolicy(),
                      child: CustomScrollView(
                        key: const ValueKey('collections-scroll'),
                        slivers: [
                          if (curated.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s6),
                              sliver: DecoratedSliver(
                                decoration: BoxDecoration(
                                  color: GColors.bgElevated,
                                  border: Border.all(color: GColors.border),
                                  borderRadius: BorderRadius.circular(GRadius.md),
                                ),
                                sliver: SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(GSpace.s5, GSpace.s4, GSpace.s5, GSpace.s5),
                                  sliver: SliverMainAxisGroup(
                                    slivers: [
                                      SliverToBoxAdapter(
                                        child: _SectionTitle(icon: Icons.bookmark, text: tr('COLLECTIONS')),
                                      ),
                                      SliverGrid(
                                        gridDelegate: _inset(grid, columns, tileW, GSpace.s5 * 2),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, i) => tile(curated[i], first: i == 0),
                                          childCount: curated.length,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          for (final (i, (type, items)) in groups.indexed) ...[
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad),
                              sliver: SliverToBoxAdapter(
                                child: _SectionTitle(
                                  icon: Icons.collections_bookmark_outlined,
                                  text: tr('VIRTUAL · {0}', [tr(virtualCollectionTypes[type]!).toUpperCase()]),
                                  count: items.length,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s6),
                              sliver: SliverGrid(
                                gridDelegate: grid,
                                delegate: SliverChildBuilderDelegate(
                                  (context, j) => tile(items[j], first: curated.isEmpty && i == 0 && j == 0),
                                  childCount: items.length,
                                ),
                              ),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: GSpace.s14)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// The same tiles inside the panel, which takes [inset] of the width.
  SliverGridDelegate _inset(SliverGridDelegateWithFixedCrossAxisCount grid, int columns, double tileW, double inset) {
    final w = tileW - inset / columns;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: grid.mainAxisSpacing,
      crossAxisSpacing: grid.crossAxisSpacing,
      mainAxisExtent: w / CollectionTile.coverAspect + _textHeight,
    );
  }

  Widget _heading(String counts) => Padding(
    padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          tr('Collections'),
          style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: GSpace.s3),
        Expanded(
          child: Text(
            counts,
            key: const ValueKey('collections-heading'),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: GColors.fgMuted),
          ),
        ),
      ],
    ),
  );

  Widget _bar() => Padding(
    padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s4),
    // Sort by stays at the right; the rest wraps when the window is narrow.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: GSpace.s3,
            runSpacing: GSpace.s3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: FilterField(
                  key: const ValueKey('collections-filter'),
                  hint: tr('Filter collections…'),
                  text: _filter,
                  onChanged: (t) => setState(() => _filter = t),
                ),
              ),
              _Segments<CollectionKindFilter>(
                keyPrefix: 'kind',
                values: CollectionKindFilter.values,
                current: _kind,
                label: (k) => k.label,
                onPick: (k) => setState(() => _kind = k),
              ),
              _Segments<CollectionWhose>(
                keyPrefix: 'whose',
                values: CollectionWhose.values,
                current: _kind == CollectionKindFilter.virtual ? CollectionWhose.everyone : _whose,
                label: (w) => w.label,
                // Virtual collections are no one's.
                onPick: _kind == CollectionKindFilter.virtual ? null : (w) => setState(() => _whose = w),
              ),
            ],
          ),
        ),
        const SizedBox(width: GSpace.s3),
        KeyedSubtree(
          key: _sortField,
          child: GDropdownField(
            key: const ValueKey('collections-sort'),
            icon: Icons.sort,
            text: tr('Sort by: {0}', [_sort.label]),
            onPress: _pickSort,
            open: _sortOpen,
            compact: true,
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text, this.count});
  final IconData icon;
  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: GSpace.s4),
    child: Row(
      children: [
        Icon(icon, size: 15, color: GColors.primary),
        const SizedBox(width: GSpace.s2),
        Text(
          text,
          style: const TextStyle(
            fontSize: GFont.sm,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: GColors.fgMuted,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: GSpace.s2),
          Text(
            '$count',
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgFaint),
          ),
        ],
      ],
    ),
  );
}

/// A row of choices, one lit ([current]); null [onPick] greys it out.
class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.keyPrefix,
    required this.values,
    required this.current,
    required this.label,
    required this.onPick,
  });

  final String keyPrefix;
  final List<T> values;
  final T current;
  final String Function(T) label;
  final ValueChanged<T>? onPick;

  @override
  Widget build(BuildContext context) {
    final off = onPick == null;
    return Opacity(
      opacity: off ? 0.45 : 1,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: GColors.bgElevated,
          border: Border.all(color: GColors.borderStrong),
          borderRadius: BorderRadius.circular(GRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in values)
              ExcludeFocus(
                excluding: off,
                child: GFocusable(
                  key: ValueKey('$keyPrefix-${label(v)}'),
                  borderRadius: GRadius.pill,
                  onActivate: off ? null : () => onPick!(v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: 6),
                    decoration: BoxDecoration(
                      color: v == current && !off ? GColors.primary : null,
                      borderRadius: BorderRadius.circular(GRadius.pill),
                    ),
                    child: Text(
                      label(v),
                      style: TextStyle(
                        fontSize: GFont.md,
                        fontWeight: v == current ? FontWeight.w600 : FontWeight.w400,
                        color: v == current && !off ? GColors.fg : GColors.fgSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
