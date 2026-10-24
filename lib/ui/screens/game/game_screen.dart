import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/retroachievements/retroachievements_game_models.dart';
import '../../../core/romm/romm_models.dart';
import '../../../core/save/resume_service.dart';
import '../../../core/save/catalog/save_count.dart';
import '../../../play/play_controller.dart';
import '../../../providers/library_providers.dart';
import '../../input/gargosy_intents.dart';
import '../../shell/page_top_bar.dart';
import '../../shell/shell_menu.dart';
import '../../theme/tokens.dart';
import '../../widgets/game_transition.dart';
import '../../widgets/hint_bar.dart';
import 'achievements_tab.dart';
import 'details_tab.dart';
import 'game_cover_column.dart';
import 'game_personal_pills.dart';
import 'game_tabs.dart';
import 'resume_newest.dart';
import 'version_field.dart';
import 'notes_tab.dart';
import 'overview_tab.dart';
import 'saves_tab.dart';

/// The game page (spec Part 1), after Freegosy's in the v2 style: the art
/// behind the page, the cover column (▶ Play, ♥, ⋯), the title, the
/// player's pills and the tabs with their badges. LB/RB switch tabs; Y
/// resumes the newest save state.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.game});

  final Game game;

  static const tabs = ['Overview', 'Saves', 'Achievements', 'Notes', 'Details'];

  /// Where the page starts below the top bar; the play screen uses the same,
  /// so the cover doesn't move between the two.
  static const padding = EdgeInsets.fromLTRB(GSpace.rowPad, GLayout.navHeight + GSpace.s4, GSpace.rowPad, 0);

  /// The title and "platform · year · ★ rating", as the page and the play
  /// screen show them beside the cover.
  static Widget titleBlock(Game game) {
    final released = game.firstReleaseDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!).year;
    final meta = [
      game.platformDisplayName,
      if (released != null) '$released',
      if (game.averageRating != null) '★ ${game.averageRating!.toStringAsFixed(1)}',
    ].whereType<String>().join('  ·  ');
    return titleHero(
      game,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            game.displayName,
            style: const TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800, height: 1.1),
          ),
          const SizedBox(height: GSpace.s2),
          Text(
            meta,
            style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary),
          ),
        ],
      ),
    );
  }

  /// The tab bodies, in the order of [tabs].
  static final List<Widget Function(Game)> tabBuilders = [
    (g) => OverviewTab(game: g),
    (g) => SavesTab(game: g),
    (g) => AchievementsTab(game: g),
    (g) => NotesTab(game: g),
    (g) => DetailsTab(game: g),
  ];

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  int _tab = 0;
  bool _scrolled = false;

  PlayMenuKey get _key => PlayMenuKey(widget.game);

  void _go(int i) {
    if (i < 0 || i >= GameScreen.tabs.length) return;
    setState(() => _tab = i);
  }

  ResumeEntry? _newestState() => newestState(ref, widget.game);

  /// Y: the newest save state, with the play screen's version question.
  Future<void> _resumeNewest(Game game) => resumeNewest(context, ref, game);

  Map<int, String> _badges(Game game) {
    final badges = <int, String>{};
    final catalog = ref.watch(playMenuProvider(_key)).valueOrNull?.catalog;
    if (catalog != null) {
      // Different saves, not copies: one save on this PC, on RomM and in a
      // backup is 1.
      final n = distinctSaveCount(catalog.all);
      if (n > 0) badges[1] = '$n';
    }
    if (game.raId != null && game.raAchievements.isNotEmpty) {
      final progression = ref.watch(raProgressionProvider).valueOrNull?[game.raId];
      if (progression != null) {
        final p = RetroAchievementsGameProgress.fromRomm(
          gameId: game.raId!,
          achievements: game.raAchievements,
          progression: progression,
        );
        badges[2] = '${p.unlockedCount}/${p.totalCount}';
      } else {
        badges[2] = '${game.raAchievements.length}';
      }
    }
    final notes = ref.watch(romNotesProvider(game.id)).valueOrNull?.length ?? 0;
    if (notes > 0) badges[3] = '$notes';
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider(widget.game.id)).valueOrNull ?? widget.game;
    ref.watch(playStatesProvider(_key)); // Y needs the states ready
    final hasStates = _newestState() != null;
    return Actions(
      actions: {
        PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => _go(_tab - 1)),
        NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => _go(_tab + 1)),
        FavoriteIntent: CallbackAction<FavoriteIntent>(onInvoke: (_) => _resumeNewest(game)),
        MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => openUserMenu(context, ref)),
      },
      child: Scaffold(
        backgroundColor: GColors.bg,
        body: GameArtBackdrop(
          game: game,
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.axis != Axis.vertical) return false;
                        final s = n.metrics.pixels > 8;
                        if (s != _scrolled) setState(() => _scrolled = s);
                        return false;
                      },
                      child: Padding(
                        padding: GameScreen.padding,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GameCoverColumn(game: game),
                            const SizedBox(width: GSpace.s10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GameScreen.titleBlock(game),
                                  if (game.siblings.isNotEmpty) ...[
                                    const SizedBox(height: GSpace.s3),
                                    VersionField(game: game),
                                  ],
                                  const SizedBox(height: GSpace.s4),
                                  GamePersonalPills(
                                    // New values from RomM (the game's details arriving) start the pills afresh.
                                    key: ValueKey(
                                      'pills-${game.id}-${game.status}-${game.userRating}-'
                                      '${game.completion}-${game.backlogged}-${game.nowPlaying}',
                                    ),
                                    game: game,
                                  ),
                                  const SizedBox(height: GSpace.s5),
                                  GameTabs(tabs: GameScreen.tabs, index: _tab, onTab: _go, badges: _badges(game)),
                                  const SizedBox(height: GSpace.s5),
                                  Expanded(
                                    child: KeyedSubtree(key: ValueKey(_tab), child: GameScreen.tabBuilders[_tab](game)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Below the page, as on the play screen, so it never covers Back.
                  HintBar(
                    hints: [
                      const Hint(GameAction.back, 'Back'),
                      const Hint(GameAction.l1, 'Previous tab'),
                      const Hint(GameAction.r1, 'Next tab'),
                      if (hasStates) const Hint(GameAction.favorite, 'Resume'),
                    ],
                  ),
                ],
              ),
              Positioned(top: 0, left: 0, right: 0, child: PageTopBar(scrolled: _scrolled)),
            ],
          ),
        ),
      ),
    );
  }
}
