// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import '../formats/zstd.dart';
import '../rgba_png.dart';

export '../formats/zstd.dart' show ZstdDecompressor;

/// Reads what a DuckStation `.sav` state records about itself.
///
/// The file starts with a plain header: the magic `DUCC`, a u32 (little
/// endian) state format version, then title, serial, disc path and the
/// offsets of the (compressed) screenshot and state data. It does not record
/// the DuckStation build that wrote it, so the format version is all there is
/// to show.
class DuckstationStateFile {
  DuckstationStateFile._();

  static const _magic = [0x44, 0x55, 0x43, 0x43]; // "DUCC"

  /// Header bytes up to and including the screenshot fields.
  static const _screenshotHeaderEnd = 0xC8;

  /// Screenshot compression types in the header.
  static const _uncompressed = 0;
  static const _zstd = 2;

  /// Bounds that no real screenshot comes near (DuckStation writes 256×192
  /// at ~50 KB): anything larger is a corrupt header, not worth reading.
  static const _maxDimension = 4096;
  static const _maxStoredBytes = 16 * 1024 * 1024;

  /// Whether [head] starts with DuckStation's state magic.
  static bool hasMagic(Uint8List head) {
    if (head.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (head[i] != _magic[i]) return false;
    }
    return true;
  }

  /// The state format version from [head], or null if [head] isn't a
  /// DuckStation state header.
  static int? parseFormatVersion(Uint8List head) {
    if (head.length < 8 || !hasMagic(head)) return null;
    final version = ByteData.sublistView(head).getUint32(4, Endian.little);
    return version == 0 ? null : version;
  }

  /// [parseFormatVersion] on the start of [file]; null on any failure.
  static Future<int?> readFormatVersion(io.File file) async {
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      return parseFormatVersion(await raf.read(8));
    } catch (e) {
      debugPrint('[DuckStation] cannot read state format of ${file.path}: $e');
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// The state's screenshot as a PNG, or null when it has none, it can't be
  /// read, or the header is implausible. DuckStation stores raw RGBA pixels,
  /// zstd-compressed by default; [zstd] decompresses them (the zstandard
  /// plugin unless a test passes a fake). Never throws.
  static Future<Uint8List?> readScreenshot(io.File file, {ZstdDecompressor? zstd}) async {
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      final head = await raf.read(_screenshotHeaderEnd);
      if (head.length < _screenshotHeaderEnd || !hasMagic(head)) return null;
      final fields = ByteData.sublistView(head);
      final compression = fields.getUint32(0xB4, Endian.little);
      final width = fields.getUint32(0xB8, Endian.little);
      final height = fields.getUint32(0xBC, Endian.little);
      final size = fields.getUint32(0xC0, Endian.little);
      final offset = fields.getUint32(0xC4, Endian.little);
      if (compression != _uncompressed && compression != _zstd) return null;
      if (width == 0 || height == 0 || width > _maxDimension || height > _maxDimension) return null;
      if (size == 0 || size > _maxStoredBytes || offset < _screenshotHeaderEnd) return null;
      if (offset + size > await raf.length()) return null;

      await raf.setPosition(offset);
      final stored = await raf.read(size);
      if (stored.length != size) return null;
      final pixels = compression == _zstd
          ? await (zstd ?? zstandardDecompress)(stored)
          : stored;
      if (pixels == null || pixels.length != width * height * 4) return null;
      return await Isolate.run(() => encodeRgbaPng(width, height, pixels));
    } catch (e) {
      debugPrint('[DuckStation] cannot read screenshot of ${file.path}: $e');
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// Gargosy: header fields of format 69 and later (DuckStation's
  /// `SAVE_STATE_HEADER`): the disc path's length and offset, and the
  /// offsets of the screenshot and the state data, which follow the path.
  static const _pathLength = 0xA8;
  static const _pathOffset = 0xAC;
  static const _screenshotOffset = 0xC4;
  static const _dataOffset = 0xD4;
  static const _headerEnd = 0xD8;
  static const _firstFormatWithThisHeader = 69;

  /// [state] with its disc path set to [mediaPath], or null when it already
  /// is, the state has no disc, or it isn't a state this can rewrite. Only
  /// the path, its length and the offsets after it change; the screenshot and
  /// state data are copied as they are.
  static Uint8List? withMediaPath(Uint8List state, String mediaPath) {
    final version = parseFormatVersion(state);
    if (version == null || version < _firstFormatWithThisHeader || state.length < _headerEnd) return null;
    final fields = ByteData.sublistView(state);
    final length = fields.getUint32(_pathLength, Endian.little);
    final offset = fields.getUint32(_pathOffset, Endian.little);
    if (length == 0 || offset < _headerEnd || offset + length > state.length) return null;
    final path = utf8.encode(mediaPath);
    if (listEquals(Uint8List.sublistView(state, offset, offset + length), path)) return null;
    final delta = path.length - length;
    final out = Uint8List(state.length + delta)
      ..setRange(0, offset, state)
      ..setRange(offset, offset + path.length, path);
    out.setRange(offset + path.length, out.length, state, offset + length);
    final rewritten = ByteData.sublistView(out)..setUint32(_pathLength, path.length, Endian.little);
    for (final at in [_screenshotOffset, _dataOffset]) {
      final value = fields.getUint32(at, Endian.little);
      if (value >= offset + length) rewritten.setUint32(at, value + delta, Endian.little);
    }
    return out;
  }
}
