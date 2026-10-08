import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/romm/romm_models.dart';
import '../../../providers/library_providers.dart';
import '../../input/gargosy_intents.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/hint_bar.dart';
import 'achievements_tab.dart';
import 'details_tab.dart';
import 'game_header.dart';
import 'notes_tab.dart';
import 'overview_tab.dart';
import 'save_data_tab.dart';
import '../../widgets/favourite.dart';

/// The game page, after v2's GameDetails (spec §7): background art, the cover
/// column with the actions, then the title and the tabs. LB/RB switch tabs.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.game});

  final Game game;

  static const tabs = ['Overview', 'Save data', 'Achievements', 'Notes', 'Details'];

  /// The tab bodies, in the order of [tabs].
  static final List<Widget Function(Game)> tabBuilders = [
    (g) => OverviewTab(game: g),
    (g) => SaveDataTab(game: g),
    (g) => AchievementsTab(game: g),
    (g) => NotesTab(game: g),
    (g) => DetailsTab(game: g),
  ];

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  int _tab = 0;

  void _go(int i) {
    if (i < 0 || i >= GameScreen.tabs.length) return;
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider(widget.game.id)).valueOrNull ?? widget.game;
    final art = assetUrl(ref, game.fanartUrl ?? game.screenshotUrl) ?? coverUrlFor(ref, game);
    final released = game.firstReleaseDate == null ? null : DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!).year;
    final meta = [game.platformDisplayName, if (released != null) '$released', if (game.averageRating != null) '★ ${game.averageRating!.toStringAsFixed(1)}']
        .whereType<String>()
        .join('  ·  ');
    return Actions(
      actions: {
        PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => _go(_tab - 1)),
        NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => _go(_tab + 1)),
        FavoriteIntent: CallbackAction<FavoriteIntent>(onInvoke: (_) => favourite(context, ref, game)),
      },
      child: Scaffold(
        backgroundColor: GColors.bg,
        body: Stack(children: [
          if (art != null)
            Positioned.fill(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s10, GSpace.rowPad, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                CoverImage(url: coverUrlFor(ref, game), title: game.displayName, width: 240, height: 324),
                const SizedBox(height: GSpace.s5),
                GameActions(game: game),
              ]),
              const SizedBox(width: GSpace.s10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(game.displayName, style: const TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: GSpace.s2),
                  Text(meta, style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary)),
                  const SizedBox(height: GSpace.s5),
                  Row(children: [
                    for (var i = 0; i < GameScreen.tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: GSpace.s2),
                        child: GFocusable(
                          borderRadius: GRadius.pill,
                          onActivate: () => _go(i),
                          child: AnimatedContainer(
                            duration: GMotion.fast,
                            padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
                            decoration: BoxDecoration(
                              color: i == _tab ? GColors.fg : GColors.surface,
                              borderRadius: BorderRadius.circular(GRadius.pill),
                            ),
                            child: Text(GameScreen.tabs[i],
                                style: TextStyle(fontWeight: FontWeight.w600, color: i == _tab ? GColors.bg : GColors.fgSecondary)),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: GSpace.s5),
                  Expanded(child: KeyedSubtree(key: ValueKey(_tab), child: GameScreen.tabBuilders[_tab](game))),
                ]),
              ),
            ]),
          ),
          const Positioned(
            left: 0,
            bottom: 0,
            child: HintBar(hints: [
              Hint(GameAction.back, 'Back'),
              Hint(GameAction.l1, 'Previous tab'),
              Hint(GameAction.r1, 'Next tab'),
              Hint(GameAction.favorite, 'Favourite'),
            ]),
          ),
        ]),
      ),
    );
  }
}
