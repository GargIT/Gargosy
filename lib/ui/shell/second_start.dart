import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/window_focus.dart';
import '../../play/outside_launch.dart';
import '../../play/play_controller.dart';
import '../../profiles/profile_providers.dart';
import '../widgets/toast.dart';
import 'shell_menu.dart';
import '../../l10n/tr.dart';

/// #223: another start of Gargosy handed its [args] to this one
/// (`AppInstance`): Gargosy comes to the front, and a `--play` runs here as
/// it would have there. The open profile plays it when it is the one named
/// (or none is); another named profile is switched to first, as Switch
/// profile does. Refused while a game runs or another launch waits.
Future<void> onSecondStart(GlobalKey<NavigatorState> nav, WidgetRef ref, List<String> args) async {
  unawaited(ref.read(windowFocusProvider).bringToFront());
  final launch = OutsideLaunch.parse(args);
  final context = nav.currentContext;
  if (launch == null || context == null) return;
  debugPrint('[Launch] --play ${launch.romId} from another start');
  if (ref.read(playControllerProvider).runningGameId != null) {
    showToast(context, tr('A game is already running. Close it first.'));
    return;
  }
  if (ref.read(outsideLaunchProvider) != null) return;
  final active = ref.read(activeProfileProvider);
  final other = launch.profileId;
  if (active != null && other != null && other != active.profile.id) {
    if (!await readyToLeaveProfile(context, ref)) return;
    // The picker that comes takes it, and opens the named profile.
    ref.read(outsideLaunchProvider.notifier).state = launch;
    ref.read(activeProfileProvider.notifier).signOut();
    return;
  }
  ref.read(outsideLaunchProvider.notifier).state = launch;
}

/// Whether the open profile (none: the picker) runs [launch] itself.
bool launchIsFor(OutsideLaunch launch, String? activeProfileId) =>
    activeProfileId == null || launch.profileId == null || launch.profileId == activeProfileId;
