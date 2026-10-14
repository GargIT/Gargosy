import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../library/library_snapshot.dart';
import '../../../library/upload_queue.dart';
import '../../../play/play_controller.dart';
import '../../../profiles/backups_index.dart';
import '../../../profiles/pin.dart';
import '../../../profiles/profile.dart';
import '../../../profiles/profile_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/pin_pad.dart';
import '../../widgets/profile_badge.dart';
import '../../widgets/sync_wait.dart';
import '../../widgets/toast.dart';
import 'settings_rows.dart';

/// Settings → Profile: the header (avatar, name, account), then cards for the
/// name, the PIN and deleting the profile (spec §5).
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
    // The profile's backup list is open in its folder: closed before the folder goes.
    await closeBackupsBox();
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
    final ctx = ref.watch(activeProfileProvider);
    final p = ctx?.profile;
    if (ctx == null || p == null) return const SizedBox.shrink();
    final host = Uri.tryParse(p.serverUrl)?.host ?? p.serverUrl;
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: GSpace.s6),
        child: Row(children: [
          ProfileAvatar(profile: p, avatarPath: ctx.paths.avatarFile, size: 94, ring: true),
          const SizedBox(width: GSpace.s6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700)),
              const SizedBox(height: GSpace.s1),
              _InfoLine(Icons.dns_outlined, '${p.rommUsername} on $host'),
              _InfoLine(Icons.calendar_today_outlined, 'Profile created ${DateFormat('d MMM y').format(p.createdAt)}'),
            ]),
          ),
        ]),
      ),
      SettingsCard(
        title: 'Profile',
        icon: Icons.person,
        note: 'One RomM user per profile. Its saves and emulator settings are its own.',
        children: [
          SettingsField(
            label: 'Name',
            icon: Icons.person_outline,
            value: p.name,
            action: 'Rename',
            actionIcon: Icons.edit_outlined,
            onActivate: () => _rename(context, ref, p),
          ),
          SettingsField(label: 'RomM account', icon: Icons.dns_outlined, value: '${p.rommUsername} on $host'),
        ],
      ),
      SettingsCard(
        title: 'PIN',
        icon: Icons.lock,
        note: "A PIN keeps others in the family from opening this profile. It's a family lock, not security: "
            'anyone using this Windows account can open the Gargosy folder.',
        children: [
          Wrap(spacing: GSpace.s3, runSpacing: GSpace.s3, children: [
            if (p.pin == null)
              SettingsButton(
                  label: 'Set a PIN',
                  icon: Icons.lock_outline,
                  kind: SettingsButtonKind.primary,
                  onActivate: () => _choosePin(context, ref, p))
            else ...[
              SettingsButton(label: 'Change PIN', icon: Icons.key_outlined, onActivate: () => _choosePin(context, ref, p)),
              SettingsButton(label: 'Remove PIN', icon: Icons.lock_open_outlined, onActivate: () => _removePin(context, ref, p)),
            ],
          ]),
        ],
      ),
      SettingsCard(title: 'Delete', icon: Icons.delete, children: [
        Row(children: [
          const Expanded(
            child: Text("Removes this profile's saves, states and emulator settings from this PC. What's on RomM stays.",
                style: TextStyle(fontSize: GFont.md, color: GColors.fgSecondary)),
          ),
          const SizedBox(width: GSpace.s4),
          SettingsButton(
              label: 'Delete profile',
              icon: Icons.delete_outline,
              kind: SettingsButtonKind.danger,
              onActivate: () => _delete(context, ref, p)),
        ]),
      ]),
    ]);
  }
}

/// A line under the profile's name: an icon and a fact.
class _InfoLine extends StatelessWidget {
  const _InfoLine(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: GSpace.s1),
        child: Row(children: [
          Icon(icon, size: 13, color: GColors.fgSecondary),
          const SizedBox(width: 7),
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary)),
          ),
        ]),
      );
}
