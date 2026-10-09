import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../library/library_snapshot.dart';
import '../../../library/upload_queue.dart';
import '../../../play/play_controller.dart';
import '../../../profiles/pin.dart';
import '../../../profiles/profile.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/engine_providers.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/pin_pad.dart';
import '../../widgets/sync_wait.dart';
import '../../widgets/toast.dart';
import 'settings_rows.dart';

/// Settings → Profile: the name, the PIN and deleting the profile (spec §5).
class ProfileSection extends ConsumerWidget {
  const ProfileSection({super.key});

  Future<void> _rename(BuildContext context, WidgetRef ref, Profile p) async {
    final name = await showOnScreenKeyboard(context, title: 'Profile name', initial: p.name);
    if (name == null || name.trim().isEmpty) return;
    await ref.read(activeProfileProvider.notifier).update(p.copyWith(name: name.trim()));
  }

  /// The current PIN, through the profile's gate (5 tries, then a wait).
  Future<bool> _checkCurrent(BuildContext context, WidgetRef ref, Profile p) async {
    final pin = p.pin;
    if (pin == null) return true;
    final gate = ref.read(pinGatesProvider).putIfAbsent(p.id, () => PinGate(pin));
    final ok = await showPinEntry(context, title: 'Current PIN', check: (entered) async {
      switch (await gate.attempt(entered)) {
        case PinResult.ok:
          return null;
        case PinResult.wrong:
          return 'Wrong PIN';
        case PinResult.locked:
          return 'Too many tries. Wait ${gate.lockedFor?.inSeconds ?? 30} seconds.';
      }
    });
    return ok != null;
  }

  Future<void> _choosePin(BuildContext context, WidgetRef ref, Profile p) async {
    if (!await _checkCurrent(context, ref, p) || !context.mounted) return;
    final first = await showPinEntry(context, title: 'Choose a PIN', check: (_) async => null);
    if (first == null || !context.mounted) return;
    final second =
        await showPinEntry(context, title: 'Enter the PIN again', check: (pin) async => pin == first ? null : "The PINs don't match");
    if (second == null) return;
    final hash = await Isolate.run(() => PinHash.create(second));
    ref.read(pinGatesProvider).remove(p.id);
    await ref.read(activeProfileProvider.notifier).update(p.copyWith(pin: hash));
    if (context.mounted) showToast(context, 'The PIN is set.');
  }

  Future<void> _removePin(BuildContext context, WidgetRef ref, Profile p) async {
    if (!await _checkCurrent(context, ref, p)) return;
    ref.read(pinGatesProvider).remove(p.id);
    await ref.read(activeProfileProvider.notifier).update(p.copyWith(clearPin: true));
    if (context.mounted) showToast(context, 'The PIN is removed.');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Profile p) async {
    // The game runs on this profile's data, and its saves sync after: both first.
    if (ref.read(playControllerProvider).runningGameId != null) {
      showToast(context, "Close the game first: a profile can't be deleted while a game runs.");
      return;
    }
    // Saves that never reached RomM go with the profile: say which.
    final queue = await ref.read(uploadQueueProvider.future);
    final waiting = <String>{for (final w in queue?.pending() ?? const []) w.romId};
    final snap = ref.read(librarySnapshotProvider);
    final names = [for (final id in waiting) snap?.find(id)?.displayName ?? 'game $id'];
    final lost = waiting.isEmpty
        ? ''
        : '\n\n${waiting.length == 1 ? "1 save hasn't" : "${waiting.length} saves haven't"} reached RomM yet '
            '(${names.join(', ')}) and ${waiting.length == 1 ? 'is' : 'are'} lost with the profile.';
    if (!context.mounted) return;
    final ok = await showConfirm(context,
        title: 'Delete ${p.name}?',
        body: 'This removes the profile and its saves, states and emulator settings from this PC. '
            'Nothing on the RomM server is deleted.$lost',
        yes: 'Delete',
        no: 'Keep',
        focusYes: false,
        danger: true);
    if (!ok || !context.mounted) return;
    if (!await _checkCurrent(context, ref, p) || !context.mounted) return;
    if (!await waitForSyncIdle(context, ref)) return;
    // The profile's backups box is open in its folder: closed before the folder goes.
    final box = backupsBoxName(p.id);
    if (Hive.isBoxOpen(box)) await Hive.box<List>(box).close();
    ref.read(activeProfileProvider.notifier).signOut();
    ref.read(pinGatesProvider).remove(p.id);
    try {
      await ref.read(profileStoreProvider).delete(p.id);
    } on Object catch (e) {
      // Signed out already; the picker still lists what's left of it.
      debugPrint('[Profiles] delete ${p.id} failed: $e');
    }
    ref.invalidate(profilesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(activeProfileProvider.select((c) => c?.profile));
    if (p == null) return const SizedBox.shrink();
    return ListView(children: [
      const SettingsHeading('Profile', note: 'One RomM user per profile. Its saves and emulator settings are its own.'),
      SettingsRow(label: 'Name', value: p.name, onActivate: () => _rename(context, ref, p)),
      SettingsRow(label: 'RomM account', value: '${p.rommUsername} on ${Uri.tryParse(p.serverUrl)?.host ?? p.serverUrl}'),
      const SettingsHeading('PIN',
          note: "A PIN keeps others in the family from opening this profile. It's a family lock, not security: "
              'anyone using this Windows account can open the Gargosy folder.'),
      if (p.pin == null)
        SettingsRow(label: 'Set a PIN', onActivate: () => _choosePin(context, ref, p))
      else ...[
        SettingsRow(label: 'Change PIN', onActivate: () => _choosePin(context, ref, p)),
        SettingsRow(label: 'Remove PIN', onActivate: () => _removePin(context, ref, p)),
      ],
      const SettingsHeading('Delete'),
      SettingsRow(label: 'Delete profile', danger: true, onActivate: () => _delete(context, ref, p)),
    ]);
  }
}
