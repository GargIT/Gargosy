import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../play/play_controller.dart';
import '../../profiles/profile_providers.dart';
import '../screens/about_screen.dart';
import '../screens/emulators_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../widgets/sync_wait.dart';
import '../widgets/toast.dart';
import 'user_menu.dart';

const shellTabs = ['Home', 'Platforms', 'Collections', 'Search'];

/// The shell's tab. Pages opened on top (the game page, the gallery) set it
/// from their top bar, then close back to the shell.
final shellTabProvider = StateProvider<int>((ref) => 0);

/// The user menu (Start, or the profile badge) and what its choices do; the
/// shell and the pages with a top bar share it.
Future<void> openUserMenu(BuildContext context, WidgetRef ref) async {
  final ctx = ref.read(activeProfileProvider);
  if (ctx == null) return;
  final choice = await showUserMenu(context, name: ctx.profile.name);
  if (!context.mounted) return;
  switch (choice) {
    case UserMenuChoice.switchProfile:
      // The game runs on this profile's emulator data; it must close first.
      if (ref.read(playControllerProvider).runningGameId != null) {
        showToast(context, "Close the game first: a profile can't change while a game runs.");
        return;
      }
      // A sync still running belongs to this profile: it finishes first.
      if (!await waitForSyncIdle(context, ref)) return;
      ref.read(activeProfileProvider.notifier).signOut();
    case UserMenuChoice.settings:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    case UserMenuChoice.emulators:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmulatorsScreen()));
    case UserMenuChoice.about:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));
    case UserMenuChoice.fullscreen:
      await toggleFullscreenAndRemember(ref.read(appPreferencesProvider).setBool);
    case null:
      break;
  }
}
