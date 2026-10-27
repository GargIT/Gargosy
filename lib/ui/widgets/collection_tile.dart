import 'package:flutter/material.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/save/catalog/save_entry.dart';
import '../theme/tokens.dart';
import 'cover_image.dart';
import 'g_focusable.dart';
import 'save_list/player_avatar.dart';
import '../../l10n/tr.dart';

/// A collection on the Collections tab (#121): a mosaic of its covers with
/// marks (smart, shared, another player's, how many are on this PC), its
/// name and a line under it. A opens it, Y a random game of it.
class CollectionTile extends StatelessWidget {
  const CollectionTile({
    super.key,
    required this.collection,
    required this.coverUrls,
    required this.line,
    required this.onOpen,
    this.onRandom,
    this.owner,
    this.onPc = 0,
    this.autofocus = false,
    this.focusNode,
  });

  /// A cover is 140 × 188, as RomM's.
  static const coverAspect = 140 / 188;

  final RommCollection collection;
  final List<String?> coverUrls;

  /// Under the name: "18 games", "64 games · anna".
  final String line;
  final VoidCallback onOpen;
  final VoidCallback? onRandom;

  /// Another player whose collection it is; null for the user's own.
  final SaveOwner? owner;
  final int onPc;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final c = collection;
    final name = c.isFavorite ? tr('Favourites') : c.name;
    return GFocusable(
      key: ValueKey('collection-${c.key}'),
      autofocus: autofocus,
      focusNode: focusNode,
      borderRadius: GRadius.lg,
      onActivate: onOpen,
      onFavorite: onRandom,
      semanticLabel: name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: coverAspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CollectionMosaic(urls: coverUrls, favourite: c.isFavorite),
                if (c.kind == CollectionKind.smart)
                  Positioned(
                    left: GSpace.s2,
                    top: GSpace.s2,
                    child: _Mark(
                      key: const ValueKey('mark-smart'),
                      tooltip: tr('Smart collection'),
                      child: const Icon(Icons.bolt, size: 15, color: GColors.gargosyGold),
                    ),
                  ),
                if (c.kind == CollectionKind.virtual && c.virtualType != null)
                  Positioned(
                    left: GSpace.s2,
                    top: GSpace.s2,
                    child: _Tag(
                      (switch (virtualCollectionTypes[c.virtualType]) {
                        final t? => tr(t),
                        null => c.virtualType!,
                      }).toUpperCase(),
                    ),
                  ),
                if (c.isPublic && c.kind != CollectionKind.virtual)
                  Positioned(
                    right: GSpace.s2,
                    top: GSpace.s2,
                    child: _Mark(
                      key: const ValueKey('mark-shared'),
                      tooltip: tr('Shared on RomM'),
                      child: const Icon(Icons.public, size: 15, color: GColors.gargosyTeal),
                    ),
                  ),
                if (owner != null)
                  Positioned(
                    left: GSpace.s2,
                    bottom: GSpace.s2,
                    child: Tooltip(message: tr('{0}\'s', [owner!.username]), child: PlayerAvatar(owner!, size: 22)),
                  ),
                if (onPc > 0)
                  Positioned(
                    right: GSpace.s2,
                    bottom: GSpace.s2,
                    child: Container(
                      key: const ValueKey('mark-on-pc'),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: GColors.gargosyTeal,
                        borderRadius: BorderRadius.circular(GRadius.pill),
                      ),
                      child: Text(
                        tr('{0} on PC', [onPc]),
                        style: const TextStyle(fontSize: GFont.xs, fontWeight: FontWeight.w700, color: GColors.bg),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: GSpace.s2),
          Text(
            name,
            key: const ValueKey('collection-name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w600),
          ),
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
          ),
        ],
      ),
    );
  }
}

/// Up to four covers in a 2 × 2 mosaic: one fills it; two or three repeat
/// to fill the four places; none shows a mark (a heart for favourites).
class CollectionMosaic extends StatelessWidget {
  const CollectionMosaic({super.key, required this.urls, this.favourite = false, this.radius = GRadius.lg});

  final List<String?> urls;
  final bool favourite;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shown = [for (final u in urls) ?u].take(4).toList();
    final Widget body;
    if (shown.isEmpty) {
      body = Container(
        color: GColors.surface,
        alignment: Alignment.center,
        child: Icon(
          favourite ? Icons.favorite : Icons.bookmark_border,
          size: favourite ? 48 : 28,
          color: favourite ? GColors.fav : GColors.fgMuted,
        ),
      );
    } else if (shown.length == 1) {
      body = CoverImage(url: shown.single, radius: 0);
    } else {
      final four = [for (var i = 0; i < 4; i++) shown[i % shown.length]];
      body = Container(
        color: GColors.bg,
        child: Column(
          children: [
            for (final row in [four.sublist(0, 2), four.sublist(2)])
              Expanded(
                child: Row(
                  children: [
                    for (final u in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(1),
                          child: CoverImage(url: u, radius: 0),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return ClipRRect(
      key: const ValueKey('collection-mosaic'),
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (favourite && shown.isNotEmpty)
            const ColoredBox(
              color: Color(0x5907070F),
              child: Center(child: Icon(Icons.favorite, size: 44, color: GColors.fav)),
            ),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({super.key, required this.tooltip, required this.child});
  final String tooltip;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Color(0xCC07070F), shape: BoxShape.circle),
      child: child,
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(color: const Color(0xCC07070F), borderRadius: BorderRadius.circular(GRadius.pill)),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: GFont.xs,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: GColors.fgSecondary,
      ),
    ),
  );
}
