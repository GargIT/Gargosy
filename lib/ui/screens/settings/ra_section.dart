import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/retroachievements/retroachievements_models.dart';
import '../../../retroachievements/ra_account.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/toast.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// Settings → RetroAchievements: the profile's RA login for the emulators
/// (RetroArch signs in with it). The password is used once, for RA's token.
class RaSection extends ConsumerStatefulWidget {
  const RaSection({super.key});

  @override
  ConsumerState<RaSection> createState() => _RaSectionState();
}

class _RaSectionState extends ConsumerState<RaSection> {
  bool _busy = false;

  Future<void> _connect(RaAccount account) async {
    final user = await showOnScreenKeyboard(context, title: tr('RetroAchievements username'));
    if (user == null || user.trim().isEmpty || !mounted) return;
    final password = await showOnScreenKeyboard(context, title: tr('RetroAchievements password'), obscure: true);
    if (password == null || password.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await account.connect(user, password);
      if (mounted) showToast(context, tr('Connected as {0}.', [account.username]));
    } on RetroAchievementsAuthException catch (e) {
      if (mounted) showToast(context, e.message);
    } on Object {
      if (mounted) showToast(context, tr('Couldn\'t reach RetroAchievements. Try again later.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(raAccountProvider);
    if (account == null) return const SizedBox.shrink();
    final user = account.username;
    return ListView(
      children: [
        SettingsCard(
          title: 'RetroAchievements',
          icon: Icons.emoji_events,
          trailing: user == null ? null : SettingsBadge(tr('Connected as @{0}', [user])),
          note: tr(
            'Emulators sign in to RetroAchievements with this profile\'s account. Your password is used once to get a sign-in token from RetroAchievements and is never stored.',
          ),
          children: user == null
              ? [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsButton(
                      label: _busy ? tr('Connecting…') : tr('Connect'),
                      icon: Icons.login,
                      kind: SettingsButtonKind.primary,
                      onActivate: _busy ? null : () => _connect(account),
                    ),
                  ),
                ]
              : [
                  SettingsField(label: tr('Username'), value: user),
                  SettingsToggle(
                    label: tr('Hardcore mode'),
                    note: tr('No save states, rewind or cheats while achievements count.'),
                    on: account.hardcore,
                    onChanged: (on) async {
                      await account.setHardcore(on);
                      if (mounted) setState(() {});
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsButton(
                      label: tr('Disconnect'),
                      icon: Icons.logout,
                      onActivate: () async {
                        await account.disconnect();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
        ),
      ],
    );
  }
}
