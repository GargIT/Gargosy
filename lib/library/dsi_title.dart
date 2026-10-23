import 'dart:io' as io;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// What a DS/DSi ROM's header says about the DSi (#114): whether it's
/// DSiWare (a download title, which melonDS DS installs into a NAND) and
/// the regions whose DSi runs it. DSiWare runs only on a NAND of one of
/// them; a cartridge game doesn't care.
class DsiTitle {
  const DsiTitle({required this.dsiWare, required this.regions});

  final bool dsiWare;

  /// Region names (`Japan`, `USA`, `Europe`, `Australia`, `China`, `Korea`)
  /// in that order; empty when the game runs on every region.
  final List<String> regions;
}

const _regionNames = ['Japan', 'USA', 'Europe', 'Australia', 'China', 'Korea'];

/// The header in [h] (at least its first 0x238 bytes), or null when it
/// isn't a DSi title (a plain DS game, or too short).
DsiTitle? parseDsiHeader(Uint8List h) {
  if (h.length < 0x238) return null;
  final data = ByteData.sublistView(h);
  // Unit code: 0 DS, 2 DS with DSi features, 3 DSi only.
  if (h[0x12] & 0x02 == 0) return null;
  final titleHigh = data.getUint32(0x234, Endian.little);
  final mask = data.getUint32(0x1B0, Endian.little);
  return DsiTitle(
    dsiWare: titleHigh == 0x00030004,
    regions: mask == 0xFFFFFFFF
        ? const []
        : [
            for (var i = 0; i < _regionNames.length; i++)
              if (mask & (1 << i) != 0) _regionNames[i],
          ],
  );
}

const _romExtensions = {'.nds', '.dsi', '.srl'};
const _headerBytes = 0x1000;

/// The DSi header of the game at [path]: a ROM file, a folder with one, or
/// a zip with one. Null when there's none or it can't be read.
Future<DsiTitle?> readDsiTitle(String path) => Isolate.run(() {
  try {
    final header = _headerOf(path);
    return header == null ? null : parseDsiHeader(header);
  } on Object {
    return null;
  }
});

Uint8List? _headerOf(String path) {
  if (io.Directory(path).existsSync()) {
    final rom = io.Directory(path)
        .listSync()
        .whereType<io.File>()
        .where((f) => _romExtensions.contains(p.extension(f.path).toLowerCase()))
        .firstOrNull;
    return rom == null ? null : _headerOf(rom.path);
  }
  final file = io.File(path);
  if (!file.existsSync()) return null;
  final ext = p.extension(path).toLowerCase();
  if (_romExtensions.contains(ext)) {
    final raf = file.openSync();
    try {
      return raf.readSync(_headerBytes);
    } finally {
      raf.closeSync();
    }
  }
  if (ext != '.zip') return null;
  final input = InputFileStream(path);
  try {
    for (final entry in ZipDecoder().decodeStream(input)) {
      if (!entry.isFile || !_romExtensions.contains(p.extension(entry.name).toLowerCase())) continue;
      final bytes = entry.readBytes();
      return bytes == null ? null : Uint8List.sublistView(bytes, 0, bytes.length.clamp(0, _headerBytes));
    }
    return null;
  } finally {
    input.closeSync();
  }
}

/// [regions] as a line: `Europe or Australia`.
String dsiRegionLine(List<String> regions) => switch (regions) {
  [] => 'any region',
  [final one] => one,
  _ => '${regions.sublist(0, regions.length - 1).join(', ')} or ${regions.last}',
};
