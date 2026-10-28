import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../emulators/bios_sync.dart';
import '../../../emulators/emulator_installer.dart';
import '../../../emulators/emulator_library.dart';
import '../../../emulators/ps3_firmware.dart';
import '../../../play/play_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/toast.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// Settings → Emulators: the emulators Gargosy owns (spec §6). Import an
/// existing install from a folder, download one, update or remove it, and
/// get the BIOS files from RomM (and install RPCS3's firmware from bios\).
class EmulatorInstallSection extends ConsumerStatefulWidget {
  const EmulatorInstallSection({super.key});

  @override
  ConsumerState<EmulatorInstallSection> createState() => _EmulatorInstallSectionState();
}

class _EmulatorInstallSectionState extends ConsumerState<EmulatorInstallSection> {
  /// Emulator id → what is happening to it right now ("Downloading 40 %").
  final Map<String, String> _busy = {};
  bool _gettingBios = false;
  bool _installingFirmware = false;

  /// RPCS3's firmware from bios\, installed once for every profile (issue #10).
  Future<void> _installPs3Firmware(String exe) async {
    final firmware = ref.read(ps3FirmwareProvider);
    if (firmware == null || _installingFirmware) return;
    // One emulator at a time: RPCS3 can't install while a game runs.
    if (ref.read(playControllerProvider).runningGameId != null) {
      showToast(context, tr('A game is running. Close it first.'));
      return;
    }
    setState(() => _installingFirmware = true);
    try {
      await firmware.install(exe);
      if (mounted) showToast(context, tr('The PS3 firmware is installed, for every profile.'));
    } on Ps3FirmwareException catch (e) {
      if (mounted) showToast(context, e.message);
    } on Object catch (e) {
      if (mounted) showToast(context, tr('Couldn\'t install the PS3 firmware: {0}', [e]));
    } finally {
      if (mounted) setState(() => _installingFirmware = false);
    }
  }

  /// Opens [e] on its own, with this profile's settings, for its menus
  /// (controllers): Dolphin started from a game has none.
  Future<void> _open(EmulatorInfo e) async {
    final exe = e.installedExe;
    if (exe == null) return;
    final refused = await ref.read(playControllerProvider.notifier).openEmulator(e.id, e.name, exe);
    if (!mounted) return;
    showToast(
      context,
      refused ??
          tr(
            '{0} is open with this profile\'s settings. Set it up there and close it when you\'re done. A game started from it doesn\'t sync its saves: start games from Gargosy.',
            [e.name],
          ),
    );
  }

  Future<void> _import(EmulatorInfo e) async {
    final lib = ref.read(emulatorLibraryProvider);
    if (lib == null) return;
    final folder = await FilePicker.getDirectoryPath(dialogTitle: tr('The folder {0} is installed in', [e.name]));
    if (folder == null || !mounted) return;
    setState(() => _busy[e.id] = tr('Importing…'));
    try {
      await lib.importFrom(e.id, folder);
      if (mounted) showToast(context, tr('{0} is installed.', [e.name]));
    } on Object catch (err) {
      if (mounted) showToast(context, tr('Couldn\'t import {0}: {1}', [e.name, err]));
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
      ref.invalidate(emulatorsProvider);
    }
  }

  /// Download, or Update: the newest build, unless it's the one installed.
  Future<void> _download(EmulatorInfo e) async {
    final installer = ref.read(emulatorInstallerProvider);
    if (installer == null) return;
    setState(() => _busy[e.id] = tr('Looking for the newest…'));
    String? error;
    var installed = false;
    try {
      final url = await installer.latestUrl(e.id);
      if (!mounted) return;
      if (url == null) {
        error = tr('no download was found');
      } else if (url == e.installedFrom) {
        showToast(context, tr('{0} is already the newest.', [e.name]));
      } else {
        await ref.read(emulatorLibraryProvider)?.clearIfNoProgram(e.id);
        await for (final pr in installer.install(e.id, url)) {
          if (!mounted) return;
          if (pr.error != null) error = pr.error;
          if (pr.status == 'done' && pr.error == null) installed = true;
          setState(
            () => _busy[e.id] = pr.status.startsWith(tr('Extracting'))
                ? tr('Unpacking…')
                : tr('Downloading {0} %', [(pr.percent * 100).round()]),
          );
        }
      }
    } on Object catch (err) {
      error = '$err';
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
      ref.invalidate(emulatorsProvider);
    }
    if (!mounted) return;
    if (error != null) {
      showToast(context, tr('Couldn\'t download {0}: {1}', [e.name, error]));
      return;
    }
    if (!installed) return;
    showToast(context, tr('{0} is installed.', [e.name]));
    // Its BIOS files from RomM, into the shared bios folder.
    final bios = ref.read(biosSyncProvider);
    if (bios == null) return;
    setState(() => _busy[e.id] = tr('Getting BIOS files…'));
    try {
      final n = await bios.forEmulator(e.id);
      if (mounted && n > 0) {
        showToast(context, n == 1 ? tr('Got 1 BIOS file from RomM.') : tr('Got {0} BIOS files from RomM.', [n]));
      }
    } on Object {
      // RomM may have none, or be out of reach: the emulator is installed anyway.
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
    }
  }

