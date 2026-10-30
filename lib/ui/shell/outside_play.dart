import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../play/outside_launch.dart';
import '../../play/play_controller.dart';
import '../../providers/library_providers.dart';
import '../../providers/update_providers.dart';
import '../screens/game/open_game.dart';
import '../screens/play/play_screen.dart';
import '../widgets/controller_dialogs.dart';
import '../widgets/game_transition.dart';
import '../widgets/sync_wait.dart';
import '../widgets/toast.dart';
import '../../l10n/tr.dart';

/// #223: the shell's part of `--play`, once the profile is open: the game's
/// page, its play screen starting at once (prompts still asked), and, when
/// the session has ended and its saves are synced, Gargosy closed, so the
/// shortcut or Steam sees the game end. A save that didn't reach RomM is
/// said first. A game that doesn't start leaves Gargosy open, saying why.
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
  // Started: the play screen said so (also after Back while it was starting).
  // Then ended: its game stopped running. A start that is refused stops it
  // too, before anything said started, and Gargosy stays.
  final started = Completer<bool>();
  final ended = Completer<PlayState>();
  final sub = ref.listenManual(playControllerProvider, (prev, next) {
    if (prev?.runningGameId != game.id || next.runningGameId != null) return;
    if (!started.isCompleted) {
      started.complete(false);
    } else if (!ended.isCompleted) {
      ended.complete(next);
    }
  });
  unawaited(openGame(context, game));
  unawaited(
    Navigator.of(context).push(
      fadeRoute<void>(
        PlayScreen(
          game: game,
          autoStart: true,
          onNotice: (m) {
            if (context.mounted) showToast(context, m);
          },
          onStarted: () {
            if (!started.isCompleted) started.complete(true);
          },
        ),
      ),
    ),
  );
  if (!await started.future || launch.stay) return sub.close();
  final end = await ended.future;
  sub.close();
  await ref.read(playControllerProvider.notifier).sessionSettled;
  if (!context.mounted) return;
  if (end.saveProblem) {
    await showNotice(context, title: tr('Your save didn\'t reach RomM'), body: end.message ?? '');
    if (!context.mounted) return;
  }
  if (!await waitForSyncIdle(context, ref)) return;
  debugPrint('[Launch] session ended; closing Gargosy');
  await ref.read(appQuitProvider)();
}
