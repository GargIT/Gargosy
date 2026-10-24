import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/deadzone_config.dart';
import '../../../core/platform/window_service.dart';
import '../../../play/quit_combo.dart';
import '../../../profiles/profile_providers.dart';
import '../../shell/user_menu.dart';
import '../../theme/tokens.dart';
import 'settings_rows.dart';

/// Settings → Controller: the stick deadzone and quitting a game with
/// Select + Start (#141), this PC's, for every profile.
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
        title: 'Controller',
        icon: Icons.gamepad,
        note:
            "How far a stick must move before it counts. Raise it if the focus drifts on its own. "
            "This PC's setting, for every profile.",
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Stick deadzone',
                style: TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w600, color: GColors.fgSecondary),
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
              label: 'Back to the default (15 %)',
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
        title: 'Quit a game',
        icon: Icons.power_settings_new,
        note: "This PC's setting, for every profile.",
        children: [
          SettingsToggle(
            label: 'Hold Select + Start to quit',
            note:
                'Held for ${QuitCombo.holdTime.inSeconds} seconds while a game runs: Gargosy closes the emulator '
                'the way its close button does, so it saves first, and syncs as usual.',
            on: ref.watch(quitComboOnProvider),
            onChanged: (on) async {
              await ref.read(appPreferencesProvider).setBool(QuitCombo.prefKey, on);
              ref.invalidate(quitComboOnProvider);
            },
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

/// Settings → Display: fullscreen (F11), remembered for the next start.
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
        title: 'Display',
        icon: Icons.desktop_windows,
        note: 'Gargosy scales with the window, for the couch at 1080p and 4K.',
        children: [
          SettingsToggle(
            label: 'Fullscreen (F11)',
            note: 'Remembered for the next start.',
            on: _full ?? false,
            onChanged: (_) async {
              await toggleFullscreenAndRemember(ref.read(appPreferencesProvider).setBool);
              final v = await WindowService.isFullScreen();
              if (mounted) setState(() => _full = v);
            },
          ),
        ],
      ),
    ],
  );
}
