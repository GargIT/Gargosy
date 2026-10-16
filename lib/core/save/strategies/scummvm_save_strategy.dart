import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// The folder of the game at [romPath] in ScummVM's saves (issue #11):
/// its name in `roms\scummvm\` (a zip's without `.zip`), so the launch and
/// the save code find the same folder whether they were given the game's
/// folder or a file in it.
String scummVmSaveFolderName(String romPath) {
  final parts = p.split(p.normalize(romPath));
  var name = parts.isEmpty ? '' : parts.last;
  for (var i = parts.length - 2; i >= 1; i--) {
    if (parts[i].toLowerCase() == 'scummvm' && parts[i - 1].toLowerCase() == 'roms') {
      name = parts[i + 1];
      break;
    }
  }
  if (name.toLowerCase().endsWith('.zip')) name = name.substring(0, name.length - 4);
  return name.isEmpty || name == '.' || name == '..' ? 'game' : name;
}

/// Save strategy for ScummVM (issue #11). Gargosy starts each game with its
/// own `--savepath`, `<data>\saves\<game>\` ([scummVmSaveFolderName]):
/// ScummVM names saves by engine (`SKY-VM.001`, `monkey1.003`), so one
/// shared folder couldn't tell the games apart. A game's saves are that
/// folder's files, uploaded as one zip.
class ScummVmSaveStrategy extends SaveStrategy {
  ScummVmSaveStrategy(this._directoryService);

  final DirectoryService _directoryService;

  /// ScummVM's own record of the folder's save times, made again by it.
  static const _notSaves = {'timestamps'};

  @override
  String get strategyId => 'scummvm';

  @override
  bool get supportsSaveSync => true;

  @override
  Future<String?> getSaveDir(Game game, String romPath) async =>
      p.join(await _directoryService.getEmulatorDirectory('scummvm'), 'saves', scummVmSaveFolderName(romPath));

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    if (syncMode == 'states') return [];
    final dir = io.Directory((await getSaveDir(game, romPath))!);
    if (!await dir.exists()) return [];
    final files = [
      for (final e in dir.listSync(followLinks: false))
        if (e is io.File && _isSave(p.basename(e.path))) e,
    ]..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    if (sessionStart != null) {
      final since = sessionStart.subtract(const Duration(seconds: 2));
      if (!files.any((f) => f.statSync().modified.isAfter(since))) return [];
    }
    return files;
  }

  static bool _isSave(String name) {
    final lower = name.toLowerCase();
    return !_notSaves.contains(lower) && !lower.startsWith('.') && !RegExp(r'\.bak\d*$').hasMatch(lower);
  }

  /// A zip's files, or one file, into the game's folder; only plain names,
  /// so nothing lands outside it.
  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final dir = (await getSaveDir(game, destPath))!;
      await io.Directory(dir).create(recursive: true);
      if (filename.toLowerCase().endsWith('.zip')) {
        for (final entry in ZipDecoder().decodeBytes(data)) {
          final name = p.basename(entry.name.replaceAll('\\', '/'));
          if (!entry.isFile || name == 'freegosy_sync.txt' || !_isSave(name)) continue;
          await io.File(p.join(dir, name)).writeAsBytes(entry.content as List<int>);
        }
        return true;
      }
      final name = p.basename(filename.replaceAll('\\', '/'));
      if (name.isEmpty || name == '.' || name == '..') return false;
      await io.File(p.join(dir, name)).writeAsBytes(data);
      return true;
    } catch (e) {
      debugPrint('[ScummVM] Restore error: $e');
      return false;
    }
  }
}
