import 'package:flutter/material.dart';

import '../../core/romm/romm_models.dart';
import '../theme/tokens.dart';
import 'cover_image.dart';
import 'g_focusable.dart';

/// v2's game card: the cover (158×213), the name and the platform under it,
/// and small marks for downloaded and favourite games.
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

  @override
  Widget build(BuildContext context) {
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
