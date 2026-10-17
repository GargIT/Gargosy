import 'dart:io' as io;

import 'package:flutter/foundation.dart';

/// What a Dolphin state (`<GameID>.s01`–`.s10`) records about itself (#60),
/// from Source/Core/Core/State.h: a 24-byte legacy header (`game_id[6]`,
/// 2 reserved, `lzo_size` u32, 4 reserved, `time` double), then, when
/// `lzo_size` is 0 (every state since Dolphin 5.0-16xxx), a version header
/// (`version_cookie` = 0xBAADBABE + the state version, the string's length)
/// and the build that wrote it (`Common::GetScmRevStr()`: `Dolphin 2609a`).
class DolphinStateFile {
  DolphinStateFile._();

  static const _legacySize = 24;
  static const _versionAt = 32;
  static const _cookieBase = 0xBAADBABE;

  /// No real state version comes near this; the build string is short.
  static const _maxStateVersion = 100000;
  static const _maxVersionLength = 256;

  /// Bytes enough for the headers and any build string.
  static const headLength = _versionAt + _maxVersionLength;

  static bool _gameIdOk(Uint8List head) {
    for (var i = 0; i < 6; i++) {
      final c = head[i];
      final ok = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
      if (!ok) return false;
    }
    return true;
  }

  /// Whether [head] starts like a Dolphin state.
  static bool looksValid(Uint8List head) {
    if (head.length < _legacySize || !_gameIdOk(head)) return false;
    final fields = ByteData.sublistView(head);
    if (fields.getUint32(8, Endian.little) != 0) return true; // an old LZO state: no version header
    if (head.length < _versionAt) return false;
    final cookie = fields.getUint32(24, Endian.little);
    return cookie >= _cookieBase && cookie - _cookieBase < _maxStateVersion;
  }

  /// The build that wrote the state in [head] (`Dolphin 2609a`), or null for
  /// an old state, a missing or garbled string, or bytes that aren't a state.
  static String? parseVersion(Uint8List head) {
    if (!looksValid(head) || head.length < _versionAt) return null;
    final fields = ByteData.sublistView(head);
    if (fields.getUint32(8, Endian.little) != 0) return null;
    final length = fields.getUint32(28, Endian.little);
    if (length == 0 || length > _maxVersionLength || _versionAt + length > head.length) return null;
    final bytes = head.sublist(_versionAt, _versionAt + length);
    if (bytes.any((c) => c < 0x20 || c > 0x7E)) return null;
    final version = String.fromCharCodes(bytes).trim();
    return version.isEmpty ? null : version;
  }

  /// [parseVersion] on the start of [file]; null on any failure.
  static Future<String?> readVersion(io.File file) async {
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      return parseVersion(await raf.read(headLength));
    } catch (e) {
      debugPrint('[Dolphin] cannot read the state header of ${file.path}: $e');
      return null;
    } finally {
      await raf?.close();
    }
  }
}
