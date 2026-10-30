import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../play/play_controller.dart';
import '../../profiles/profile_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/update_providers.dart';
import '../screens/doc_reader_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../widgets/controller_dialogs.dart';
import '../widgets/sync_wait.dart';
import '../widgets/toast.dart';
import 'user_menu.dart';
import '../../l10n/tr.dart';

List<String> get shellTabs => [tr('Home'), tr('Platforms'), tr('Collections'), tr('Search')];

/// The shell's tab. Pages opened on top (the game page, the gallery) set it
/// from their top bar, then close back to the shell.
final shellTabProvider = StateProvider<int>((ref) => 0);

/// The user menu (Start, or the profile badge) and what its choices do: a
/// settings item opens Settings on its section. The shell and the pages
/// with a top bar share it.
Future<void> openUserMenu(BuildContext context, WidgetRef ref) async {
  final ctx = ref.read(activeProfileProvider);
  if (ctx == null) return;
  final available = ref.read(updateStateProvider).available;
  final downloads = ref.read(downloadsProvider.notifier);
  final choice = await showUserMenu(
    context,
    profile: ctx.profile,
    avatarPath: ctx.paths.avatarFile,
    update: available == null ? null : tr('Update available: {0}', [available.release.version]),
    downloads: downloads.anything ? downloads.pending : null,
  );
  if (!context.mounted) return;
  if (choice == null) return;
  final page = choice.page;
  if (page != null) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(initial: page)));
    return;
  }
  switch (choice.action!) {
    case UserMenuAction.switchProfile:
      if (!await readyToLeaveProfile(context, ref)) return;
      ref.read(activeProfileProvider.notifier).signOut();
    case UserMenuAction.downloads:
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()));
    case UserMenuAction.fullscreen:
      await toggleFullscreenAndRemember(ref.read(appPreferencesProvider).setBool);
    case UserMenuAction.changelog:
      await openDoc(context, ref.read(appRootProvider).changelog);
  }
}

/// Whether the open profile may close now (a switch, or `--play` for another
/// profile, #223): no game runs, the player let its downloads stop, and its
/// sync has finished. Says why not.
Future<bool> readyToLeaveProfile(BuildContext context, WidgetRef ref) async {
  // The game runs on this profile's emulator data; it must close first.
  if (ref.read(playControllerProvider).runningGameId != null) {
    showToast(context, tr('Close the game first: a profile can\'t change while a game runs.'));
    return false;
  }
  // Downloads belong to this profile: switching stops them (#143).
  final pending = ref.read(downloadsProvider.notifier).pending;
  if (pending > 0 &&
      !await showConfirm(
        context,
        title: tr('Stop the downloads?'),
        body: pending == 1
            ? tr('A download is running. Switching profile stops it.')
            : tr('{0} downloads are running or waiting. Switching profile stops them.', [pending]),
        yes: tr('Switch profile'),
        focusYes: false,
      )) {
    return false;
  }
  if (!context.mounted) return false;
  // A sync still running belongs to this profile: it finishes first.
  if (!await waitForSyncIdle(context, ref)) return false;
  return true;
}
