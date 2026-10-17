import 'package:flutter/foundation.dart';

/// What an mGBA state (`<rom stem>.ss<N>`) is (#61), from src/core/serialize.c:
/// with screenshots on (mGBA's default) a PNG, its own screenshot, with the
/// state in a `gbAs` chunk; else the raw state, which starts with the core's
/// `versionMagic` (GBA 0x01000000 + version, GB 0x00400000 + version, both
/// little-endian). mGBA records no build, so there is no version to show.
class MgbaStateFile {
  MgbaStateFile._();

  static const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  static const _gbaMagic = 0x01000000;
  static const _gbMagic = 0x00400000;

  /// Whether [bytes] start with the PNG signature (a state with its screenshot).
  static bool isPng(Uint8List bytes) {
    if (bytes.length < _png.length) return false;
    for (var i = 0; i < _png.length; i++) {
      if (bytes[i] != _png[i]) return false;
    }
    return true;
  }

  /// Whether [bytes] look like an mGBA state: a PNG, or a raw GBA or GB state.
  static bool looksValid(Uint8List bytes) {
    if (isPng(bytes)) return true;
    if (bytes.length < 4) return false;
    final magic = ByteData.sublistView(bytes).getUint32(0, Endian.little);
    return (magic & 0xFFFF0000) == _gbaMagic || (magic & 0xFFFF0000) == _gbMagic;
  }
}
