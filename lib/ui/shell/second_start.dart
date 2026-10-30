import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/window_focus.dart';
import '../../core/storage/logger_service.dart';
import '../../play/outside_launch.dart';
import '../../play/play_controller.dart';
import '../../profiles/profile_providers.dart';
import '../widgets/toast.dart';
import 'shell_menu.dart';
import '../../l10n/tr.dart';

/// A profile switch for a handed-over launch is under way.
bool _switching = false;

/// #223: another start of Gargosy handed its [args] to this one
/// (`AppInstance`): Gargosy comes to the front, and a `--play` runs here as
/// it would have there, except that Gargosy stays open after it (the one the
/// player was using; the shortcut's own start has ended already). The open
/// profile plays it when it is the one named (or none is); another named
/// profile is switched to first, as Switch profile does. Refused while a
/// game runs or a switch is under way; a launch still waiting at the picker
/// is replaced by the newer one.
Future<void> onSecondStart(GlobalKey<NavigatorState> nav, WidgetRef ref, List<String> args) async {
  try {
    unawaited(ref.read(windowFocusProvider).bringToFront().catchError((Object _) {}));
    final asked = OutsideLaunch.parse(args);
    final context = nav.currentContext;
    if (asked == null || context == null) return;
    final launch = OutsideLaunch(romId: asked.romId, profileId: asked.profileId, stay: true);
    debugPrint('[Launch] --play ${launch.romId} from another start');
    bool busy() {
      if (_switching) return true;
      if (ref.read(playControllerProvider).runningGameId == null) return false;
      showToast(context, tr('A game is already running. Close it first.'));
      return true;
    }

    if (busy()) return;
    final active = ref.read(activeProfileProvider);
    final other = launch.profileId;
    if (active != null && other != null && other != active.profile.id) {
      _switching = true;
      try {
        if (!await readyToLeaveProfile(context, ref) || !context.mounted) return;
      } finally {
        _switching = false;
      }
      // A game may have started while the switch asked or waited.
      if (busy()) return;
      // The picker that comes takes it, and opens the named profile.
      ref.read(outsideLaunchProvider.notifier).state = launch;
      ref.read(activeProfileProvider.notifier).signOut();
      return;
    }
    ref.read(outsideLaunchProvider.notifier).state = launch;
  } on Object catch (e, s) {
    LoggerService().error(e, s, context: 'Launch');
  }
}

/// Whether the open profile (none: the picker) runs [launch] itself.
bool launchIsFor(OutsideLaunch launch, String? activeProfileId) =>
    activeProfileId == null || launch.profileId == null || launch.profileId == activeProfileId;
