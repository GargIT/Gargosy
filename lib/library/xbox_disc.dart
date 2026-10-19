import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

/// The XDVDFS volume descriptor's magic, at [xdvdfsDescriptor] into the
/// game partition (sigil's `src/xdvdfs.c`).
const xdvdfsMagic = 'MICROSOFT*XBOX*MEDIA';
const xdvdfsDescriptor = 0x10000;

/// Where the game partition starts on an original Xbox (XGD1) disc. A
/// Redump image is the whole disc, video partition first; an XISO, which
/// is what xemu reads (xemu.app/docs/disc-images), is the game partition
/// alone.
const xgd1GamePartition = 0x18300000;

enum XboxDisc { xiso, redump, unknown }

/// The image isn't an original Xbox disc in either form.
class NotAnXboxDisc implements Exception {
  const NotAnXboxDisc(this.name);
  final String name;

  @override
  String toString() => "$name isn't an Xbox disc image (no XDVDFS volume).";
}

bool _magicIn(Uint8List bytes, int at) {
  if (bytes.length < at + xdvdfsMagic.length) return false;
  for (var i = 0; i < xdvdfsMagic.length; i++) {
    if (bytes[at + i] != xdvdfsMagic.codeUnitAt(i)) return false;
  }
  return true;
}

bool _magicAt(io.RandomAccessFile f, int offset) {
  if (f.lengthSync() < offset + xdvdfsMagic.length) return false;
  f.setPositionSync(offset);
  return _magicIn(f.readSync(xdvdfsMagic.length), 0);
}

/// Which form the image at [path] is in.
XboxDisc detectXboxDisc(String path, {int gamePartition = xgd1GamePartition}) {
  final f = io.File(path).openSync();
  try {
    if (_magicAt(f, xdvdfsDescriptor)) return XboxDisc.xiso;
    if (_magicAt(f, gamePartition + xdvdfsDescriptor)) return XboxDisc.redump;
    return XboxDisc.unknown;
  } finally {
    f.closeSync();
  }
}

/// Writes an Xbox disc image streamed through [add] (from `tar -xO`) to
/// [out] as an XISO: an XISO as it is, a Redump image without its video
/// partition. Anything else throws [NotAnXboxDisc] as soon as that's
/// known. Nothing is buffered beyond the first 64 KiB of each partition.
class XisoWriter {
  XisoWriter(this._out, {required this.name, this.gamePartition = xgd1GamePartition});

  final io.RandomAccessFile _out;
  final String name;
  final int gamePartition;

  static const _probe = xdvdfsDescriptor + 20;
  final _buf = BytesBuilder(copy: false);
  var _phase = _Phase.head;
  int _pos = 0;
  int _written = 0;

  /// What the image turned out to be; null until it's known.
  XboxDisc? kind;

  /// Bytes written to [_out] so far.
  int get written => _written;

  void _write(List<int> bytes, [int start = 0, int? end]) {
    _out.writeFromSync(bytes, start, end);
    _written += (end ?? bytes.length) - start;
  }

  void add(List<int> chunk) {
    var i = 0;
    while (i < chunk.length) {
      switch (_phase) {
        case _Phase.head:
        case _Phase.probe:
          final take = math.min(_probe - _buf.length, chunk.length - i);
          _buf.add(chunk.sublist(i, i + take));
          i += take;
          _pos += take;
          if (_buf.length < _probe) break;
          final head = _buf.takeBytes();
          if (_magicIn(head, xdvdfsDescriptor)) {
            kind = _phase == _Phase.head ? XboxDisc.xiso : XboxDisc.redump;
            _write(head);
            _phase = _Phase.copy;
          } else if (_phase == _Phase.head) {
            _phase = _Phase.skip;
          } else {
            kind = XboxDisc.unknown;
            throw NotAnXboxDisc(name);
          }
        case _Phase.skip:
          final take = math.min(gamePartition - _pos, chunk.length - i);
          i += take;
          _pos += take;
          if (_pos == gamePartition) _phase = _Phase.probe;
        case _Phase.copy:
          _write(chunk, i);
          _pos += chunk.length - i;
          i = chunk.length;
      }
    }
  }

  /// The stream ended: throws [NotAnXboxDisc] when it never showed an
  /// XDVDFS volume.
  void close() {
    if (_phase != _Phase.copy) {
      kind = XboxDisc.unknown;
      throw NotAnXboxDisc(name);
    }
  }
}

enum _Phase { head, skip, probe, copy }

/// Writes the game partition of the Redump image [src] to [dst] (an XISO).
/// [onProgress] hears the bytes written and the total.
Future<void> redumpToXiso(
  String src,
  String dst, {
  int gamePartition = xgd1GamePartition,
  void Function(int done, int total)? onProgress,
}) async {
  final input = io.File(src).openSync();
  final output = io.File(dst).openSync(mode: io.FileMode.write);
  try {
    final total = input.lengthSync() - gamePartition;
    input.setPositionSync(gamePartition);
    final buffer = Uint8List(8 << 20);
    var done = 0;
    while (true) {
      final n = await input.readInto(buffer);
      if (n <= 0) break;
      await output.writeFrom(buffer, 0, n);
      done += n;
      onProgress?.call(done, total);
    }
  } finally {
    input.closeSync();
    output.closeSync();
  }
}
