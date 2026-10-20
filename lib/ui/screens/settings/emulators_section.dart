import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/emulator/emulator_strategy.dart';
import '../../../core/emulator/platform_slugs.dart';
import '../../../core/save/state_sync_service.dart';
import '../../../emulators/emulator_library.dart';
import '../../../providers/engine_providers.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import 'settings_rows.dart';

/// Settings → Emulator settings: which installed emulator plays each of the
/// profile's platforms, and the one save-state sync switch (state-sync plan
/// S0.4). Both are this profile's own (its prefs).
class EmulatorsSection extends ConsumerStatefulWidget {
  const EmulatorsSection({super.key});

  @override
  ConsumerState<EmulatorsSection> createState() => _EmulatorsSectionState();
}

class _EmulatorsSectionState extends ConsumerState<EmulatorsSection> {
  Future<void> _choose(String slug, String title, List<({String id, String name})> options, String? current) async {
    final i = await showChoice(
      context,
      title: 'Play $title in',
      labels: [for (final o in options) o.name],
      current: options.indexWhere((o) => o.id == current),
    );
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
        rows.add(
          SettingsField(
            key: ValueKey('emulator-for-${pl.slug}'),
            label: pl.nameForDisplay,
            value: installed[current] ?? options.first.name,
            actionIcon: Icons.expand_more,
            onActivate: () => _choose(pl.slug, pl.nameForDisplay, options, current),
          ),
        );
      }
    }
    // Which installed emulators sync states comes from their strategies, never a list here.
    final strategies = {
      for (final st in registry?.allStrategies ?? const <EmulatorStrategy>[])
        if (installed.containsKey(st.emulatorId)) installed[st.emulatorId]!: st,
    };
    final syncing = [
      for (final e in strategies.entries)
        if (e.value.supportsStateSync) e.key,
    ]..sort();
    final localOnly = [
      for (final e in strategies.entries)
        if (!e.value.supportsStateSync) e.key,
    ]..sort();
    final fromMenu = [
      for (final n in syncing)
        if (!strategies[n]!.supportsStateLoadOnLaunch) n,
    ];
    return ListView(
      children: [
        SettingsCard(
          title: 'Which emulator plays',
          icon: Icons.tune,
          note:
              'For platforms with more than one emulator installed. '
              'A game can still be played in another one from its play screen.',
          children: [
            if (rows.isEmpty)
              const Text('Only one emulator per platform is installed.', style: TextStyle(color: GColors.fgSecondary))
            else
              LayoutBuilder(
                builder: (context, box) {
                  // Two to a row when there's room, as RomM's settings grid.
                  final w = box.maxWidth >= 640 ? (box.maxWidth - GSpace.s4) / 2 : box.maxWidth;
                  return Wrap(
                    spacing: GSpace.s4,
                    runSpacing: GSpace.s4,
                    children: [for (final r in rows) SizedBox(width: w, child: r)],
                  );
                },
              ),
          ],
        ),
        SettingsCard(
          title: 'Save states on RomM',
          icon: Icons.cloud_upload,
          note:
              'Upload save states after playing and bring them down before, like saves. On by default. '
              'States on this PC always work, sync or not.',
          children: [
            if (prefs == null)
              const Text('Open a profile to change this.', style: TextStyle(color: GColors.fgSecondary))
            else
              SettingsToggle(
                key: const ValueKey('state-sync'),
                label: 'Sync save states with RomM',
                on: StateSyncService.isOn(prefs),
                onChanged: (on) async {
                  await prefs.setBool(StateSyncService.enabledKey, on);
                  if (mounted) setState(() {});
                },
              ),
            if (prefs != null) _StateSyncCoverage(syncing: syncing, localOnly: localOnly, fromMenu: fromMenu),
          ],
        ),
      ],
    );
  }
}

/// Which installed emulators the switch covers and which keep their states on
/// this PC, as two lists of names; those that sync but can't start in a state
/// get a line saying where to load one.
class _StateSyncCoverage extends StatelessWidget {
  const _StateSyncCoverage({required this.syncing, required this.localOnly, required this.fromMenu});

  final List<String> syncing;
  final List<String> localOnly;
  final List<String> fromMenu;

  static String _names(List<String> list) =>
      list.length < 2 ? list.join() : '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';

  @override
  Widget build(BuildContext context) {
    const note = TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary, height: 1.4);
    Widget group(String key, IconData icon, String title, Color color, List<String> names) => Column(
      key: ValueKey(key),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: GSpace.s2),
            Text(
              title,
              style: TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
        const SizedBox(height: GSpace.s2),
        Wrap(
          spacing: GSpace.s2,
          runSpacing: GSpace.s2,
          children: [for (final n in names) SettingsBadge(n, color: color)],
        ),
      ],
    );
    if (syncing.isEmpty) return const Text('No installed emulator syncs save states yet.', style: note);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('state-sync-synced', Icons.cloud_done, 'Synced with RomM', GColors.success, syncing),
        if (fromMenu.isNotEmpty) ...[
          const SizedBox(height: GSpace.s2),
          Text('${_names(fromMenu)}: start the game, then load the state from the emulator\'s own menu.', style: note),
        ],
        if (localOnly.isNotEmpty) ...[
          const SizedBox(height: GSpace.s4),
          group('state-sync-local', Icons.computer, 'Only on this PC', GColors.fgSecondary, localOnly),
        ],
      ],
    );
  }
}
