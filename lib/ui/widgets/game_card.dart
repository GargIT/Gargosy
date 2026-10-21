import 'package:flutter/material.dart';

import '../../core/romm/romm_models.dart';
import '../../library/game_versions.dart';
import '../theme/tokens.dart';
import 'cover_image.dart';
import 'g_focusable.dart';

/// v2's game card: the cover (158×213), the name and the platform under it,
/// and marks on the cover: how many versions it folds (top left), on this PC
/// and favourite (top right), its regions (bottom left).
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.game,
    this.coverUrl,
    this.downloaded = false,
    this.favourite = false,
    this.onOpen,
    this.onFavorite,
    this.autofocus = false,
    this.focusNode,
  });

  static const width = 158.0;
  static const coverHeight = 213.0;
  static const height = coverHeight + 52;

  final Game game;
  final String? coverUrl;
  final bool downloaded;
  final bool favourite;
  final VoidCallback? onOpen;
  final VoidCallback? onFavorite;
  final bool autofocus;
  final FocusNode? focusNode;

  static const _maxRegions = 3;

  @override
  Widget build(BuildContext context) {
    final versions = versionCount(game);
    final regions = regionBadges(game.regions);
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GFocusable(
            autofocus: autofocus,
            focusNode: focusNode,
            onActivate: onOpen,
            onFavorite: onFavorite,
            semanticLabel: game.displayName,
            child: Stack(
              children: [
                CoverImage(url: coverUrl, title: game.displayName, width: width, height: coverHeight),
                Positioned(
                  top: GSpace.s2,
                  right: GSpace.s2,
                  child: Row(
                    children: [
                      if (favourite) const _Mark(Icons.favorite, GColors.fav),
                      if (downloaded) const _Mark(Icons.download_done, GColors.success),
                    ],
                  ),
                ),
                if (versions > 1)
                  Positioned(
                    top: GSpace.s2,
                    left: GSpace.s2,
                    child: _Badge(key: const ValueKey('card-versions'), icon: Icons.layers_outlined, text: '$versions'),
                  ),
                if (regions.isNotEmpty)
                  Positioned(
                    left: GSpace.s2,
                    bottom: GSpace.s2,
                    right: GSpace.s2,
                    child: Wrap(
                      spacing: GSpace.s1,
                      runSpacing: GSpace.s1,
                      children: [
                        for (final r in regions.take(_maxRegions)) _Badge(text: r),
                        if (regions.length > _maxRegions) _Badge(text: '+${regions.length - _maxRegions}'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: GSpace.s2),
          Text(
            game.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w600),
          ),
          Text(
            game.platformDisplayName ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
          ),
        ],
      ),
    );
  }
}

/// A small dark pill on the cover: a region (`USA`) or the version count.
class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.text, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: GColors.panel, borderRadius: BorderRadius.circular(GRadius.sm)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: GColors.fgSecondary), const SizedBox(width: 2)],
        Text(
          text,
          style: const TextStyle(fontSize: GFont.xs, fontWeight: FontWeight.w700, color: GColors.fg),
        ),
      ],
    ),
  );
}

class _Mark extends StatelessWidget {
  const _Mark(this.icon, this.color);
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: GSpace.s1),
    padding: const EdgeInsets.all(3),
    decoration: const BoxDecoration(color: GColors.panel, shape: BoxShape.circle),
    child: Icon(icon, size: 14, color: color),
  );
}
