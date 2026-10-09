import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/deadzone_config.dart';
import '../../../core/platform/window_service.dart';
import '../../../profiles/profile_providers.dart';
import '../../shell/user_menu.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';
import 'settings_rows.dart';

/// Settings → Controller: the stick deadzone (this PC's, for every profile).
class ControllerSection extends StatefulWidget {
  const ControllerSection({super.key});

  @override
  State<ControllerSection> createState() => _ControllerSectionState();
}

class _ControllerSectionState extends State<ControllerSection> {
  Future<void> _step(double by) async {
    final next = (globalDeadzone + by).clamp(kMinDeadzone, kMaxDeadzone);
    await setGlobalDeadzone(double.parse(next.toStringAsFixed(2)));
    if (mounted) setState(() {});
  }

  Widget _button(IconData icon, VoidCallback onPress) => Padding(
        padding: const EdgeInsets.only(left: GSpace.s2),
        child: GFocusable(
          borderRadius: GRadius.pill,
          onActivate: onPress,
          child: Container(
            padding: const EdgeInsets.all(GSpace.s2),
            decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
            child: Icon(icon),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListView(children: [
        const SettingsHeading('Controller',
            note: 'How far a stick must move before it counts. Raise it if the focus drifts on its own.'),
        Row(children: [
          Expanded(child: SettingsRow(label: 'Stick deadzone', value: '${(globalDeadzone * 100).round()} %')),
          _button(Icons.remove, () => _step(-0.05)),
          _button(Icons.add, () => _step(0.05)),
        ]),
        SettingsRow(label: 'Back to the default (15 %)', onActivate: () async {
          await resetDeadzoneSettings();
          if (mounted) setState(() {});
        }),
      ]);
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
  Widget build(BuildContext context) => ListView(children: [
        const SettingsHeading('Display', note: 'Gargosy scales with the window, for the couch at 1080p and 4K.'),
        SettingsToggle(
          label: 'Fullscreen (F11)',
          on: _full ?? false,
          onChanged: (_) async {
            await toggleFullscreenAndRemember(ref.read(appPreferencesProvider).setBool);
            final v = await WindowService.isFullScreen();
            if (mounted) setState(() => _full = v);
          },
        ),
      ]);
}
