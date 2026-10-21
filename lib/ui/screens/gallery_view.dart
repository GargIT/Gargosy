import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/romm/romm_models.dart';
import '../../library/library_snapshot.dart';
import '../../library/local_gallery.dart';
import '../../providers/download_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/romm_providers.dart';
import '../theme/tokens.dart';
import '../widgets/cover_grid.dart';
import '../widgets/error_retry.dart';
import '../widgets/g_focusable.dart';
import '../widgets/gallery_bar.dart';
import 'filter_sheet.dart';
import 'game/open_game.dart';
import '../widgets/favourite.dart';

/// A gallery's games for [query], loaded a page at a time as you scroll, with
/// the filter and sort bar (spec §2, #95). Used by the gallery screen and by
/// Search. With On this PC on, the games are the profile's downloaded ones,
/// filtered and sorted by Gargosy itself, with or without RomM.
class GalleryView extends ConsumerStatefulWidget {
  const GalleryView({
    super.key,
    required this.query,
    this.title,
    this.filterHint,
    this.emptyText = 'No games here',
    this.autofocus = true,
  });

  final GalleryQuery query;
  final String? title;

  /// The bar's filter field hint; null leaves the field out.
  final String? filterHint;
  final String emptyText;
  final bool autofocus;

  @override
  ConsumerState<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends ConsumerState<GalleryView> {
  late GalleryQuery _query = widget.query;
  final List<Game> _games = [];
  int? _total;
  FilterValues _values = const FilterValues();
  bool _loading = false;
  Object? _error;
  int _generation = 0;
  bool _thisPc = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(GalleryView old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _query = widget.query;
      _reload();
    }
  }

  void _reload() {
    _generation++;
    _games.clear();
    _total = null;
    _error = null;
    _loading = false;
    if (!_thisPc) _loadMore(first: true);
  }

  Future<void> _loadMore({bool first = false}) async {
    final api = ref.read(libraryApiProvider);
    if (_thisPc || api == null || _loading || (_total != null && _games.length >= _total!)) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await api.page(_query, offset: _games.length, withFilterValues: first);
      if (!mounted || gen != _generation) return;
      setState(() {
        _games.addAll(page.games);
        _total = page.total;
        if (page.filters != null) _values = page.filters!;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setQuery(GalleryQuery next) {
    if (next == _query) return;
    setState(() => _query = next);
    if (!_thisPc) _reload();
  }

  void _setThisPc(bool on) {
    setState(() {
      _thisPc = on;
      // Downloaded is Gargosy's own order; RomM can't sort by it.
      if (!on && _query.sort.group == SortGroup.thisPc) {
        _query = _query.copyWith(sort: GallerySort.name, descending: false);
      }
    });
    _reload();
  }

  Future<void> _filters(FilterValues values) async {
    final next = await showFilterSheet(context, query: _query, values: values);
    if (next != null) _setQuery(next);
  }

  /// The downloaded games in this gallery's scope, before its filters.
  List<Game> _onThisPc() {
    final favs = ref.watch(favouriteIdsProvider);
    final ids = _query.collectionId == null
        ? const <int>{}
        : (ref.watch(collectionsProvider).valueOrNull ?? const <RommCollection>[])
                  .where((c) => c.id == _query.collectionId)
                  .firstOrNull
                  ?.romIds ??
              const <int>{};
    return [
      for (final g in ref.watch(gamesOnThisPcProvider))
        if (inGalleryScope(g, _query, collectionRomIds: ids, favouriteIds: favs)) g,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final favIds = ref.watch(favouriteIdsProvider);
    List<Game> games = _games;
    int? total = _total;
    var values = _values;
    if (_thisPc) {
      final local = _onThisPc();
      values = filterValuesOf(local);
      final files = ref.watch(romFilesProvider);
      games = localGallery(local, _query, inScope: (_) => true, installedAt: files.installedAt);
      total = games.length;
    }
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s4, GSpace.rowPad, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    widget.title!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: GSpace.s4),
                if (total != null)
                  Text(
                    '$total games',
                    style: const TextStyle(fontSize: GFont.lg, color: GColors.fgMuted),
                  ),
              ],
            ),
          ),
        GalleryBar(
          query: _query,
          onQuery: _setQuery,
          onFilters: () => _filters(values),
          thisPc: _thisPc,
          thisPcCount: _thisPc ? total : null,
          onThisPc: _setThisPc,
          filterHint: widget.filterHint,
        ),
      ],
    );
    Widget body;
    if (!_thisPc && _error != null && _games.isEmpty) {
      body = Column(
        children: [
          header,
          Expanded(
            child: ErrorRetry(message: describeLoadError(_error!), onRetry: _reload),
          ),
        ],
      );
    } else if (total == null) {
      body = Column(
        children: [
          header,
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    } else {
      body = CoverGrid(
        header: header,
        games: games,
        total: total,
        emptyText: _thisPc ? 'None of these games are on this PC.' : widget.emptyText,
        autofocus: widget.autofocus,
        coverUrl: (g) => coverUrlFor(ref, g),
        onOpen: (g) => openGame(context, g),
        onFavorite: (g) => favourite(context, ref, g),
        isFavourite: (g) => favIds.contains(g.id),
        isDownloaded: (g) => watchDownloaded(ref, g),
        // After a failed page, nothing more is asked for until Retry.
        onEndReached: _thisPc || _error != null ? null : _loadMore,
        footer: _thisPc || _error == null
            ? null
            : _LoadMoreFailed(
                error: _error!,
                onRetry: () {
                  setState(() => _error = null);
                  _loadMore();
                },
              ),
      );
    }
    return Focus(skipTraversal: true, child: body);
  }
}

class _LoadMoreFailed extends StatelessWidget {
  const _LoadMoreFailed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s14),
    child: Row(
      children: [
        Flexible(
          child: Text(
            "Couldn't load more  ·  ${describeLoadError(error)}",
            style: const TextStyle(color: GColors.fgSecondary),
          ),
        ),
        const SizedBox(width: GSpace.s4),
        GFocusable(
          borderRadius: GRadius.pill,
          onActivate: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s2),
            decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ),
  );
}
