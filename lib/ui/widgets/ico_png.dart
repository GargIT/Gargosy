import 'dart:typed_data';

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// The largest PNG picture inside an .ico file, or null when there is none
/// (only old-style bitmaps, or not an .ico). RomM has some platform icons
/// only as .ico (C64, VIC-20, DOS, …), each a 256 × 256 PNG.
Uint8List? pngFromIco(Uint8List ico) {
  if (ico.length < 6) return null;
  final data = ByteData.sublistView(ico);
  if (data.getUint16(0, Endian.little) != 0 || data.getUint16(2, Endian.little) != 1) return null;
  final count = data.getUint16(4, Endian.little);
  Uint8List? best;
  var bestSize = -1;
  for (var i = 0; i < count; i++) {
    final dir = 6 + 16 * i;
    if (dir + 16 > ico.length) break;
    final width = data.getUint8(dir) == 0 ? 256 : data.getUint8(dir);
    final length = data.getUint32(dir + 8, Endian.little);
    final offset = data.getUint32(dir + 12, Endian.little);
    if (offset + length > ico.length || length < _pngSignature.length) continue;
    final isPng = [for (var k = 0; k < _pngSignature.length; k++) ico[offset + k] == _pngSignature[k]].every((b) => b);
    if (isPng && width > bestSize) {
      bestSize = width;
      best = Uint8List.sublistView(ico, offset, offset + length);
    }
  }
  return best;
}
