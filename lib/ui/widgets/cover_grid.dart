import 'package:flutter/material.dart';

import '../../core/romm/romm_models.dart';
import '../input/wrap_grid_policy.dart';
import '../theme/tokens.dart';
import 'game_card.dart';

/// A gallery's grid of game cards. Focus wraps between rows (spec §7), and
/// [onEndReached] asks for the next page when the end comes into view.
class CoverGrid extends StatefulWidget {
  const CoverGrid({
    super.key,
    required this.games,
    required this.coverUrl,
    required this.onOpen,
    this.onFavorite,
    this.isFavourite,
    this.isDownloaded,
    this.onEndReached,
    this.total,
    this.header,
    this.footer,
    this.emptyText = 'Nothing here yet',
    this.autofocus = true,
    this.placeholder,
    this.onTopChanged,
  });

  static const gap = GSpace.s5;

  final List<Game> games;
  final String? Function(Game) coverUrl;
  final void Function(Game) onOpen;
  final void Function(Game)? onFavorite;
  final bool Function(Game)? isFavourite;
  final bool Function(Game)? isDownloaded;
  final VoidCallback? onEndReached;
  final int? total;
  final Widget? header;

  /// Shown under the grid (e.g. "Couldn't load more · Retry").
  final Widget? footer;
  final String emptyText;
  final bool autofocus;

  /// Shown under the header instead of the games (loading, an error). The
  /// header stays where it is, so a field in it keeps its focus.
  final Widget? placeholder;

  /// The first game shown at the top changed while scrolling (its position).
  final ValueChanged<int>? onTopChanged;

  /// Columns that fit in [width] (after the row padding on both sides).
  static int columnsFor(double width) {
    final inner = width - 2 * GSpace.rowPad;
    return ((inner + gap) / (GameCard.width + gap)).floor().clamp(1, 20);
  }

  @override
  State<CoverGrid> createState() => CoverGridState();
}

class CoverGridState extends State<CoverGrid> {
  final _scroll = ScrollController();
  int _top = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_reportTop);
  }

  /// [CoverGrid.onTopChanged] when the game the view is at changes: the
  /// focused one while it's on screen, else the first shown.
  void _reportTop() {
    if (!mounted) return;
    final top = _focusedOnScreen() ?? firstVisibleIndex();
    if (top == _top) return;
    _top = top;
    widget.onTopChanged?.call(top);
  }

  final _headerKey = GlobalKey();
  int _columns = 1;

  /// A focus node per position, so a jump can focus the game it lands on.
  final _nodes = <int, FocusNode>{};

  FocusNode _nodeFor(int i) => _nodes.putIfAbsent(i, () => FocusNode(debugLabel: 'cover $i')..addListener(_reportTop));

  /// The focused game's position when its row is on screen, else null.
  int? _focusedOnScreen() {
    if (!_scroll.hasClients) return null;
    for (final e in _nodes.entries) {
      if (!e.value.hasPrimaryFocus || e.value.context == null || e.key >= widget.games.length) continue;
      final header = (_headerKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
      final top = header + GSpace.s4 + (e.key ~/ _columns) * (GameCard.height + CoverGrid.gap);
      final pos = _scroll.position;
      final shown = top + GameCard.height > pos.pixels && top < pos.pixels + pos.viewportDimension;
      return shown ? e.key : null;
    }
    return null;
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// The focused game's position, else the first game whose row shows at
  /// the top of the grid (0 when none).
  int currentIndex() {
    final focused = FocusManager.instance.primaryFocus;
    for (final e in _nodes.entries) {
      if (e.value == focused && e.value.context != null && e.key < widget.games.length) return e.key;
    }
    return firstVisibleIndex();
  }

  /// The first game whose row shows at the top of the grid (0 when none).
  int firstVisibleIndex() {
    if (!_scroll.hasClients || widget.games.isEmpty) return 0;
    final header = (_headerKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
    final into = _scroll.position.pixels - header - GSpace.s4;
    if (into <= 0) return 0;
    // A row more than half scrolled away doesn't count as shown.
    final row = ((into + (GameCard.height + CoverGrid.gap) / 2) / (GameCard.height + CoverGrid.gap)).floor();
    return (row * _columns).clamp(0, widget.games.length - 1);
  }

  /// Scrolls to the game at [index] (already loaded) and focuses it: the
  /// A–Z rail's jump. Every row is as tall, so the offset is known without
  /// building the rows in between. Games just loaded may not be laid out
  /// yet: it tries again over the next frames until the cover is there.
  void jumpTo(int index, {int frames = 6}) {
    if (!mounted || index < 0 || index >= widget.games.length || !_scroll.hasClients) return;
    final header = (_headerKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
    final row = index ~/ _columns;
    final target = header + GSpace.s4 + row * (GameCard.height + CoverGrid.gap);
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    final node = _nodes[index];
    if (node != null && node.context != null && _scroll.position.pixels >= target - 1) {
      node.requestFocus();
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 1 && node?.context != null) {
      node!.requestFocus(); // near the end: the row can't come to the top
      return;
    }
    if (frames == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => jumpTo(index, frames: frames - 1));
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final games = w.games;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columns = CoverGrid.columnsFor(constraints.maxWidth);
        return FocusTraversalGroup(
          policy: WrapGridTraversalPolicy(),
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              if (w.header != null)
                SliverToBoxAdapter(
                  child: KeyedSubtree(key: _headerKey, child: w.header!),
                ),
              if (w.placeholder != null)
                SliverFillRemaining(hasScrollBody: false, child: w.placeholder)
              else if (games.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      w.emptyText,
                      style: const TextStyle(fontSize: GFont.lg, color: GColors.fgMuted),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s4, GSpace.rowPad, GSpace.s14),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: CoverGrid.gap,
                      crossAxisSpacing: CoverGrid.gap,
                      mainAxisExtent: GameCard.height,
                    ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      if (w.onEndReached != null &&
                          i >= games.length - columns * 2 &&
                          (w.total == null || games.length < w.total!)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => w.onEndReached!());
                      }
                      final g = games[i];
                      return Align(
                        alignment: Alignment.topLeft,
                        child: GameCard(
                          game: g,
                          coverUrl: w.coverUrl(g),
                          focusNode: _nodeFor(i),
                          autofocus: w.autofocus && i == 0,
                          favourite: w.isFavourite?.call(g) ?? false,
                          downloaded: w.isDownloaded?.call(g) ?? false,
                          onOpen: () => w.onOpen(g),
                          onFavorite: w.onFavorite == null ? null : () => w.onFavorite!(g),
                        ),
                      );
                    }, childCount: games.length),
                  ),
                ),
              if (w.footer != null && games.isNotEmpty) SliverToBoxAdapter(child: w.footer),
            ],
          ),
        );
      },
    );
  }
}
