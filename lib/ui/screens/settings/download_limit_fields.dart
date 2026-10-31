import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/download_schedule.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/download_providers.dart';
import '../../widgets/controller_dialogs.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// Settings → Storage → Downloads' Speed limit and Only download (#228):
/// app-wide, for every profile on this PC; a change applies to the queue at
/// once. [changed] redraws the card.
List<Widget> downloadLimitFields(BuildContext context, WidgetRef ref, VoidCallback changed) {
  final prefs = ref.watch(appPreferencesProvider);
  final limits = DownloadLimits.of(prefs);

  Future<void> pickSpeed() async {
    const speeds = DownloadLimits.speeds;
    final i = await showChoice(
      context,
      title: tr('Speed limit'),
      labels: [for (final s in speeds) DownloadLimits.speedLabel(s)],
      current: speeds.indexOf(limits.megabytesPerSecond),
    );
    if (i == null) return;
    await prefs.setString(DownloadLimits.speedKey, '${speeds[i]}');
    changed();
  }

  Future<void> pickWindow() async {
    // A saved window that isn't a preset (written by hand) is offered too.
    final windows = <DownloadWindow?>[
      null,
      ...DownloadWindow.presets,
      if (limits.window case final w? when !DownloadWindow.presets.contains(w)) w,
    ];
    final i = await showChoice(
      context,
      title: tr('Only download'),
      labels: [
        for (final w in windows) w == null ? tr('Any time') : tr('Between {0}', [w.label]),
      ],
      current: windows.indexOf(limits.window),
    );
    if (i == null) return;
    final w = windows[i];
    w == null ? await prefs.remove(DownloadLimits.windowKey) : await prefs.setString(DownloadLimits.windowKey, '$w');
    ref.read(downloadsProvider.notifier).limitsChanged();
    changed();
  }

  return [
    SettingsField(
      key: const ValueKey('download-speed'),
      label: tr('Speed limit'),
      icon: Icons.speed,
      value: DownloadLimits.speedLabel(limits.megabytesPerSecond),
      action: tr('Change'),
      onActivate: pickSpeed,
    ),
    SettingsField(
      key: const ValueKey('download-window'),
      label: tr('Only download'),
      icon: Icons.schedule,
      value: limits.window == null ? tr('Any time') : tr('Between {0}', [limits.window!.label]),
      action: tr('Change'),
      onActivate: pickWindow,
    ),
  ];
}
