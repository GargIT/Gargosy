import 'package:flutter/material.dart';

import '../../core/romm/romm_models.dart';
import '../input/wrap_grid_policy.dart';
import '../theme/tokens.dart';
import 'game_card.dart';

/// A gallery's grid of game cards. Focus wraps between rows (spec §7), and
/// [onEndReached] asks for the next page when the end comes into view.
class CoverGrid extends StatelessWidget {
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

  /// Columns that fit in [width] (after the row padding on both sides).
  static int columnsFor(double width) {
    final inner = width - 2 * GSpace.rowPad;
    return ((inner + gap) / (GameCard.width + gap)).floor().clamp(1, 20);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = columnsFor(constraints.maxWidth);
      return FocusTraversalGroup(
        policy: WrapGridTraversalPolicy(),
        child: CustomScrollView(slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
          if (games.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(emptyText, style: const TextStyle(fontSize: GFont.lg, color: GColors.fgMuted))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s4, GSpace.rowPad, GSpace.s14),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  mainAxisExtent: GameCard.height,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (onEndReached != null && i >= games.length - columns * 2 && (total == null || games.length < total!)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => onEndReached!());
                    }
                    final g = games[i];
                    return Align(
                      alignment: Alignment.topLeft,
                      child: GameCard(
                        game: g,
                        coverUrl: coverUrl(g),
                        autofocus: autofocus && i == 0,
                        favourite: isFavourite?.call(g) ?? false,
                        downloaded: isDownloaded?.call(g) ?? false,
                        onOpen: () => onOpen(g),
                        onFavorite: onFavorite == null ? null : () => onFavorite!(g),
                      ),
                    );
                  },
                  childCount: games.length,
                ),
              ),
            ),
          if (footer != null && games.isNotEmpty) SliverToBoxAdapter(child: footer),
        ]),
      );
    });
  }
}
