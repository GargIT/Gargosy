import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/emulator/platform_slugs.dart';
import '../../../core/save/state_sync_service.dart';
import '../../../emulators/emulator_library.dart';
import '../../../providers/engine_providers.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import 'settings_rows.dart';

/// The emulators whose save states can sync with RomM.
const _stateSyncEmulators = ['duckstation', 'pcsx2', 'retroarch'];

/// Settings → Emulator settings: which installed emulator plays each of the
/// profile's platforms, and save-state sync per emulator. Both are this
/// profile's own (its prefs).
class EmulatorsSection extends ConsumerStatefulWidget {
  const EmulatorsSection({super.key});

  @override
  ConsumerState<EmulatorsSection> createState() => _EmulatorsSectionState();
}

class _EmulatorsSectionState extends ConsumerState<EmulatorsSection> {
  Future<void> _choose(String slug, String title, List<({String id, String name})> options, String? current) async {
    final i = await showChoice(context,
        title: 'Play $title in', labels: [for (final o in options) o.name], current: options.indexWhere((o) => o.id == current));
    if (i == null || i < 0) return;
    await ref.read(strategyRegistryProvider)?.setPreference(canonicalPlatformSlug(slug), options[i].id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(strategyRegistryProvider);
    final prefs = ref.watch(profilePrefsProvider);
    final installed = {
      for (final e in ref.watch(emulatorsProvider).valueOrNull ?? const <EmulatorInfo>[])
        if (e.supported && e.installedExe != null) e.id: e.name,
    };
    final platforms = ref.watch(platformsProvider).valueOrNull ?? const [];
    final rows = <Widget>[];
    if (registry != null) {
      for (final pl in platforms) {
        final options = [
          for (final s in registry.getAllStrategiesForSlug(pl.slug))
            if (installed.containsKey(s.emulatorId)) (id: s.emulatorId, name: installed[s.emulatorId]!),
        ];
        if (options.length < 2) continue;
        final current = registry.getStrategyForSlug(pl.slug)?.emulatorId;
        rows.add(SettingsField(
          key: ValueKey('emulator-for-${pl.slug}'),
          label: pl.nameForDisplay,
          value: installed[current] ?? options.first.name,
          actionIcon: Icons.expand_more,
          onActivate: () => _choose(pl.slug, pl.nameForDisplay, options, current),
        ));
      }
    }
    final stateRows = [
      for (final id in _stateSyncEmulators)
        if (installed.containsKey(id) && prefs != null)
          SettingsToggle(
            key: ValueKey('state-sync-$id'),
            label: installed[id]!,
            on: prefs.getBool(StateSyncService.enabledKey(id)) ?? false,
            onChanged: (on) async {
              await prefs.setBool(StateSyncService.enabledKey(id), on);
              if (mounted) setState(() {});
            },
          ),
    ];
    return ListView(children: [
      SettingsCard(
        title: 'Which emulator plays',
        icon: Icons.tune,
        note: 'For platforms with more than one emulator installed. '
            'A game can still be played in another one from its play screen.',
        children: [
          if (rows.isEmpty)
            const Text('Only one emulator per platform is installed.', style: TextStyle(color: GColors.fgSecondary))
          else
            LayoutBuilder(builder: (context, box) {
              // Two to a row when there's room, as RomM's settings grid.
              final w = box.maxWidth >= 640 ? (box.maxWidth - GSpace.s4) / 2 : box.maxWidth;
              return Wrap(spacing: GSpace.s4, runSpacing: GSpace.s4, children: [
                for (final r in rows) SizedBox(width: w, child: r),
              ]);
            }),
        ],
      ),
      SettingsCard(
        title: 'Save states on RomM',
        icon: Icons.cloud_upload,
        rowPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        note: 'Upload save states after playing and bring them down before, like saves. Off by default.',
        children: stateRows.isEmpty
            ? const [Text('No emulator that syncs save states is installed.', style: TextStyle(color: GColors.fgSecondary))]
            : stateRows,
      ),
    ]);
  }
}
