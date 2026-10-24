import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/resume_service.dart';
import '../../../play/play_controller.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/save_list/save_labels.dart';
import '../../widgets/toast.dart';

/// The game's newest save state this PC can start in (Resume), or null.
ResumeEntry? newestState(WidgetRef ref, Game game) {
  final states = ref.read(playStatesProvider(PlayMenuKey(game))).valueOrNull ?? const <ResumeEntry>[];
  ResumeEntry? newest;
  for (final s in states) {
    if (!s.resumable) continue; // loaded from the emulator's own menu
    if (newest == null || s.savedAt.isAfter(newest.savedAt)) newest = s;
  }
  return newest;
}

/// Resumes [game]'s newest save state (the game page's Y, Home's Resume),
/// asking first, as the play screen does, when it may roll a newer save back.
Future<void> resumeNewest(BuildContext context, WidgetRef ref, Game game) async {
  final key = PlayMenuKey(game);
  final entry = newestState(ref, game);
  if (entry == null) return;
  // As on the play screen: a state older than the newest save may roll it back.
  final menu = ref.read(playMenuProvider(key)).valueOrNull;
  if (menu != null) {
    final view = buildPlayView(
      catalog: menu.catalog,
      states: ref.read(playStatesProvider(key)).valueOrNull ?? const [],
      platformSlug: game.platformSlug ?? '',
      picked: menu.forThisGame,
      platformDefault: menu.platformDefault,
      installed: menu.installedIds,
    );
    if (view.promptFor(StatePlay(entry)) != null) {
      final ok = await showConfirm(
        context,
        title: 'Resume an older state?',
        body:
            'This state is from ${formatSaveTime(entry.savedAt)}, but your save is from '
            '${formatSaveTime(view.newestSave!)}. Resuming may roll your save back.',
        yes: 'Resume anyway',
        focusYes: false,
      );
      if (!ok || !context.mounted) return;
    }
  }
  final reason = await ref
      .read(playControllerProvider.notifier)
      .resume(
        game,
        entry,
        confirmVersion: (v, i) => showConfirm(
          context,
          title: 'Load a state from another version?',
          body:
              '${entry.slot.label} was made by ${entry.emulatorName} $v; you have $i. '
              'It may not load, or the game may misbehave.',
          yes: 'Load it',
          focusYes: false,
        ),
        onNotice: (m) {
          if (context.mounted) showToast(context, m);
        },
      );
  if (reason != null && context.mounted) showToast(context, reason);
}
