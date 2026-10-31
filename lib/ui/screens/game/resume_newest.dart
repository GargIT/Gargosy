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
import '../../../l10n/tr.dart';

/// The game's newest save state this PC can start in (Resume), or null.
ResumeEntry? newestState(WidgetRef ref, Game game) {
  final states = ref.read(playStatesProvider(PlayMenuKey(game))).value ?? const <ResumeEntry>[];
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
  final menu = ref.read(playMenuProvider(key)).value;
  if (menu != null) {
    final view = buildPlayView(
      catalog: menu.catalog,
      states: ref.read(playStatesProvider(key)).value ?? const [],
      platformSlug: game.platformSlug ?? '',
      picked: menu.forThisGame,
      platformDefault: menu.platformDefault,
      installed: menu.installedIds,
    );
    if (view.promptFor(StatePlay(entry)) != null) {
      final ok = await showConfirm(
        context,
        title: tr('Resume an older state?'),
        body: tr('This state is from {0}, but your save is from {1}. Resuming may roll your save back.', [
          formatSaveTime(entry.savedAt),
          formatSaveTime(view.newestSave!),
        ]),
        yes: tr('Resume anyway'),
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
          title: tr('Load a state from another version?'),
          body: tr('{0} was made by {1} {2}; you have {3}. It may not load, or the game may misbehave.', [
            entry.slot.label,
            entry.emulatorName,
            v,
            i,
          ]),
          yes: tr('Load it'),
          focusYes: false,
        ),
        onNotice: (m) {
          if (context.mounted) showToast(context, m);
        },
      );
  if (reason != null && context.mounted) showToast(context, reason);
}
