import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../platform/platform_info.dart';

/// A file in a zip and its unpacked size.
typedef ZipEntry = ({String name, int size});

/// The unpacker refused or failed; [detail] is what it said.
class UnpackException implements Exception {
  const UnpackException(this.detail);
  final String detail;

  @override
  String toString() => detail;
}

/// Lists, unpacks and streams zips (#200): a ROM's zip before an emulator
/// that can't open it, an Xbox disc streamed into its XISO, an emulator's
/// download. Never writes outside the folder it's given; callers check
/// what landed there.
abstract class Unpacker {
  /// The zip's files (not its folders), with their sizes.
  Future<List<ZipEntry>> list(String zip);

  /// Unpacks [zip] into [into], leaving out names matching [exclude]
  /// (globs). [tick] is called now and then while it runs.
  Future<void> unpack(String zip, String into, {List<String> exclude = const [], void Function()? tick});

  /// The bytes of the zip's file matching [pattern] (a glob), streamed;
  /// cancelling the stream stops the unpacker. Ends with an
  /// [UnpackException] when it fails.
  Stream<List<int>> open(String zip, String pattern);
}

/// The [Unpacker] of [platform]'s OS.
Unpacker unpackerFor(PlatformInfo platform) {
  if (platform.isWindows) return TarUnpacker(platform);
  throw UnsupportedError('No unpacker on ${platform.os} yet');
}

final unpackerProvider = Provider<Unpacker>((ref) => unpackerFor(PlatformInfo.current));

/// Windows' own `tar.exe` (bsdtar, hundreds of MB/s), by its path: a plain
/// `tar` can find Git's GNU tar first, which reads `C:\...` as a remote
/// host and doesn't read zips.
class TarUnpacker implements Unpacker {
  TarUnpacker(PlatformInfo platform)
    : tar = p.join(platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32', 'tar.exe');

  final String tar;

  @override
  Future<List<ZipEntry>> list(String zip) async {
    final r = await io.Process.run(tar, ['-tvf', zip]);
    if (r.exitCode != 0) throw UnpackException((r.stderr as String).trim());
    // -rw-rw-r--  0 0      0  7825162240 dec 24  1996 Name.iso (the month is localised)
    final line = RegExp(r'^(\S)\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+\S+\s(.*)$');
    return [
      for (final l in const LineSplitter().convert(r.stdout as String))
        if (line.firstMatch(l.trimRight()) case final m? when m.group(1) == '-')
          (name: m.group(3)!, size: int.parse(m.group(2)!)),
    ];
  }

  @override
  Future<void> unpack(String zip, String into, {List<String> exclude = const [], void Function()? tick}) async {
    final proc = await io.Process.start(tar, [
      '-xf',
      zip,
      '-C',
      into,
      for (final e in exclude) ...['--exclude', e],
    ]);
    final err = StringBuffer();
    final errDone = proc.stderr.transform(io.systemEncoding.decoder).forEach(err.write);
    final outDone = proc.stdout.drain<void>();
    final timer = tick == null ? null : Timer.periodic(const Duration(milliseconds: 500), (_) => tick());
    final code = await proc.exitCode;
    timer?.cancel();
    await errDone;
    await outDone;
    if (code != 0) throw UnpackException(err.toString().trim());
  }

  @override
  Stream<List<int>> open(String zip, String pattern) async* {
    final proc = await io.Process.start(tar, ['-xOf', zip, pattern]);
    final err = StringBuffer();
    final errDone = proc.stderr.transform(io.systemEncoding.decoder).forEach(err.write);
    var finished = false;
    try {
      yield* proc.stdout;
      finished = true;
    } finally {
      if (!finished) proc.kill();
      await proc.exitCode;
      await errDone;
    }
    if (await proc.exitCode != 0) throw UnpackException(err.toString().trim());
  }
}
