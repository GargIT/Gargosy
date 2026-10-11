import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/xbox_disc.dart';
import 'package:path/path.dart' as p;

/// A small stand-in for the 387 MB video partition.
const gp = 0x30000;

/// An XISO: the XDVDFS magic at 0x10000, then [tail] bytes of game data.
Uint8List xiso({int tail = 5000}) {
  final b = Uint8List(xdvdfsDescriptor + 20 + tail);
  b.setAll(xdvdfsDescriptor, xdvdfsMagic.codeUnits);
  for (var i = xdvdfsDescriptor + 20; i < b.length; i++) {
    b[i] = i % 251;
  }
  return b;
}

/// A Redump image: a video partition of [gp] bytes, then the XISO.
Uint8List redump(Uint8List game) => Uint8List(gp + game.length)..setAll(gp, game);

void main() {
  late io.Directory dir;
  setUp(() => dir = io.Directory.systemTemp.createTempSync('gargosy_xiso'));
  tearDown(() => dir.deleteSync(recursive: true));

  String file(String name, List<int> bytes) => (io.File(p.join(dir.path, name))..writeAsBytesSync(bytes)).path;

  Uint8List stream(Uint8List image, int chunk) {
    final out = io.File(p.join(dir.path, 'out-$chunk.iso')).openSync(mode: io.FileMode.write);
    final w = XisoWriter(out, name: 'Game', gamePartition: gp);
    try {
      for (var i = 0; i < image.length; i += chunk) {
        w.add(image.sublist(i, i + chunk > image.length ? image.length : i + chunk));
      }
      w.close();
    } finally {
      out.closeSync();
    }
    return io.File(p.join(dir.path, 'out-$chunk.iso')).readAsBytesSync();
  }

  test('detects an XISO, a Redump image, and anything else', () {
    final game = xiso();
    expect(detectXboxDisc(file('a.iso', game), gamePartition: gp), XboxDisc.xiso);
    expect(detectXboxDisc(file('b.iso', redump(game)), gamePartition: gp), XboxDisc.redump);
    expect(detectXboxDisc(file('c.iso', Uint8List(gp * 2)), gamePartition: gp), XboxDisc.unknown);
    expect(detectXboxDisc(file('d.iso', [1, 2, 3]), gamePartition: gp), XboxDisc.unknown);
  });

  test('streaming: a Redump image comes out as exactly its game partition, whatever the chunk size', () {
    final game = xiso();
    // 777 puts the partition edges and the probe's end mid-chunk.
    for (final chunk in [1 << 20, 4096, 777]) {
      expect(stream(redump(game), chunk), game, reason: 'chunk $chunk');
    }
  });

  test('streaming: an XISO is written as it is', () {
    final game = xiso();
    expect(stream(game, 4096), game);
    expect(stream(game, 999), game);
  });

  test('streaming: an image with no XDVDFS volume is refused', () {
    expect(() => stream(Uint8List(gp * 2), 4096), throwsA(isA<NotAnXboxDisc>()));
    expect(() => stream(Uint8List(100), 4096), throwsA(isA<NotAnXboxDisc>()));
  });

  test('a Redump file on disk becomes its XISO, with progress up to the total', () async {
    final game = xiso(tail: 20000);
    final src = file('r.iso', redump(game));
    final dst = p.join(dir.path, 'x.iso');
    final seen = <int>[];
    int? total;
    await redumpToXiso(src, dst, gamePartition: gp, onProgress: (d, t) {
      seen.add(d);
      total = t;
    });
    expect(io.File(dst).readAsBytesSync(), game);
    expect(seen.last, game.length);
    expect(total, game.length);
  });
}
