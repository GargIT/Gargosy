import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/emulator/platform_slugs.dart';
import '../../../core/emulator/retroarch_core_list.dart';
import '../../../core/romm/romm_models.dart';
import '../../../core/save/catalog/save_maker.dart';
import '../../../emulators/emulator_library.dart';
import '../../../providers/engine_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_dropdown.dart';
import '../../widgets/g_focusable.dart';
import '../settings/settings_screen.dart';
import '../../../l10n/tr.dart';

/// The platform page's Emulator tab: which installed emulator plays the
/// platform and RetroArch's core for it (the same setting as Settings →
/// Emulator settings, for this platform only), and the platform's emulators,
/// an uninstalled one with a way to Settings → Emulators.
class EmulatorTab extends ConsumerStatefulWidget {
  const EmulatorTab({super.key, required this.platform});

  final Platform platform;

  @override
  ConsumerState<EmulatorTab> createState() => _EmulatorTabState();
}

class _EmulatorTabState extends ConsumerState<EmulatorTab> {
  final _emulatorField = GlobalKey();
  final _coreField = GlobalKey();
  String? _open;

  Future<void> _pick(
    GlobalKey field,
    String which,
    List<String> labels,
    int current,
    Future<void> Function(int) then,
  ) async {
    setState(() => _open = which);
    final i = await showDropdown(context, field: field, labels: labels, current: current < 0 ? null : current);
    if (!mounted) return;
    setState(() => _open = null);
    if (i == null || i == current) return;
    await then(i);
    if (mounted) setState(() {});
  }

  void _openEmulators() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SettingsScreen(initial: SettingsPage.emulators)));

  @override
  Widget build(BuildContext context) {
    final p = widget.platform;
    final registry = ref.watch(strategyRegistryProvider);
    final infos = {
      for (final e in ref.watch(emulatorsProvider).valueOrNull ?? const <EmulatorInfo>[])
        if (e.supported) e.id: e,
    };
    final ids = <String>[];
    for (final s in registry?.getAllStrategiesForSlug(p.slug) ?? const []) {
      if (infos.containsKey(s.emulatorId) && !ids.contains(s.emulatorId)) ids.add(s.emulatorId);
    }
    final installed = [
      for (final id in ids)
        if (infos[id]!.installedExe != null) id,
    ];
    final preferred = registry?.getStrategyForSlug(p.slug)?.emulatorId;
    // As the play screen: the platform's emulator when installed, else the first installed.
    final current = installed.contains(preferred) ? preferred : installed.firstOrNull;
    final cores = current == 'retroarch' ? getCoresForSlug(p.slug) : const <RetroArchCore>[];
    final coreId = bareCoreId(
      (registry == null ? null : chosenCoreFor(registry.coreOverrides, p.slug)) ?? getDefaultCoreForSlug(p.slug),
    );
    final coreIndex = cores.indexWhere((c) => bareCoreId(c.id) == coreId);
    final name = p.nameForDisplay;
    const label = TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w700, letterSpacing: 1, color: GColors.fgMuted);
    return ListView(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s4, GSpace.rowPad, GSpace.s6),
      children: [
        Container(
          padding: const EdgeInsets.all(GSpace.s5),
          decoration: BoxDecoration(
            color: GColors.card,
            borderRadius: BorderRadius.circular(GRadius.card),
            border: Border.all(color: GColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sports_esports_outlined, size: 16, color: GColors.fgMuted),
                  const SizedBox(width: GSpace.s2),
                  Text(tr('{0} PLAYS IN', [name.toUpperCase()]), style: label),
                ],
              ),
              const SizedBox(height: GSpace.s4),
              Wrap(
                spacing: GSpace.s3,
                runSpacing: GSpace.s3,
                children: [
                  KeyedSubtree(
                    key: _emulatorField,
                    child: GDropdownField(
                      key: const ValueKey('platform-emulator'),
                      icon: Icons.sports_esports_outlined,
                      text: current == null ? tr('No emulator installed') : infos[current]!.name,
                      open: _open == 'emulator',
                      compact: true,
                      onPress: installed.length < 2 || registry == null
                          ? null
                          : () => _pick(
                              _emulatorField,
                              'emulator',
                              [for (final id in installed) infos[id]!.name],
                              installed.indexOf(current!),
                              (i) => registry.setPreference(canonicalPlatformSlug(p.slug), installed[i]),
                            ),
                    ),
                  ),
                  if (cores.isNotEmpty)
                    KeyedSubtree(
                      key: _coreField,
                      child: GDropdownField(
                        key: const ValueKey('platform-core'),
                        icon: Icons.memory,
                        text: tr('Core: {0}', [coreIndex < 0 ? (coreId ?? '–') : cores[coreIndex].displayName]),
                        open: _open == 'core',
                        compact: true,
                        onPress: registry == null
                            ? null
                            : () => _pick(
                                _coreField,
                                'core',
                                [for (final c in cores) c.displayName],
                                coreIndex,
                                (i) => registry.setCoreOverride(p.slug, cores[i].id),
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: GSpace.s3),
              Text(
                tr(
                  'The same as Settings → Emulator settings, for {0} only. A game\'s "Always for this game" on the play screen comes before it.',
                  [name],
                ),
                style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: GSpace.s6),
        Text(tr('EMULATORS FOR {0}', [name.toUpperCase()]), style: label),
        const SizedBox(height: GSpace.s3),
        if (ids.isEmpty)
          Text(tr('Gargosy has no emulator for this platform.'), style: const TextStyle(color: GColors.fgSecondary)),
        for (final id in ids)
          _EmulatorRow(
            key: ValueKey('platform-emulator-$id'),
            name: infos[id]!.name,
            installed: infos[id]!.installedExe != null,
            onInstall: _openEmulators,
          ),
      ],
    );
  }
}

class _EmulatorRow extends StatelessWidget {
  const _EmulatorRow({super.key, required this.name, required this.installed, required this.onInstall});

  final String name;
  final bool installed;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: GSpace.s2),
    padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
    decoration: BoxDecoration(
      color: GColors.card,
      borderRadius: BorderRadius.circular(GRadius.lg),
      border: Border.all(color: GColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (installed)
          Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: GColors.success),
              const SizedBox(width: GSpace.s2),
              Text(
                tr('Installed'),
                style: const TextStyle(color: GColors.success, fontWeight: FontWeight.w600),
              ),
            ],
          )
        else
          GFocusable(
            borderRadius: GRadius.pill,
            onActivate: onInstall,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GRadius.pill),
                border: Border.all(color: GColors.primary),
              ),
              child: Text(
                tr('Install under Emulators'),
                style: const TextStyle(color: GColors.primaryHover, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    ),
  );
}
