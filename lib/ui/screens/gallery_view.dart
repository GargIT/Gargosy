import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/romm/romm_models.dart';
import '../../library/game_versions.dart';
import '../../library/letter_index.dart';
import '../../library/library_snapshot.dart';
import '../../library/local_gallery.dart';
import '../../providers/download_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/romm_providers.dart';
import '../input/gargosy_intents.dart';
import '../theme/tokens.dart';
import '../widgets/alphabet_rail.dart';
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
    this.pinnedBar = false,
  });

  final GalleryQuery query;
  final String? title;

  /// The bar's filter field hint; null leaves the field out.
  final String? filterHint;
  final String emptyText;
  final bool autofocus;

  /// The bar stays above the grid instead of scrolling with it (the
  /// platform page, where it sits under the pinned tabs).
  final bool pinnedBar;

  @override
  ConsumerState<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends ConsumerState<GalleryView> {
  late GalleryQuery _query = widget.query;
  final List<Game> _games = [];
  int? _total;
  FilterValues _values = const FilterValues();
  bool _loading = false;
  Future<void>? _inFlight;

  /// RomM's first-letter offsets for this order (by name only), as rail letters.
  Map<String, int> _rail = const {};
  final _gridKey = GlobalKey<CoverGridState>();
  final _railKey = GlobalKey<AlphabetRailState>();
  Object? _error;
  int _generation = 0;
  bool _thisPc = false;

  /// The first cover takes focus once, when the page opens: a reload (a
  /// filter typed, a sort picked) never pulls focus into the grid.
  bool _autofocusDone = false;

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
    _rail = const {};
    _error = null;
    _loading = false;
    if (!_thisPc) _loadMore(first: true);
  }

  /// The next page, or with [upTo] every game up to that position in one
  /// request (a jump on the A–Z rail).
  Future<void> _loadMore({bool first = false, int? upTo}) async {
    final api = ref.read(libraryApiProvider);
    if (_thisPc || api == null || _loading || (_total != null && _games.length >= _total!)) return;
    final gen = _generation;
    setState(() => _loading = true);
    final done = Completer<void>();
    _inFlight = done.future;
    try {
      final limit = upTo == null ? RommLibraryApi.pageSize : upTo - _games.length + RommLibraryApi.pageSize;
      final page = await api.page(
        _query,
        offset: _games.length,
        limit: limit,
        withFilterValues: first,
        withCharIndex: first && _query.sort == GallerySort.name,
        // One card per game, its versions folded into it (#95).
        foldVersions: true,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _games.addAll(page.games);
        _total = page.total;
        if (page.filters != null) _values = page.filters!;
        if (page.charIndex != null) _rail = railIndexOf(page.charIndex!);
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } finally {
      done.complete();
    }
  }

  /// X: focus on the rail, at the focused game's letter, else the first
  /// shown game's (the letter whose first game is the last at or before it).
  void _toRail(Map<String, int> rail) {
    if (rail.isEmpty) return;
    final shownAt = _gridKey.currentState?.currentIndex() ?? 0;
    // RomM's letter offsets count its own list, folded versions too.
    final first = _thisPc ? shownAt : _rawIndexOfShown(shownAt);
    String? letter;
    var best = -1;
    for (final e in rail.entries) {
      if (e.value <= first && e.value > best) {
        best = e.value;
        letter = e.key;
      }
    }
    _railKey.currentState?.focusLetter(letter ?? rail.entries.reduce((a, b) => a.value <= b.value ? a : b).key);
  }

  /// The A–Z rail: the first game under [letter] in [rail], loaded first when
  /// it's beyond the pages so far, then scrolled to and focused.
  Future<void> _jump(String letter, Map<String, int> rail) async {
    final at = rail[letter];
    if (at == null) return;
    if (!_thisPc && at >= _games.length) {
      if (_loading) await _inFlight;
      if (!mounted) return;
      await _loadMore(upTo: at);
      if (!mounted || at >= _games.length) return;
    }
    final target = _thisPc ? at : _shownIndexOfRaw(at);
    if (target < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _gridKey.currentState?.jumpTo(target));
    WidgetsBinding.instance.scheduleFrame(); // a click that changes nothing draws none
  }

  /// RomM's games ([_games], in its order) with each game's versions folded
  /// into the first of them: RomM's `group_by_meta_id` groups by one
  /// metadata id, so versions matched by different ids (a patched copy
  /// without IGDB's) still come apart, though `sibling_roms` links them.
  List<Game> get _shown => foldVersions(_games);

  /// The shown game at or after RomM's position [raw] (-1 when none).
  int _shownIndexOfRaw(int raw) {
    final pos = {for (var i = 0; i < _games.length; i++) _games[i].id: i};
    return _shown.indexWhere((g) => pos[g.id]! >= raw);
  }

  /// RomM's position of the shown game at [shown].
  int _rawIndexOfShown(int shown) {
    final list = _shown;
    if (list.isEmpty) return 0;
    final id = list[shown.clamp(0, list.length - 1)].id;
    return _games.indexWhere((g) => g.id == id).clamp(0, _games.length);
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
    List<Game> games = _shown;
    int? total = _total;
    var values = _values;
    if (_thisPc) {
      final local = _onThisPc();
      values = filterValuesOf(local);
      final files = ref.watch(romFilesProvider);
      games = foldVersions(localGallery(local, _query, inScope: (_) => true, installedAt: files.installedAt));
      total = games.length;
    }
    final bar = GalleryBar(
      query: _query,
      onQuery: _setQuery,
      onFilters: () => _filters(values),
      thisPc: _thisPc,
      thisPcCount: _thisPc ? total : null,
      onThisPc: _setThisPc,
      filterHint: widget.filterHint,
    );
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
        if (!widget.pinnedBar) bar,
      ],
    );
    // One grid in every state: the header (and a filter being typed in) stays put.
    final failed = !_thisPc && _error != null && _games.isEmpty;
    final rail = _query.sort != GallerySort.name
        ? const <String, int>{}
        : _thisPc
        ? railIndexOfGames(games)
        : _rail;
    final grid = CoverGrid(
      key: _gridKey,
      header: header,
      games: games,
      total: total,
      placeholder: failed
          ? ErrorRetry(message: describeLoadError(_error!), onRetry: _reload)
          : total == null
          ? const Center(child: CircularProgressIndicator())
          : null,
      emptyText: _thisPc ? 'None of these games are on this PC.' : widget.emptyText,
      autofocus: widget.autofocus && !_autofocusDone,
      coverUrl: (g) => coverUrlFor(ref, g),
      onOpen: (g) => openGameVersion(context, ref, g),
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
    // The rail sits in the grid's right margin, so the covers don't move for it.
    final body = rail.isEmpty
        ? grid
        : Stack(
            children: [
              grid,
              Positioned(
                top: GSpace.s4,
                bottom: GSpace.s4,
                right: (GSpace.rowPad - AlphabetRail.width) / 2,
                child: AlphabetRail(key: _railKey, letters: rail.keys.toSet(), onJump: (l) => _jump(l, rail)),
              ),
            ],
          );
    if (!_autofocusDone && games.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autofocusDone = true;
      });
    }
    final view = Focus(
      skipTraversal: true,
      child: widget.pinnedBar
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar,
                Expanded(child: body),
              ],
            )
          : body,
    );
    // X: to the rail (when sorted by name).
    return Actions(
      actions: {DetailIntent: CallbackAction<DetailIntent>(onInvoke: (_) => _toRail(rail))},
      child: view,
    );
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
