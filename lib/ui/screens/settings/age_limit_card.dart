import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profiles/age_limit.dart';
import '../../../profiles/profile.dart';
import '../../../profiles/profile_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/profile_pin.dart';
import '../../widgets/toast.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// Settings → Profile's Age limit (#224): the highest age this profile's
/// games may be rated for, and whether unrated games are hidden too.
/// Changing either asks for a parent's PIN (an older profile without a
/// limit); with none, this profile's own; with no PIN anywhere, it isn't
/// locked, and the card says so. A family lock, as the PIN is.
class AgeLimitCard extends ConsumerWidget {
  const AgeLimitCard({super.key, required this.profile});

  final Profile profile;

  static String labelOf(AgeLimit l) => l.maxAge == null ? tr('Off') : tr('Up to {0}', [l.maxAge]);

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final options = <int?>[null, ...AgeLimit.ages];
    final i = await showChoice(
      context,
      title: tr('Age limit'),
      labels: [for (final a in options) labelOf(AgeLimit(maxAge: a))],
      current: options.indexOf(profile.ageLimit.maxAge),
    );
    if (i == null || !context.mounted || options[i] == profile.ageLimit.maxAge) return;
    // Off is off: Hide unrated doesn't come back with the next limit.
    final max = options[i];
    await _save(
      context,
      ref,
      max == null ? AgeLimit.off : AgeLimit(maxAge: max, hideUnrated: profile.ageLimit.hideUnrated),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, AgeLimit next) async {
    if (!await confirmGuardian(context, ref, profile) || !context.mounted) return;
    await ref.read(activeProfileProvider.notifier).update(profile.copyWith(ageLimit: next));
    if (context.mounted) showToast(context, tr('Age limit: {0}', [labelOf(next)]));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limit = profile.ageLimit;
    final all = ref.watch(profilesProvider).valueOrNull;
    // Said only once the profiles are read: never "unlocked" while loading.
    final unlocked = all != null && guardiansOf(all, profile).isEmpty;
    return SettingsCard(
      title: tr('Age limit'),
      icon: Icons.family_restroom,
      note: tr(
        'Games rated above the limit can\'t be played in this profile, and an emulator can\'t be opened on its own. A rating\'s age is its board\'s (PEGI, ESRB …); a game with several counts at its highest.',
      ),
      children: [
        SettingsField(
          key: const ValueKey('age-limit'),
          label: tr('Age limit'),
          icon: Icons.child_care,
          value: labelOf(limit),
          action: tr('Change'),
          actionIcon: Icons.edit_outlined,
          onActivate: () => _change(context, ref),
        ),
        if (limit.isOn)
          SettingsToggle(
            label: tr('Hide unrated games'),
            note: tr('Games without a rating Gargosy can read are hidden too.'),
            on: limit.hideUnrated,
            onChanged: (on) => _save(context, ref, AgeLimit(maxAge: limit.maxAge, hideUnrated: on)),
          ),
        if (unlocked)
          Text(
            profile.pin == null
                ? tr('Anyone can change it: set a PIN on a parent\'s profile (one without an age limit) to lock it.')
                : tr('Changing it asks for this profile\'s PIN. A parent\'s profile with a PIN locks it instead.'),
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
          ),
      ],
    );
  }
}

/// The profiles whose PIN may change [p]'s age limit: the others made
/// before it, without a limit, that have a PIN. One made later (by the
/// child, for the purpose) never counts.
List<Profile> guardiansOf(List<Profile> all, Profile p) => [
  for (final o in all)
    if (o.id != p.id && o.createdAt.isBefore(p.createdAt) && !o.ageLimit.isOn && o.pin != null) o,
];

/// Asks for a parent's PIN before [p]'s age limit changes (which parent,
/// when there are several); with none, [p]'s own PIN; with no PIN at all,
/// true. Wrong tries count toward that profile's lock, as on the picker.
Future<bool> confirmGuardian(BuildContext context, WidgetRef ref, Profile p) async {
  final all = await ref.read(profilesProvider.future);
  if (!context.mounted) return false;
  final guardians = guardiansOf(all, p);
  Profile who = p;
  if (guardians.length > 1) {
    final i = await showChoice(context, title: tr('Whose PIN?'), labels: [for (final g in guardians) g.name]);
    if (i == null || !context.mounted) return false;
    who = guardians[i];
  } else if (guardians.isNotEmpty) {
    who = guardians.single;
  }
  return checkProfilePin(context, ref, who);
}
