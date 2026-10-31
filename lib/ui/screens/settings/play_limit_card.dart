import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profiles/play_limit.dart';
import '../../../profiles/profile.dart';
import '../../../profiles/profile_providers.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/toast.dart';
import 'age_limit_card.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// Settings → Profile's Play time (#235): minutes a day, counted on every
/// PC, and the hours this profile may play. Changing either asks for a
/// parent's PIN, as the age limit does ([confirmGuardian]).
class PlayLimitCard extends ConsumerWidget {
  const PlayLimitCard({super.key, required this.profile});

  final Profile profile;

  Future<void> _pickMinutes(BuildContext context, WidgetRef ref) async {
    final options = <int?>[null, ...PlayLimit.minuteChoices];
    final i = await showChoice(
      context,
      title: tr('Play time a day'),
      labels: [for (final m in options) PlayLimit.minutesLabel(m)],
      current: options.indexOf(profile.playLimit.minutesPerDay),
    );
    if (i == null || !context.mounted || options[i] == profile.playLimit.minutesPerDay) return;
    await _save(context, ref, profile.playLimit.copyWith(minutesPerDay: () => options[i]));
  }

  Future<void> _pickWindow(BuildContext context, WidgetRef ref) async {
    final now = profile.playLimit.window;
    final options = [null, ...PlayLimit.windowChoices, if (now != null && !PlayLimit.windowChoices.contains(now)) now];
    final i = await showChoice(
      context,
      title: tr('Play between'),
      labels: [for (final w in options) PlayLimit.windowLabel(w)],
      current: options.indexOf(now),
    );
    if (i == null || !context.mounted || options[i] == now) return;
    await _save(context, ref, profile.playLimit.copyWith(window: () => options[i]));
  }

  Future<void> _save(BuildContext context, WidgetRef ref, PlayLimit next) async {
    if (!await confirmGuardian(context, ref, profile) || !context.mounted) return;
    await ref.read(activeProfileProvider.notifier).update(profile.copyWith(playLimit: next));
    if (context.mounted) showToast(context, tr('Play time changed.'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limit = profile.playLimit;
    return SettingsCard(
      title: tr('Play time'),
      icon: Icons.timer_outlined,
      note: tr(
        'Play time a day counts every PC this profile plays on. Five minutes before the time is up Windows plays its alert sound; then the game is closed (emulators that keep a state on close keep one) and its saves sync. An emulator can\'t be opened on its own while a limit is on.',
      ),
      children: [
        SettingsField(
          key: const ValueKey('play-limit-minutes'),
          label: tr('Play time a day'),
          icon: Icons.hourglass_bottom,
          value: PlayLimit.minutesLabel(limit.minutesPerDay),
          action: tr('Change'),
          actionIcon: Icons.edit_outlined,
          onActivate: () => _pickMinutes(context, ref),
        ),
        SettingsField(
          key: const ValueKey('play-limit-window'),
          label: tr('Play between'),
          icon: Icons.schedule,
          value: PlayLimit.windowLabel(limit.window),
          action: tr('Change'),
          actionIcon: Icons.edit_outlined,
          onActivate: () => _pickWindow(context, ref),
        ),
      ],
    );
  }
}
