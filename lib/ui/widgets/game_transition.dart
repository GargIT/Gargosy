import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_models.dart';
import '../../providers/library_providers.dart';
import '../theme/tokens.dart';
import 'cover_image.dart';

/// What the game page and the play screen share so moving between them is
/// smooth: the same art behind both, a fade instead of a slide, and the
/// cover and title held in place (heroes).

/// The game's art, blurred and dimmed, behind [child].
class GameArtBackdrop extends ConsumerWidget {
  const GameArtBackdrop({super.key, required this.game, required this.child});
  final Game game;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = assetUrl(ref, game.fanartUrl ?? game.screenshotUrl) ?? coverUrlFor(ref, game);
    return ColoredBox(
      color: GColors.bg,
      child: Stack(
        children: [
          if (art != null)
            Positioned.fill(
              key: const ValueKey('game-art'),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Opacity(opacity: 0.35, child: CoverImage(url: art, radius: 0)),
              ),
            ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x6607070F), GColors.bg],
                ),
              ),
            ),
          ),
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
