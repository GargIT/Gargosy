import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../play/outside_launch.dart';
import '../../play/play_controller.dart';
import '../../providers/library_providers.dart';
import '../../providers/update_providers.dart';
import '../screens/game/open_game.dart';
import '../screens/play/play_screen.dart';
import '../widgets/game_transition.dart';
import '../widgets/sync_wait.dart';
import '../widgets/toast.dart';
import '../../l10n/tr.dart';

/// #223: the shell's part of `--play`, once the profile is open: the game's
/// page, its play screen starting at once (prompts still asked), and, when
/// the session has ended and its saves are synced, Gargosy closed, so the
/// shortcut or Steam sees the game end. A game that doesn't start leaves
/// Gargosy open on its page, saying why.
Future<void> runOutsideLaunch(BuildContext context, WidgetRef ref) async {
  final launch = ref.read(outsideLaunchProvider);
  if (launch == null) return;
  ref.read(outsideLaunchProvider.notifier).state = null;
  debugPrint('[Launch] --play ${launch.romId}${launch.stay ? ' (stays open)' : ''}');
  final game = await ref.read(gameProvider(launch.romId).future).catchError((Object _) => null);
  if (!context.mounted) return;
  if (game == null) {
    showToast(context, tr('Gargosy couldn\'t find the game {0}.', [launch.romId]));
    return;
  }
  unawaited(openGame(context, game));
  await Navigator.of(context).push(
    fadeRoute<void>(
      PlayScreen(
        game: game,
        autoStart: true,
        onNotice: (m) {
          if (context.mounted) showToast(context, m);
        },
      ),
    ),
  );
  // The play screen closes once the game runs; Back or a refusal leaves it
  // not running, and Gargosy stays.
  if (!context.mounted || launch.stay || ref.read(playControllerProvider).runningGameId != game.id) return;
  final ended = Completer<void>();
  final sub = ref.listenManual(playControllerProvider, (prev, next) {
    if (prev?.runningGameId == game.id && next.runningGameId == null && !ended.isCompleted) ended.complete();
  });
  await ended.future;
  sub.close();
  if (!context.mounted || !await waitForSyncIdle(context, ref)) return;
  debugPrint('[Launch] session ended; closing Gargosy');
  await ref.read(appQuitProvider)();
}
