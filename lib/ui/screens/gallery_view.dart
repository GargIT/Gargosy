import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/romm/romm_models.dart';
import '../../providers/download_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/romm_providers.dart';
import '../input/gargosy_intents.dart';
import '../theme/tokens.dart';
import '../widgets/cover_grid.dart';
import '../widgets/error_retry.dart';
import '../widgets/g_focusable.dart';
import 'filter_sheet.dart';
import 'game/open_game.dart';
import '../widgets/favourite.dart';

/// A gallery's games for [query], loaded a page at a time as you scroll, with
/// sort and filters on X (spec §2). Used by the gallery screen and by Search.
class GalleryView extends ConsumerStatefulWidget {
  const GalleryView({super.key, required this.query, this.title, this.emptyText = 'No games here', this.autofocus = true});

  final GalleryQuery query;
  final String? title;
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
    _loadMore(first: true);
  }

  Future<void> _loadMore({bool first = false}) async {
    final api = ref.read(libraryApiProvider);
    if (api == null || _loading || (_total != null && _games.length >= _total!)) return;
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

  Future<void> _filters() async {
    final next = await showFilterSheet(context, query: _query, values: _values);
    if (next == null || next == _query) return;
    setState(() => _query = next);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final favIds = ref.watch(favouriteIdsProvider);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s4, GSpace.rowPad, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (widget.title != null) Text(widget.title!, style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800)),
        if (widget.title != null) const SizedBox(width: GSpace.s4),
        if (_total != null) Text('$_total games', style: const TextStyle(fontSize: GFont.lg, color: GColors.fgMuted)),
        const Spacer(),
        Text('${_query.sort.label}${_query.hasFilters ? '  ·  filtered' : ''}', style: const TextStyle(color: GColors.fgMuted)),
      ]),
    );
    Widget body;
    if (_error != null && _games.isEmpty) {
      body = Column(children: [header, Expanded(child: ErrorRetry(message: describeLoadError(_error!), onRetry: _reload))]);
    } else if (_total == null) {
      body = Column(children: [header, const Expanded(child: Center(child: CircularProgressIndicator()))]);
    } else {
      body = CoverGrid(
        header: header,
        games: _games,
        total: _total,
        emptyText: widget.emptyText,
        autofocus: widget.autofocus,
        coverUrl: (g) => coverUrlFor(ref, g),
        onOpen: (g) => openGame(context, g),
        onFavorite: (g) => favourite(context, ref, g),
        isFavourite: (g) => favIds.contains(g.id),
        isDownloaded: (g) => watchDownloaded(ref, g),
        // After a failed page, nothing more is asked for until Retry.
        onEndReached: _error == null ? _loadMore : null,
        footer: _error == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s14),
                child: Row(children: [
                  Flexible(
                    child: Text("Couldn't load more  ·  ${describeLoadError(_error!)}",
                        style: const TextStyle(color: GColors.fgSecondary)),
                  ),
                  const SizedBox(width: GSpace.s4),
                  GFocusable(
                    borderRadius: GRadius.pill,
                    onActivate: () {
                      setState(() => _error = null);
                      _loadMore();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s2),
                      decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
                      child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
      );
    }
    return Actions(
      actions: {DetailIntent: CallbackAction<DetailIntent>(onInvoke: (_) => _filters())},
      child: Focus(skipTraversal: true, child: body),
    );
  }
}