  Future<void> _remove(EmulatorInfo e) async {
    final ok = await showConfirm(
      context,
      title: tr('Remove {0}?', [e.name]),
      body: tr('The emulator\'s program is removed. Every profile\'s saves and settings for it stay.'),
      yes: tr('Remove'),
      no: tr('Keep'),
      focusYes: false,
      danger: true,
    );
    if (!ok) return;
    await ref.read(emulatorLibraryProvider)?.remove(e.id);
    ref.invalidate(emulatorsProvider);
  }

  Future<void> _getBios(Set<String> installed) async {
    final bios = ref.read(biosSyncProvider);
    if (bios == null || _gettingBios) return;
    setState(() => _gettingBios = true);
    try {
      final n = await bios.forAll(installed);
      if (!mounted) return;
      showToast(context, switch (n) {
        0 => tr('No new BIOS files on RomM.'),
        1 => tr('Got 1 BIOS file from RomM.'),
        _ => tr('Got {0} BIOS files from RomM.', [n]),
      });
    } on Object {
      if (mounted) showToast(context, tr('Couldn\'t get BIOS files from RomM.'));
    } finally {
      if (mounted) setState(() => _gettingBios = false);
    }
  }

  Widget _row(EmulatorInfo e) {
    final busy = _busy[e.id];
    final installed = e.installedExe != null;
    final state = !e.supported
        ? tr('Not supported yet')
        : (!installed
              ? e.downloadOff ?? tr('Not installed')
              : (e.version == null ? tr('Installed') : tr('Installed · {0}', [e.version])));
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.name,
                style: TextStyle(
                  fontSize: GFont.lg,
                  fontWeight: FontWeight.w700,
                  color: e.supported ? GColors.fg : GColors.fgMuted,
                ),
              ),
              Text(
                e.exe,
                style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
              ),
            ],
          ),
        ),
        Text(
          busy ?? state,
          style: TextStyle(fontSize: GFont.md, color: installed && e.supported ? GColors.success : GColors.fgSecondary),
        ),
        if (busy == null && e.supported) ...[
          const SizedBox(width: GSpace.s4),
          if (installed) ...[
            SettingsButton(label: tr('Open'), icon: Icons.open_in_new, onActivate: () => _open(e)),
            const SizedBox(width: GSpace.s2),
          ],
          SettingsButton(
            label: tr('Import from folder'),
            icon: Icons.folder_open_outlined,
            onActivate: () => _import(e),
          ),
          if (e.downloadOff == null) ...[
            const SizedBox(width: GSpace.s2),
            SettingsButton(
              label: installed ? tr('Update') : tr('Download'),
              icon: installed ? Icons.update : Icons.download_outlined,
              kind: installed ? SettingsButtonKind.tonal : SettingsButtonKind.primary,
              onActivate: () => _download(e),
            ),
          ],
          if (installed) ...[
            const SizedBox(width: GSpace.s2),
            SettingsButton(label: tr('Remove'), icon: Icons.delete_outline, onActivate: () => _remove(e)),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final emulators = ref.watch(emulatorsProvider);
    return emulators.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        final supported = [
          for (final e in list)
            if (e.supported) e,
        ];
        final notYet = [
          for (final e in list)
            if (!e.supported) e,
        ];
        final installed = {
          for (final e in supported)
            if (e.installedExe != null) e.id,
        };
        final rpcs3Exe = supported.where((e) => e.id == 'rpcs3').firstOrNull?.installedExe;
        final ps3Firmware = ref.watch(ps3FirmwareProvider);
        return ListView(
          children: [
            SettingsCard(
              title: tr('Emulators'),
              icon: Icons.videogame_asset,
              note: tr(
                'Gargosy keeps its own copy of each emulator, in the Gargosy folder. Every profile gets its own saves and settings for it.',
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: GSpace.s2,
                    runSpacing: GSpace.s2,
                    children: [
                      SettingsButton(
                        label: _gettingBios ? tr('Getting BIOS files…') : tr('Get BIOS files from RomM'),
                        icon: Icons.memory,
                        onActivate: _gettingBios ? null : () => _getBios(installed),
                      ),
                      if (rpcs3Exe != null && ps3Firmware != null)
                        SettingsButton(
                          key: const Key('ps3-firmware'),
                          label: _installingFirmware
                              ? tr('Installing the PS3 firmware…')
                              : tr('Install PS3 firmware from bios\\ ({0})', [
                                  ps3Firmware.installed ? 'installed' : 'not installed',
                                ]),
                          icon: Icons.system_update_alt,
                          onActivate: _installingFirmware ? null : () => _installPs3Firmware(rpcs3Exe),
                        ),
                    ],
                  ),
                ),
                for (final e in supported) _row(e),
              ],
            ),
            if (notYet.isNotEmpty)
              SettingsCard(
                title: tr('Not supported yet'),
                icon: Icons.hourglass_empty,
                note: tr('Gargosy can\'t point these at a profile\'s own folder yet, so it doesn\'t run them.'),
                children: [for (final e in notYet) _row(e)],
              ),
          ],
        );
      },
    );
  }
}
