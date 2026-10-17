import 'dart:io' as io;

import 'package:flutter/foundation.dart';

/// What a PPSSPP `.ppst` state records about itself (#59), from PPSSPP's
/// `CChunkFileReader::SChunkHeader` (Common/Serialize/Serializer.h): four
/// little-endian int32s (`Revision`, `Compress`, `ExpectedSize`,
/// `UncompressedSize`) and `GitVersion[32]`, the build that wrote it
/// (`v1.20.4`). There is no magic; the revision (4 or more, 5 today) and a
/// known compression are the check.
class PpssppStateFile {
  PpssppStateFile._();

  /// Bytes up to and including `GitVersion`.
  static const headerSize = 48;

  /// PPSSPP refuses revisions below 4 (`REVISION_MIN`); a revision far above
  /// today's 5 is a file that isn't a state.
  static const _revisionMin = 4;
  static const _revisionMax = 64;

  /// `SerializeCompressType`: none, snappy, zstd.
  static const _compressMax = 2;

  /// Whether [head] starts like a PPSSPP state.
  static bool looksValid(Uint8List head) {
    if (head.length < headerSize) return false;
    final fields = ByteData.sublistView(head);
    final revision = fields.getInt32(0, Endian.little);
    final compress = fields.getInt32(4, Endian.little);
    return revision >= _revisionMin && revision <= _revisionMax && compress >= 0 && compress <= _compressMax;
  }

  /// The PPSSPP build that wrote the state in [head] (`v1.20.4`), or null
  /// when [head] isn't a state or names none.
  static String? parseVersion(Uint8List head) {
    if (!looksValid(head)) return null;
    final chars = <int>[];
    for (var i = 16; i < headerSize; i++) {
      final c = head[i];
      if (c == 0) break;
      if (c < 0x20 || c > 0x7E) return null;
      chars.add(c);
    }
    final version = String.fromCharCodes(chars).trim();
    return version.isEmpty ? null : version;
  }

  /// [parseVersion] on the start of [file]; null on any failure.
  static Future<String?> readVersion(io.File file) async {
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      return parseVersion(await raf.read(headerSize));
    } catch (e) {
      debugPrint('[PPSSPP] cannot read the state header of ${file.path}: $e');
      return null;
    } finally {
      await raf?.close();
    }
  }
}
