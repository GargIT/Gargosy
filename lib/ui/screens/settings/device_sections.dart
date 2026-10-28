import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/deadzone_config.dart';
import '../../../core/input/hid_buttons.dart';
import '../../../core/platform/window_service.dart';
import '../../../play/quit_combo.dart';
import '../../../profiles/profile_providers.dart';
import '../../shell/screensaver.dart';
import '../../shell/user_menu.dart';
import '../../widgets/controller_dialogs.dart';
import '../../theme/tokens.dart';
import 'settings_rows.dart';
import 'teach_quit_buttons.dart';
import '../../../l10n/tr.dart';

/// Settings → Controller: the stick deadzone and quitting a game with
/// held buttons (#141) and teaching them to a controller (#171), this PC's, for
/// every profile.
class ControllerSection extends ConsumerStatefulWidget {
  const ControllerSection({super.key});

  @override
  ConsumerState<ControllerSection> createState() => _ControllerSectionState();
}

class _ControllerSectionState extends ConsumerState<ControllerSection> {
  Future<void> _step(double by) async {
    final next = (globalDeadzone + by).clamp(kMinDeadzone, kMaxDeadzone);
    await setGlobalDeadzone(double.parse(next.toStringAsFixed(2)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      SettingsCard(
        title: tr('Controller'),
        icon: Icons.gamepad,
        note: tr(
          'How far a stick must move before it counts. Raise it if the focus drifts on its own. This PC\'s setting, for every profile.',
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Stick deadzone'),
                style: const TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w600, color: GColors.fgSecondary),
              ),
              const SizedBox(height: GSpace.s2),
              Row(
                children: [
                  SettingsButton(
                    icon: Icons.remove,
                    semanticLabel: 'Lower the deadzone',
                    onActivate: () => _step(-0.05),
                  ),
                  const SizedBox(width: GSpace.s3),
                  Expanded(child: _DeadzoneBar(globalDeadzone)),
                  const SizedBox(width: GSpace.s3),
                  SettingsButton(icon: Icons.add, semanticLabel: 'Raise the deadzone', onActivate: () => _step(0.05)),
                ],
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SettingsButton(
              label: tr('Back to the default (15 %)'),
              icon: Icons.restart_alt,
              onActivate: () async {
                await resetDeadzoneSettings();
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      ),
      SettingsCard(
        title: tr('Quit a game'),
        icon: Icons.power_settings_new,
        note: tr(
          'Held for {0} second while a game runs: Gargosy closes the emulator the way its close button does, so it saves first, and syncs as usual. Pick buttons nothing else uses (Game Bar, Steam or the emulator may take Select + Start). This PC\'s setting, for every profile.',
          [QuitCombo.holdTime.inSeconds],
        ),
        children: [
          SettingsField(
            key: const ValueKey('quit-buttons'),
            label: tr('Hold to quit'),
            value: QuitButtons.labelOf(ref.watch(quitButtonsProvider)),
            action: tr('Change'),
            onActivate: () async {
              const choices = [...QuitButtons.values, null];
              final i = await showChoice(
                context,
                title: tr('Hold to quit a game'),
                labels: [for (final b in choices) QuitButtons.labelOf(b)],
                current: choices.indexOf(ref.read(quitButtonsProvider)),
              );
              if (i == null || i < 0) return;
              await ref
                  .read(appPreferencesProvider)
                  .setString(QuitButtons.prefKey, choices[i]?.name ?? QuitButtons.off);
              ref.invalidate(quitButtonsProvider);
            },
          ),
          SettingsField(
            key: const ValueKey('teach-quit-buttons'),
            label: tr('Controllers taught'),
            value: switch (LearnedHidButtons.read(ref.watch(appPreferencesProvider)).length) {
              0 => tr('None (Xbox controllers and the ones SDL\'s list knows need none)'),
              1 => tr('1 controller'),
              final n => tr('{0} controllers', [n]),
            },
            action: tr('Teach'),
            onActivate: () async {
              await showTeachQuitButtons(context);
              if (mounted) setState(() {});
            },
          ),
          if (LearnedHidButtons.read(ref.watch(appPreferencesProvider)).isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: SettingsButton(
                label: tr('Forget taught buttons'),
                icon: Icons.restart_alt,
                onActivate: () async {
                  await LearnedHidButtons.forgetAll(ref.read(appPreferencesProvider));
                  if (mounted) setState(() {});
                },
              ),
            ),
        ],
      ),
    ],
  );
}

/// The deadzone as a value and a bar from the least to the most.
class _DeadzoneBar extends StatelessWidget {
  const _DeadzoneBar(this.value);
  final double value;

  @override
  Widget build(BuildContext context) {
    final f = ((value - kMinDeadzone) / (kMaxDeadzone - kMinDeadzone)).clamp(0.0, 1.0);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: GColors.field,
        borderRadius: BorderRadius.circular(GRadius.chip),
        border: Border.all(color: GColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '${(value * 100).round()} %',
              style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GRadius.pill),
              child: LinearProgressIndicator(
                value: f,
                minHeight: 4,
                color: GColors.primary,
                backgroundColor: GColors.borderStrong,
              ),
            ),
          ),
          const SizedBox(width: GSpace.s3),
          Text(
            '${(kMinDeadzone * 100).round()} – ${(kMaxDeadzone * 100).round()} %',
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
          ),
        ],
      ),
    );
  }
}

