import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../emulators/emulator_library.dart';
import '../../../emulators/emulator_templates.dart';
import '../../../l10n/tr.dart';
import '../../../play/play_controller.dart';
import '../../../profiles/profile_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/toast.dart';
import 'settings_rows.dart';

/// Settings → Emulators → New profiles (#301): an installed emulator's
/// settings in this profile become what every new profile starts with
/// (`userdata\templates\<emu>\`), or that is forgotten again.
class EmulatorTemplatesCard extends ConsumerStatefulWidget {
  const EmulatorTemplatesCard({super.key, required this.installed});

  /// The installed emulators, as Settings → Emulators lists them.
  final List<EmulatorInfo> installed;

  @override
  ConsumerState<EmulatorTemplatesCard> createState() => _EmulatorTemplatesCardState();
}

class _EmulatorTemplatesCardState extends ConsumerState<EmulatorTemplatesCard> {
  late Map<String, TemplateInfo> _templates = ref.read(emulatorTemplatesProvider).all();

  bool _gameRunning() {
    if (ref.read(playControllerProvider).runningGameId == null) return false;
    showToast(context, tr('A game is running. Close it first.'), error: true);
    return true;
  }

  Future<void> _use(EmulatorInfo e) async {
    final profile = ref.read(activeProfileProvider);
    if (profile == null || _gameRunning()) return;
    final templates = ref.read(emulatorTemplatesProvider);
    final before = _templates[e.id];
    if (before != null) {
      final ok = await showConfirm(
        context,
        title: tr('Replace the settings new profiles start with?'),
        body: tr('New profiles start with {0}\'s settings for {1} now. They\'re replaced by {2}\'s.', [
          before.profileName,
          e.name,
          profile.profile.name,
        ]),
        yes: tr('Replace'),
        no: tr('Keep'),
      );
      if (!ok || !mounted || _gameRunning()) return;
    }
    try {
      final n = templates.save(e.id, profile.paths, profileName: profile.profile.name);
      if (!mounted) return;
      if (n == 0) {
        showToast(
          context,
          tr('This profile has no settings for {0} yet. Open it or play a game in it first.', [e.name]),
          error: true,
        );
        return;
      }
      showToast(context, tr('New profiles start with these settings for {0}, without sign-ins.', [e.name]));
    } on Object catch (err) {
      if (mounted) showToast(context, tr('Couldn\'t copy the settings for {0}: {1}', [e.name, err]), error: true);
    }
    if (mounted) setState(() => _templates = templates.all());
  }

  void _forget(EmulatorInfo e) {
    final templates = ref.read(emulatorTemplatesProvider);
    try {
      templates.forget(e.id);
      showToast(context, tr('New profiles start with {0}\'s own settings.', [e.name]));
    } on Object catch (err) {
      showToast(context, tr('Couldn\'t forget the settings for {0}: {1}', [e.name, err]), error: true);
    }
    setState(() => _templates = templates.all());
  }

  Widget _row(EmulatorInfo e) {
    final t = _templates[e.id];
    final state = t == null
        ? tr('Its own settings')
        : tr('{0}\'s settings, {1}', [t.profileName, DateFormat.yMMMd().format(t.savedAt)]);
    return LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          Expanded(
            child: Text(
              e.name,
              style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700, color: GColors.fg),
            ),
          ),
          Flexible(
            child: Text(
              state,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: GFont.md, color: t == null ? GColors.fgSecondary : GColors.success),
            ),
          ),
          const SizedBox(width: GSpace.s4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * 0.6),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: GSpace.s2,
              runSpacing: GSpace.s2,
              children: [
                SettingsButton(
                  key: ValueKey('template-use-${e.id}'),
                  label: tr('Use this profile\'s'),
                  icon: Icons.content_copy,
                  onActivate: () => _use(e),
                ),
                if (t != null)
                  SettingsButton(
                    key: ValueKey('template-forget-${e.id}'),
                    label: tr('Forget'),
                    icon: Icons.delete_outline,
                    onActivate: () => _forget(e),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final e in widget.installed)
        if (templateSettings.containsKey(e.id)) e,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return SettingsCard(
      title: tr('New profiles'),
      icon: Icons.person_add_alt,
      note: tr(
        'What a new profile starts with in each emulator: its own settings, or a copy of a profile\'s (buttons, hotkeys, graphics). Saves, states, memory cards and sign-ins are never copied.',
      ),
      children: [for (final e in shown) _row(e)],
    );
  }
}
