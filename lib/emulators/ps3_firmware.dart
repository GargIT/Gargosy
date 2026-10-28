import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../profiles/app_root.dart';
import '../profiles/profile_providers.dart';
import '../providers/engine_providers.dart';
import 'bios_links.dart' show BiosFiles;
import 'close_process.dart';
import 'profile_directories.dart';
import 'rpcs3_config.dart';
import '../l10n/tr.dart';

/// Why the PS3 firmware couldn't be installed; the UI shows [message].
class Ps3FirmwareException implements Exception {
  const Ps3FirmwareException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Presses Yes in RPCS3's "Install firmware?" box of process [pid]; true
/// when it did. Tests pass their own.
typedef FirmwareConfirm = Future<bool> Function(int pid);

/// The PS3 firmware for RPCS3 (issue #10): RomM's `PS3UPDAT.PUP` in `bios\`,
/// installed once with `rpcs3.exe --installfw` into the shared
/// `emulators\rpcs3-firmware\dev_flash\` every profile reads (see
/// [Rpcs3Config]). RPCS3 can't install without its window (`--no-gui`
/// refuses), asks "Install firmware?" first and stays open after: Gargosy
/// presses Yes for the player (a controller can't reach that box), waits
/// until the files stop changing, and closes RPCS3. Probed on 0.0.43.
class Ps3Firmware {
  Ps3Firmware(
    this.root,
    this.dirs, {
    FirmwareConfirm? confirm,
    Future<void> Function(io.Process process)? close,
    this.poll = const Duration(seconds: 1),
    this.timeout = const Duration(minutes: 10),
  }) : confirm = confirm ?? confirmWithUiAutomation,
       close = close ?? closeProcess;

  final AppRoot root;
  final ProfileLaunchDirectories dirs;
  final FirmwareConfirm confirm;

  /// Closes RPCS3 once the firmware is in ([closeProcess]; tests pass their own).
  final Future<void> Function(io.Process process) close;
  final Duration poll;
  final Duration timeout;

  static const pupName = 'PS3UPDAT.PUP';

  /// The firmware file in `bios\` (`bios\ps3` first), or null.
  io.File? get pup => BiosFiles(root.bios).find(const [pupName], platforms: const ['ps3']);

  String get _flash => Rpcs3Config.sharedFlashIn(root);

  /// Whether a firmware is installed in the shared dev_flash (its VSH).
  bool get installed => io.File(p.join(_flash, 'vsh', 'module', 'vsh.self')).existsSync();

  static List<String> commandLine(String pup) => ['--installfw', pup];

  int _size() {
    final d = io.Directory(_flash);
    if (!d.existsSync()) return 0;
    var n = 0;
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is io.File) n += e.lengthSync();
    }
    return n;
  }

  /// Installs [pup] with RPCS3 at [exePath].
  Future<void> install(String exePath) async {
    final file = pup;
    if (file == null) {
      throw Ps3FirmwareException(
        tr(
          'There is no {0} in bios\\. Get BIOS files from RomM first (RomM keeps the PS3 firmware with the platform\'s firmware).',
          [pupName],
        ),
      );
    }
    final run = await dirs.startWithProfile('rpcs3', exePath, commandLine(file.path));
    var exited = false;
    run.process.exitCode.then((_) => exited = true);
    try {
      if (!await confirm(run.process.pid) && !exited) {
        throw Ps3FirmwareException(tr('RPCS3 didn\'t ask to install the firmware; nothing was installed.'));
      }
      // Done when the VSH is there and the folder stops growing.
      final until = DateTime.now().add(timeout);
      var last = -1;
      var still = 0;
      while (!exited && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(poll);
        final size = _size();
        still = installed && size == last ? still + 1 : 0;
        last = size;
        if (still >= 5) break;
      }
    } finally {
      if (!exited) await close(run.process);
      await run.finish();
    }
    if (!installed) throw Ps3FirmwareException(tr('RPCS3 couldn\'t install the firmware.'));
  }
}

/// [FirmwareConfirm] on Windows: Windows PowerShell's UI Automation finds
/// RPCS3's "RPCS3 Firmware Installer" box of [pid] (waiting up to a minute
/// for it) and invokes its Yes button.
Future<bool> confirmWithUiAutomation(int pid) async {
  const script = r'''
param([int]$ProcessId)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [Windows.Automation.AutomationElement]::RootElement
$byPid = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessId)
$yes = New-Object Windows.Automation.AndCondition(
  (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)),
  (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, 'Yes')))
for ($i = 0; $i -lt 60; $i++) {
  foreach ($w in $root.FindAll([Windows.Automation.TreeScope]::Children, $byPid)) {
    if ($w.Current.Name -eq 'RPCS3 Firmware Installer') {
      $b = $w.FindFirst([Windows.Automation.TreeScope]::Descendants, $yes)
      if ($b) { $b.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); exit 0 }
    }
  }
  Start-Sleep -Seconds 1
}
exit 1
''';
  final dir = await io.Directory.systemTemp.createTemp('gargosy-rpcs3-');
  try {
    final ps1 = io.File(p.join(dir.path, 'confirm.ps1'))..writeAsStringSync(script);
    final r = await io.Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      ps1.path,
      '-ProcessId',
      '$pid',
    ]);
    return r.exitCode == 0;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

final ps3FirmwareProvider = Provider<Ps3Firmware?>((ref) {
  final dirs = ref.watch(launchDirectoriesProvider);
  return dirs == null ? null : Ps3Firmware(ref.watch(appRootProvider), dirs);
});
