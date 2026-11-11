import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_models.dart';
import '../../providers/library_providers.dart';
import '../theme/tokens.dart';
import 'baked_art.dart';

/// What the game page and the play screen share so moving between them is
/// smooth: the same art behind both, a fade instead of a slide, and the
/// cover and title held in place (heroes).

/// The game's art, blurred and dimmed, behind [child].
class GameArtBackdrop extends ConsumerWidget {
  const GameArtBackdrop({super.key, required this.game, required this.child, this.video, this.onArtShown});
  final Game game;
  final Widget child;

  /// Once the art (or the cover, until the art comes) is drawn, or the game
  /// has none: what Home waits for before its rows.
  final VoidCallback? onArtShown;

  /// Over the art, under the shade (#238): the game's video, when it plays.
  final Widget? video;

  /// How soft the art is: enough to read text over, little enough to see what
  /// the picture is.
  static const blur = 28.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = coverUrlFor(ref, game);
    final art = assetUrl(ref, game.fanartUrl ?? game.screenshotUrl) ?? cover;
    if (art == null && onArtShown != null) WidgetsBinding.instance.addPostFrameCallback((_) => onArtShown!());
    // The shade is baked into the art, except over a video, which goes
    // between them. Without art or video it would only be the page's colour.
    return ColoredBox(
      color: GColors.bg,
      child: Stack(
        children: [
          if (art != null)
            Positioned.fill(
              key: const ValueKey('game-art'),
              child: BakedArt(url: art, quick: cover, blur: blur, shade: video == null, onShown: onArtShown),
            ),
          if (video != null) ...[
            Positioned.fill(child: Opacity(opacity: 0.5, child: video)),
            const Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: BakedArt.shadeGradient)),
            ),
          ],
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// A route that fades [page] in over the one below.
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 180),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  ),
);

/// The game's cover, flown in place between the game page and the play screen.
Widget coverHero(Game game, Widget child) => Hero(tag: ('game-cover', game.id), child: child);

/// The game's title block, flown in place the same way. Text in flight sits
/// in the overlay, outside the page's Material, hence its own.
Widget titleHero(Game game, Widget child) => Hero(
  tag: ('game-title', game.id),
  child: Material(type: MaterialType.transparency, child: child),
);
