import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'g_focusable.dart';
import 'game_card.dart';

/// A titled row (v2's Home rows): as many of [itemCount] items from
/// [itemBuilder] as fit the width, each [itemWidth] wide, the row [height]
/// tall (#184: no scrolling sideways). With [onSeeAll], See all takes the
/// last place when they don't all fit, else comes after them when there is
/// room. Nothing when it has no items.
class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.count,
    this.height = GameCard.height,
    this.onSeeAll,
    this.seeAllSize = const Size(GameCard.width, GameCard.coverHeight),
    this.itemWidth = GameCard.width,
  });

  final String title;

  /// Beside the title (how many in all), when known.
  final int? count;
  final int itemCount;
  final Widget Function(BuildContext context, int i) itemBuilder;
  final double height;
  final VoidCallback? onSeeAll;
  final Size seeAllSize;
  final double itemWidth;

  static const _gap = GSpace.s4;

  /// How many items [width] shows, and whether See all is among them.
  static (int, bool) fit({required double width, required double itemWidth, required int count, required bool seeAll}) {
    final places = ((width + _gap) / (itemWidth + _gap)).floor().clamp(1, 1 << 20);
    if (count + (seeAll ? 1 : 0) <= places) return (count, seeAll);
    if (!seeAll) return (places, false);
    return (places == 1 ? 0 : places - 1, true);
  }

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s6, GSpace.rowPad, GSpace.s3),
          child: Text.rich(
            TextSpan(
              text: title,
              children: [
                if (count != null)
                  TextSpan(
                    text: '  $count',
                    style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w400, color: GColors.fgMuted),
                  ),
              ],
            ),
            style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: height + GSpace.s3,
          child: LayoutBuilder(
            builder: (context, box) {
              final (shown, seeAll) = fit(
                width: box.maxWidth - 2 * GSpace.rowPad,
                itemWidth: itemWidth,
                count: itemCount,
                seeAll: onSeeAll != null,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: _gap,
                  children: [
                    for (var i = 0; i < shown; i++) itemBuilder(context, i),
                    if (seeAll) _SeeAll(size: Size(itemWidth, seeAllSize.height), onActivate: onSeeAll!),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.size, required this.onActivate});

  final Size size;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: GFocusable(
      key: const ValueKey('see-all'),
      onActivate: onActivate,
      semanticLabel: 'See all',
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: GColors.surface,
          borderRadius: BorderRadius.circular(GRadius.card),
          border: Border.all(color: GColors.border),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_forward, color: GColors.fgSecondary),
            SizedBox(height: GSpace.s2),
            Text(
              'See all',
              style: TextStyle(fontWeight: FontWeight.w600, color: GColors.fgSecondary),
            ),
          ],
        ),
      ),
    ),
  );
}
