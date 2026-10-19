import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../../storage/profile_rooted.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';

/// Flycast's save states (#63). Its saves (the VMU) go through sigil, so
/// this strategy is registered for states only
/// (`SaveSyncService.stateStrategyForGame`).
///
/// Flycast names a state after the content file without its extension:
/// `<stem>.state` for slot 0 and `<stem>_<N>.state` for slots 1–99
/// (core/oslib/oslib.cpp, `getSavestatePath`); `.state.net` and `.state.tmp`
/// are its own scratch files. In a profile the folder is `<data>\states`
/// (`-config config:Dreamcast.SavestatePath`). A state starts with
/// `FLYSAVE1`, its creation time, the format version and the size of the PNG
/// screenshot that follows (core/nullDC.cpp, `SavestateHeader`); states from
/// before that header have none.
class FlycastSaveStrategy extends SaveStrategy with StateSyncCapable {
  FlycastSaveStrategy(this._directoryService);

  final DirectoryService _directoryService;

  @override
  String get strategyId => 'flycast';

  static const _magic = 'FLYSAVE1';
  static const _headerSize = 24;

  /// A file this big without the header is an older state.
  static const _legacyMinSize = 1024;
  static const _maxPng = 8 * 1024 * 1024;
  static final _slotSuffix = RegExp(r'(?:_(\d{1,2}))?\.state$');

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

  @override
  Future<String> stateDirectory(Game game, String romPath) async {
    if (_directoryService is! ProfileRootedDirectories) {
      throw StateError("Flycast's state folder is only known in a Gargosy profile");
    }
    return p.join(await _directoryService.getEmulatorAppSupportDirectory('flycast'), 'states');
  }

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    final stems = {
      p.basenameWithoutExtension(romPath).toLowerCase(),
      if (game.fsName case final fs?) p.basenameWithoutExtension(fs).toLowerCase(),
    }..removeWhere((s) => s.isEmpty);
    if (stems.isEmpty) return null;
    return (String fileName) {
      if (fileName != p.basename(fileName) || fileName.contains(r'\')) return false;
      final m = _slotSuffix.firstMatch(fileName);
      return m != null && stems.contains(fileName.substring(0, m.start).toLowerCase());
    };
  }

  /// The slot of a state [fileName]: 0 without a number.
  static int? slotNumber(String fileName) {
    final m = _slotSuffix.firstMatch(fileName);
    if (m == null) return null;
    return m.group(1) == null ? 0 : int.parse(m.group(1)!);
  }

  static bool _hasHeader(Uint8List bytes) =>
      bytes.length >= _headerSize && String.fromCharCodes(bytes.sublist(0, 8)) == _magic;

  @override
  bool looksLikeValidState(Uint8List bytes) => _hasHeader(bytes) || bytes.length >= _legacyMinSize;

  @override
  StateSlot slotOf(String fileName) {
    final n = slotNumber(fileName);
    return n == null ? UnknownStateSlot(fileName) : NumberedStateSlot(n);
  }

  @override
  Future<StateFileInfo> describeState(io.File file) async {
    final base = await super.describeState(file);
    String? format;
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      final head = await raf.read(_headerSize);
      if (_hasHeader(head)) format = ByteData.sublistView(head).getUint32(16, Endian.little).toString();
    } catch (e) {
      debugPrint('[Flycast] cannot read the state header of ${file.path}: $e');
    } finally {
      await raf?.close();
    }
    return StateFileInfo(savedAt: base.savedAt, formatId: format);
  }

  /// The PNG Flycast stores after the header.
  @override
  Future<Uint8List?> stateScreenshot(io.File file) async {
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      final head = await raf.read(_headerSize);
      if (!_hasHeader(head)) return null;
      final size = ByteData.sublistView(head).getUint32(20, Endian.little);
      if (size == 0 || size > _maxPng || _headerSize + size > await raf.length()) return null;
      final png = await raf.read(size);
      return png.length == size ? png : null;
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }
}
