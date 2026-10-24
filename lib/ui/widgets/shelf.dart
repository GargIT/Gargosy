import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'g_focusable.dart';
import 'game_card.dart';

/// A titled row (v2's Home rows): [itemCount] items from [itemBuilder], the
/// row [height] tall, and with [onSeeAll] a See all tile at its end. Nothing
/// when it has no items.
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
  });

  final String title;

  /// Beside the title (how many in all), when known.
  final int? count;
  final int itemCount;
  final Widget Function(BuildContext context, int i) itemBuilder;
  final double height;
  final VoidCallback? onSeeAll;
  final Size seeAllSize;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    final n = itemCount + (onSeeAll == null ? 0 : 1);
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
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad),
            itemCount: n,
            separatorBuilder: (_, _) => const SizedBox(width: GSpace.s4),
            itemBuilder: (context, i) =>
                i < itemCount ? itemBuilder(context, i) : _SeeAll(size: seeAllSize, onActivate: onSeeAll!),
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
