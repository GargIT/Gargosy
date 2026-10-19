import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../../storage/profile_rooted.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';

/// MAME's save states (#62); MAME's saves (its `nvram`) aren't synced, so
/// this strategy is registered for states only
/// (`SaveSyncService.stateStrategyForGame`) and the save pipeline never sees
/// it.
///
/// MAME keeps a game's states in `<state_directory>\<driver>\<name>.sta`
/// (src/emu/machine.cpp, `compose_saveload_filename`): the driver is the ROM
/// set's name, `<name>` the key pressed at "Save State" (`1`, `a`) or `auto`
/// with `-autosave`. In a profile the state directory is `<data>\sta`
/// (`-state_directory`). A state starts `MAMESAVE`, then the format version
/// (2) (src/emu/save.cpp); it records no build.
class MameSaveStrategy extends SaveStrategy with StateSyncCapable {
  MameSaveStrategy(this._directoryService);

  final DirectoryService _directoryService;

  @override
  String get strategyId => 'mame';

  static const _magic = 'MAMESAVE';
  static const _version = 2;
  static final _name = RegExp(r'^([A-Za-z0-9_-]{1,32})\.sta$');

  /// The driver MAME runs: the ROM set's name (as the launch passes it).
  static String _driver(String romPath) => p.basenameWithoutExtension(romPath);

  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;

  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async => const [];

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => false;

  /// Only in a profile, where Gargosy sets MAME's state directory.
  @override
  Future<String> stateDirectory(Game game, String romPath) async {
    if (_directoryService is! ProfileRootedDirectories) {
      throw StateError("MAME's state folder is only known in a Gargosy profile");
    }
    final data = await _directoryService.getEmulatorAppSupportDirectory('mame');
    return p.join(data, 'sta', _driver(romPath));
  }

  /// The folder is the driver's own, so every state in it is the game's.
  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    if (_driver(romPath).isEmpty) return null;
    return (String fileName) => _name.hasMatch(fileName);
  }

  @override
  bool looksLikeValidState(Uint8List bytes) =>
      bytes.length > 9 && String.fromCharCodes(bytes.sublist(0, 8)) == _magic && bytes[8] == _version;

  @override
  StateSlot slotOf(String fileName) {
    final name = _name.firstMatch(fileName)?.group(1);
    if (name == 'auto') return const AutoStateSlot();
    final number = int.tryParse(name ?? '');
    return number != null && number >= 0 && number <= 9 ? NumberedStateSlot(number) : UnknownStateSlot(fileName);
  }
}
