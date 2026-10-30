import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'platform_info.dart';

/// #223: a shortcut on the player's desktop that starts a game through
/// Gargosy (`--play`). The one write Gargosy's Dart code makes outside the
/// Gargosy folder (CLAUDE.md names it): a new link file in [desktopDir],
/// never replacing one there.
abstract class ShortcutMaker {
  /// The player's desktop folder, or null when there is none.
  Future<String?> desktopDir();

  /// Makes the link [linkPath] to [target] with [args], started in
  /// [workingDir], with [iconPath]'s icon when given. Throws when it can't.
  Future<void> make({
    required String linkPath,
    required String target,
    required List<String> args,
    required String workingDir,
    String? iconPath,
    String description = '',
  });

  /// A link's file extension, with its dot.
  String get extension;
}

/// The [ShortcutMaker] of [platform]'s OS.
ShortcutMaker shortcutMakerFor(PlatformInfo platform) {
  if (platform.isWindows) return WindowsShortcutMaker(platform);
  throw UnsupportedError('No desktop shortcuts on ${platform.os} yet');
}

final shortcutMakerProvider = Provider<ShortcutMaker>((ref) => shortcutMakerFor(PlatformInfo.current));

/// Windows: a `.lnk` made by the shell's own `WScript.Shell`, through
/// Windows PowerShell by its path. The values go in as environment
/// variables, so no name needs quoting.
class WindowsShortcutMaker implements ShortcutMaker {
  WindowsShortcutMaker(PlatformInfo platform)
    : _powershell = p.join(
        platform.environment['SystemRoot'] ?? r'C:\Windows',
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      );

  final String _powershell;

  @override
  String get extension => '.lnk';

  Future<io.ProcessResult> _run(String script, [Map<String, String> env = const {}]) => io.Process.run(
    _powershell,
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      // UTF-8 both ways: a desktop under C:\Users\Göran comes back whole.
      '[Console]::OutputEncoding = [Text.Encoding]::UTF8\n$script',
    ],
    environment: env,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  @override
  Future<String?> desktopDir() async {
    final r = await _run("[Environment]::GetFolderPath('Desktop')");
    final dir = '${r.stdout}'.trim();
    return r.exitCode == 0 && dir.isNotEmpty ? dir : null;
  }

  @override
  Future<void> make({
    required String linkPath,
    required String target,
    required List<String> args,
    required String workingDir,
    String? iconPath,
    String description = '',
  }) async {
    const script = r'''
$ErrorActionPreference = 'Stop'
# Never over a file that came meanwhile.
if (Test-Path -LiteralPath $env:GARGOSY_LNK) { [Console]::Error.WriteLine('The name is taken'); exit 3 }
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:GARGOSY_LNK)
$s.TargetPath = $env:GARGOSY_TARGET
$s.Arguments = $env:GARGOSY_ARGS
$s.WorkingDirectory = $env:GARGOSY_DIR
if ($env:GARGOSY_ICON) { $s.IconLocation = $env:GARGOSY_ICON + ',0' }
$s.Description = $env:GARGOSY_DESC
$s.Save()
''';
    final r = await _run(script, {
      'GARGOSY_LNK': linkPath,
      'GARGOSY_TARGET': target,
      'GARGOSY_ARGS': args.join(' '),
      'GARGOSY_DIR': workingDir,
      'GARGOSY_ICON': iconPath ?? '',
      'GARGOSY_DESC': description,
    });
    debugPrint('[Shortcut] $linkPath: powershell ${r.exitCode} ${'${r.stderr}'.trim()}');
    if (r.exitCode != 0 || !io.File(linkPath).existsSync()) {
      throw io.FileSystemException('${r.stderr}'.trim(), linkPath);
    }
  }
}