/// Settings → Display: fullscreen (F11), remembered for the next start, and
/// the screensaver's wait (#147).
class DisplaySection extends ConsumerStatefulWidget {
  const DisplaySection({super.key});

  @override
  ConsumerState<DisplaySection> createState() => _DisplaySectionState();
}

class _DisplaySectionState extends ConsumerState<DisplaySection> {
  bool? _full;

  @override
  void initState() {
    super.initState();
    WindowService.isFullScreen().then((v) {
      if (mounted) setState(() => _full = v);
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      SettingsCard(
        title: tr('Display'),
        icon: Icons.desktop_windows,
        note: tr('Gargosy scales with the window, for the couch at 1080p and 4K.'),
        children: [
          SettingsToggle(
            label: tr('Fullscreen (F11)'),
            note: tr('Remembered for the next start.'),
            on: _full ?? false,
            onChanged: (_) async {
              await toggleFullscreenAndRemember(ref.read(appPreferencesProvider).setBool);
              final v = await WindowService.isFullScreen();
              if (mounted) setState(() => _full = v);
            },
          ),
          SettingsField(
            key: const ValueKey('screensaver'),
            label: tr('Screensaver'),
            value: ScreensaverDelay.label(ref.watch(screensaverMinutesProvider)),
            action: tr('Change'),
            onActivate: () async {
              const choices = ScreensaverDelay.choices;
              final i = await showChoice(
                context,
                title: tr('Screensaver on Home and the tabs'),
                labels: [for (final n in choices) ScreensaverDelay.label(n)],
                current: choices.indexOf(ref.read(screensaverMinutesProvider)),
              );
              if (i == null || i < 0) return;
              await ref.read(appPreferencesProvider).setString(ScreensaverDelay.prefKey, '${choices[i]}');
              ref.invalidate(screensaverMinutesProvider);
            },
          ),
          // #191: app-wide, so the profile picker shows it too.
          SettingsField(
            key: const ValueKey('language'),
            label: tr('Language'),
            value: ref.watch(languageProvider).label,
            action: tr('Change'),
            onActivate: () async {
              const choices = AppLanguage.values;
              final i = await showChoice(
                context,
                title: tr('Language'),
                labels: [for (final l in choices) l.label],
                current: choices.indexOf(ref.read(languageProvider)),
              );
              if (i == null || i < 0) return;
              await changeLanguage(ref, choices[i]);
            },
          ),
        ],
      ),
    ],
  );
}
