import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../library/download_service.dart';
import '../../../play/play_controller.dart';
import '../../../play/play_time.dart';
import '../../../providers/download_providers.dart';
import '../../../providers/library_providers.dart';
import '../../screens/game/open_game.dart';
import '../../screens/game/resume_newest.dart';
import '../../screens/play/play_screen.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/format.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/game_transition.dart';
import '../../widgets/save_list/save_labels.dart';
import '../../widgets/toast.dart';

/// Home's header (#139): one game over its art. [random] false is the game
/// played last, with Resume when it has a save state; true is the random
/// pick, with Another (Y) to draw again.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, required this.game, required this.random, this.label, this.autofocus = false});

  final Game game;
  final bool random;

  /// Above the name; by default when it was last played, or RANDOM PICK.
  final String? label;
  final bool autofocus;

  static const coverWidth = 190.0;
  static const coverHeight = 256.0;

  Widget _button(
    String text,
    IconData? icon,
    VoidCallback? onPress, {
    bool primary = false,
    bool autofocus = false,
    Key? key,
  }) => GFocusable(
    key: key,
    autofocus: autofocus,
    borderRadius: GRadius.pill,
    onActivate: onPress,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s6, vertical: GSpace.s3),
      decoration: BoxDecoration(
        color: primary ? GColors.primary : GColors.surfaceHover,
        borderRadius: BorderRadius.circular(GRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: GSpace.s2)],
          Text(
            text,
            style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );

  Widget _chip(String text, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s1),
    decoration: BoxDecoration(
      color: (color ?? GColors.fg).withValues(alpha: color == null ? 0.1 : 0.16),
      borderRadius: BorderRadius.circular(GRadius.pill),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: GFont.sm, color: color, fontWeight: color == null ? null : FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = watchDownloaded(ref, game);
    final progress = ref.watch(downloadsProvider)[game.id];
    final playing = ref.watch(playControllerProvider.select((s) => s.runningGameId == game.id));
    // The states only for the game played last: Resume needs them.
    if (!random) ref.watch(playStatesProvider(PlayMenuKey(game)));
    final state = random ? null : newestState(ref, game);
    final played = random ? null : ref.watch(playTimeProvider(game.id)).valueOrNull;
    final released = game.firstReleaseDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!).year;
    final meta = [
      game.platformDisplayName,
      if (released != null) '$released',
      if (game.genres.isNotEmpty) game.genres.take(2).join(', '),
    ].whereType<String>().join(' · ');
    final when = game.lastPlayed == null ? null : formatSaveTime(game.lastPlayed!);
    final top = label ?? (random ? 'RANDOM PICK' : 'LAST PLAYED${when == null ? '' : ' · ${when.toUpperCase()}'}');

    final downloading = progress != null && progress.phase != DownloadPhase.failed;
    final buttons = <Widget>[
      if (state != null)
        _button(
          'Resume',
          Icons.play_arrow,
          playing ? null : () => resumeNewest(context, ref, game),
          primary: true,
          autofocus: autofocus,
          key: const ValueKey('home-resume'),
        ),
      if (downloaded)
        _button(
          playing ? 'Playing…' : 'Play',
          state == null ? Icons.play_arrow : null,
          playing
              ? null
              : () => Navigator.of(context).push(
                  fadeRoute<void>(
                    PlayScreen(
                      game: game,
                      onNotice: (m) {
                        if (context.mounted) showToast(context, m);
                      },
                    ),
                  ),
                ),
          primary: state == null,
          autofocus: autofocus && state == null,
          key: const ValueKey('home-play'),
        )
      else
        _button(
          downloading ? (progress.phase == DownloadPhase.queued ? 'Queued' : 'Downloading…') : 'Download',
          Icons.download,
          downloading ? null : () => ref.read(downloadsProvider.notifier).start(game),
          primary: true,
          autofocus: autofocus,
          key: const ValueKey('home-download'),
        ),
      if (random)
        _button(
          'Another',
          Icons.shuffle,
          () => ref.invalidate(randomGameProvider),
          key: const ValueKey('home-another'),
        ),
      _button('Game page', null, () => openGame(context, game), key: const ValueKey('home-game-page')),
    ];

    // As tall as what it holds (a long name, buttons on two lines), the art
    // behind all of it.
    return Stack(
      key: const ValueKey('home-header'),
      children: [
        Positioned.fill(
          child: GameArtBackdrop(game: game, child: const SizedBox.shrink()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GLayout.navHeight + GSpace.s10, GSpace.rowPad, GSpace.s6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CoverImage(url: coverUrlFor(ref, game), title: game.displayName, width: coverWidth, height: coverHeight),
              const SizedBox(width: GSpace.s8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      top,
                      style: const TextStyle(
                        fontSize: GFont.sm,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: GColors.fgSecondary,
                      ),
                    ),
                    const SizedBox(height: GSpace.s2),
                    Text(
                      game.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800, height: 1.1),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: GSpace.s2),
                      Text(
                        meta,
                        style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary),
                      ),
                    ],
                    if (downloaded || state != null || played != null) ...[
                      const SizedBox(height: GSpace.s3),
                      Wrap(
                        spacing: GSpace.s2,
                        runSpacing: GSpace.s2,
                        children: [
                          if (downloaded) _chip('On this PC', color: GColors.gargosyTeal),
                          if (played != null) _chip('${formatPlayTime(played.total)} played'),
                          if (state != null)
                            _chip(
                              'State from ${formatSaveTime(state.savedAt)}'
                              '${state.emulatorName.isEmpty ? '' : ' · ${state.emulatorName}'}',
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: GSpace.s5),
                    Wrap(spacing: GSpace.s3, runSpacing: GSpace.s3, children: buttons),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
