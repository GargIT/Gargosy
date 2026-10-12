import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/emulator/platform_slugs.dart';
import '../../../core/save/state_sync_service.dart';
import '../../../emulators/bios_sync.dart';
import '../../../emulators/emulator_library.dart';
import '../../../emulators/ps3_firmware.dart';
import '../../../providers/engine_providers.dart';
import '../../../providers/library_providers.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/toast.dart';
import '../emulators_screen.dart';
import 'settings_rows.dart';

/// The emulators whose save states can sync with RomM.
const _stateSyncEmulators = ['duckstation', 'pcsx2', 'retroarch'];

/// Settings → Emulators: which installed emulator plays each of the
/// profile's platforms, and save-state sync per emulator. Both are this
/// profile's own (its prefs).
class EmulatorsSection extends ConsumerStatefulWidget {
  const EmulatorsSection({super.key});

  @override
  ConsumerState<EmulatorsSection> createState() => _EmulatorsSectionState();
}

class _EmulatorsSectionState extends ConsumerState<EmulatorsSection> {
  bool _gettingBios = false;
  bool _installingFirmware = false;

  /// RPCS3's firmware from bios\, installed once for every profile (issue #10).
  Future<void> _installPs3Firmware(String exe) async {
    final firmware = ref.read(ps3FirmwareProvider);
    if (firmware == null || _installingFirmware) return;
    setState(() => _installingFirmware = true);
    try {
      await firmware.install(exe);
      if (mounted) showToast(context, 'The PS3 firmware is installed, for every profile.');
    } on Ps3FirmwareException catch (e) {
      if (mounted) showToast(context, e.message);
    } on Object catch (e) {
      if (mounted) showToast(context, "Couldn't install the PS3 firmware: $e");
    } finally {
      if (mounted) setState(() => _installingFirmware = false);
    }
  }

  Future<void> _getBios(Set<String> installed) async {
    final bios = ref.read(biosSyncProvider);
    if (bios == null || _gettingBios) return;
    setState(() => _gettingBios = true);
    try {
      final n = await bios.forAll(installed);
      if (!mounted) return;
      showToast(context, switch (n) {
        0 => 'No new BIOS files on RomM.',
        1 => 'Got 1 BIOS file from RomM.',
        _ => 'Got $n BIOS files from RomM.',
      });
    } on Object {
      if (mounted) showToast(context, "Couldn't get BIOS files from RomM.");
    } finally {
      if (mounted) setState(() => _gettingBios = false);
    }
  }

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
    final emulators = ref.watch(emulatorsProvider).valueOrNull ?? const <EmulatorInfo>[];
    final installed = {
      for (final e in emulators)
        if (e.supported && e.installedExe != null) e.id: e.name,
    };
    final rpcs3Exe = emulators.where((e) => e.id == 'rpcs3' && e.supported).firstOrNull?.installedExe;
    final ps3Firmware = ref.watch(ps3FirmwareProvider);
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
        rows.add(SettingsRow(
          label: pl.nameForDisplay,
          value: installed[current] ?? options.first.name,
          onActivate: () => _choose(pl.slug, pl.nameForDisplay, options, current),
        ));
      }
    }
    return ListView(children: [
      const SettingsHeading('Emulators', note: 'Gargosy keeps its own copy of each emulator.'),
      SettingsRow(
        label: 'Install, update or remove emulators',
        onActivate: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmulatorsScreen())),
      ),
      SettingsRow(
        label: _gettingBios ? 'Getting BIOS files…' : 'Get BIOS files from RomM',
        onActivate: _gettingBios ? null : () => _getBios(installed.keys.toSet()),
      ),
      if (rpcs3Exe != null && ps3Firmware != null)
        SettingsRow(
          key: const Key('ps3-firmware'),
          label: _installingFirmware ? 'Installing the PS3 firmware…' : 'Install PS3 firmware from bios\\',
          value: ps3Firmware.installed ? 'Installed' : 'Not installed',
          onActivate: _installingFirmware ? null : () => _installPs3Firmware(rpcs3Exe),
        ),
      const SettingsHeading('Which emulator plays', note: 'For platforms with more than one emulator installed. '
          'A game can still be played in another one from its play screen.'),
      if (rows.isEmpty) const SettingsRow(label: 'Only one emulator per platform is installed') else ...rows,
      const SettingsHeading('Save states on RomM',
          note: 'Upload save states after playing and bring them down before, like saves. Off by default.'),
      for (final id in _stateSyncEmulators)
        if (installed.containsKey(id) && prefs != null)
          SettingsToggle(
            key: ValueKey('state-sync-$id'),
            label: '${installed[id]}: sync save states',
            on: prefs.getBool(StateSyncService.enabledKey(id)) ?? false,
            onChanged: (on) async {
              await prefs.setBool(StateSyncService.enabledKey(id), on);
              if (mounted) setState(() {});
            },
          ),
    ]);
  }
}
