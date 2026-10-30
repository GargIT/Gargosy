import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../library/library_snapshot.dart';
import '../../../library/upload_queue.dart';
import '../../../play/play_controller.dart';
import '../../../profiles/pin.dart';
import '../../../profiles/profile.dart';
import '../../../profiles/profile_paths.dart';
import '../../../profiles/profile_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/pin_pad.dart';
import '../../widgets/profile_badge.dart';
import '../../widgets/sync_wait.dart';
import '../../widgets/toast.dart';
import '../login_step.dart';
import 'age_limit_card.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// Settings → Profile: the header (avatar, name, account), then cards for the
/// name, the PIN and deleting the profile (spec §5).
class ProfileSection extends ConsumerWidget {
  const ProfileSection({super.key});

  Future<void> _rename(BuildContext context, WidgetRef ref, Profile p) async {
    final name = await showOnScreenKeyboard(context, title: tr('Profile name'), initial: p.name);
    if (name == null || name.trim().isEmpty) return;
    await ref.read(activeProfileProvider.notifier).update(p.copyWith(name: name.trim()));
  }

  /// The current PIN, through the profile's gate (5 tries, then a wait).
  /// Signs the profile in to RomM again, as the same RomM user, and uses the
  /// new login from then on: how a profile gets a permission Gargosy asks for
  /// since it signed in (deleting games). Refused while a game runs.
  Future<void> _signInAgain(BuildContext context, WidgetRef ref, Profile p) async {
    if (ref.read(playControllerProvider).runningGameId != null) {
      showToast(context, tr('Close the game first.'));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          body: LoginStep(
            serverUrl: p.serverUrl,
            trustSelfSigned: p.trustSelfSigned,
            deviceName: tr('Gargosy on {0}', [ref.read(pcIdentityProvider).machineName]),
            expectedUserId: p.rommUserId,
            expectedUsername: p.rommUsername,
            onBack: () => Navigator.of(routeContext).pop(),
            onLoggedIn: (login, me) async {
              await loginStoreForWidget(ref, p).write(ProfilePaths(ref.read(appRootProvider), p.id).guard, login);
              if (routeContext.mounted) Navigator.of(routeContext).pop();
              await ref.read(activeProfileProvider.notifier).activate(p, login);
              if (context.mounted) showToast(context, tr('Signed in again as {0}.', [me.username]));
            },
          ),
        ),
      ),
    );
  }

  Future<bool> _checkCurrent(BuildContext context, WidgetRef ref, Profile p) async {
    final pin = p.pin;
    if (pin == null) return true;
    final gate = ref.read(pinGatesProvider).putIfAbsent(p.id, () => PinGate(pin));
    final ok = await showPinEntry(
      context,
      title: tr('Current PIN'),
      check: (entered) async {
        switch (await gate.attempt(entered)) {
          case PinResult.ok:
            return null;
          case PinResult.wrong:
            return tr('Wrong PIN');
          case PinResult.locked:
            return tr('Too many tries. Wait {0} seconds.', [gate.lockedFor?.inSeconds ?? 30]);
        }
      },
    );
    return ok != null;
  }

  Future<void> _choosePin(BuildContext context, WidgetRef ref, Profile p) async {
    if (!await _checkCurrent(context, ref, p) || !context.mounted) return;
    final first = await showPinEntry(context, title: tr('Choose a PIN'), check: (_) async => null);
    if (first == null || !context.mounted) return;
    final second = await showPinEntry(
      context,
      title: tr('Enter the PIN again'),
      check: (pin) async => pin == first ? null : tr('The PINs don\'t match'),
    );
    if (second == null) return;
    final hash = await Isolate.run(() => PinHash.create(second));
    ref.read(pinGatesProvider).remove(p.id);
    await ref.read(activeProfileProvider.notifier).update(p.copyWith(pin: hash));
    if (context.mounted) showToast(context, tr('The PIN is set.'));
  }

  Future<void> _removePin(BuildContext context, WidgetRef ref, Profile p) async {
    if (!await _checkCurrent(context, ref, p)) return;
    ref.read(pinGatesProvider).remove(p.id);
    await ref.read(activeProfileProvider.notifier).update(p.copyWith(clearPin: true));
    if (context.mounted) showToast(context, tr('The PIN is removed.'));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Profile p) async {
    // The game runs on this profile's data, and its saves sync after: both first.
    if (ref.read(playControllerProvider).runningGameId != null) {
      showToast(context, tr('Close the game first: a profile can\'t be deleted while a game runs.'));
      return;
    }
    // Saves that never reached RomM go with the profile: say which.
    final queue = await ref.read(uploadQueueProvider.future);
    final waiting = <String>{for (final w in queue?.pending() ?? const []) w.romId};
    final snap = ref.read(librarySnapshotProvider);
    final names = [
      for (final id in waiting) snap?.find(id)?.displayName ?? tr('game {0}', [id]),
    ];
    final lost = waiting.isEmpty
        ? ''
        : tr('\n\n{0} reached RomM yet ({1}) and {2} lost with the profile.', [
            waiting.length == 1 ? "1 save hasn't" : "${waiting.length} saves haven't",
            names.join(', '),
            waiting.length == 1 ? 'is' : 'are',
          ]);
    if (!context.mounted) return;
    final ok = await showConfirm(
      context,
      title: tr('Delete {0}?', [p.name]),
      body: tr(
        'This removes the profile and its saves, states and emulator settings from this PC. Nothing on the RomM server is deleted.{0}',
        [lost],
      ),
      yes: tr('Delete'),
      no: tr('Keep'),
      focusYes: false,
      danger: true,
    );
    if (!ok || !context.mounted) return;
    if (!await _checkCurrent(context, ref, p) || !context.mounted) return;
    if (!await waitForSyncIdle(context, ref)) return;
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
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: GSpace.s6),
          child: Row(
            children: [
              ProfileAvatar(profile: p, avatarPath: ctx.paths.avatarFile, size: 94, ring: true),
              const SizedBox(width: GSpace.s6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: GSpace.s1),
                    _InfoLine(Icons.dns_outlined, tr('{0} on {1}', [p.rommUsername, host])),
                    _InfoLine(
                      Icons.calendar_today_outlined,
                      tr('Profile created {0}', [DateFormat('d MMM y').format(p.createdAt)]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SettingsCard(
          title: tr('Profile'),
          icon: Icons.person,
          note: tr('One RomM user per profile. Its saves and emulator settings are its own.'),
          children: [
            SettingsField(
              label: tr('Name'),
              icon: Icons.person_outline,
              value: p.name,
              action: tr('Rename'),
              actionIcon: Icons.edit_outlined,
              onActivate: () => _rename(context, ref, p),
            ),
            SettingsField(
              key: const ValueKey('romm-account'),
              label: tr('RomM account'),
              icon: Icons.dns_outlined,
              value: tr('{0} on {1}', [p.rommUsername, host]),
              action: tr('Sign in again'),
              actionIcon: Icons.login,
              onActivate: () => _signInAgain(context, ref, p),
            ),
          ],
        ),
        SettingsCard(
          title: 'PIN',
          icon: Icons.lock,
          note: tr(
            'A PIN keeps others in the family from opening this profile. It\'s a family lock, not security: anyone using this Windows account can open the Gargosy folder.',
          ),
          children: [
            Wrap(
              spacing: GSpace.s3,
              runSpacing: GSpace.s3,
              children: [
                if (p.pin == null)
                  SettingsButton(
                    label: tr('Set a PIN'),
                    icon: Icons.lock_outline,
                    kind: SettingsButtonKind.primary,
                    onActivate: () => _choosePin(context, ref, p),
                  )
                else ...[
                  SettingsButton(
                    label: tr('Change PIN'),
                    icon: Icons.key_outlined,
                    onActivate: () => _choosePin(context, ref, p),
                  ),
                  SettingsButton(
                    label: tr('Remove PIN'),
                    icon: Icons.lock_open_outlined,
                    onActivate: () => _removePin(context, ref, p),
                  ),
                ],
              ],
            ),
          ],
        ),
        AgeLimitCard(profile: p),
        SettingsCard(
          title: tr('Delete'),
          icon: Icons.delete,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(
                      'Removes this profile\'s saves, states and emulator settings from this PC. What\'s on RomM stays.',
                    ),
                    style: const TextStyle(fontSize: GFont.md, color: GColors.fgSecondary),
                  ),
                ),
                const SizedBox(width: GSpace.s4),
                SettingsButton(
                  label: tr('Delete profile'),
                  icon: Icons.delete_outline,
                  kind: SettingsButtonKind.danger,
                  onActivate: () => _delete(context, ref, p),
                ),
              ],
            ),
          ],
        ),
      ],
    );
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
    child: Row(
      children: [
        Icon(icon, size: 13, color: GColors.fgSecondary),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
          ),
        ),
      ],
    ),
  );
}
