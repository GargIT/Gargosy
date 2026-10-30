import 'dart:io' as io;
import 'dart:isolate';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/storage/app_preferences.dart';
import '../l10n/tr.dart';

/// #225: a download is checked against RomM's hashes of its files before it
/// moves into `roms\`. A cut connection or a bad disk is the usual cause of
/// "the game won't start".
class DownloadDamaged implements Exception {
  const DownloadDamaged(this.files);

  /// The files whose bytes don't match RomM's.
  final List<String> files;

  @override
  String toString() => tr('The download is damaged ({0}). Download it again.', [files.join(', ')]);
}

/// One of RomM's files for a game (`Game.files`): its name and hashes.
class RomFileHashes {
  const RomFileHashes(this.name, {this.sha1, this.md5, this.crc});

  final String name;
  final String? sha1, md5, crc;

  bool get hasAny => sha1 != null || md5 != null || crc != null;

  static RomFileHashes? fromJson(Map<String, dynamic> json) {
    final name = '${json['file_name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    String? hash(String key) {
      final v = '${json[key] ?? ''}'.trim().toLowerCase();
      return v.isEmpty ? null : v;
    }

    return RomFileHashes(name, sha1: hash('sha1_hash'), md5: hash('md5_hash'), crc: hash('crc_hash'));
  }
}

/// Whether [path]'s bytes are [want]'s: SHA-1 when RomM has it, else MD5,
/// else CRC32. True when RomM has none. In another isolate (multi-GB discs).
Future<bool> fileMatches(String path, RomFileHashes want) {
  final sha1Want = want.sha1, md5Want = want.md5, crcWant = want.crc;
  return Isolate.run(() {
    final file = io.File(path).openSync();
    try {
      if (sha1Want != null || md5Want != null) {
        final out = _Digest();
        final sink = (sha1Want != null ? sha1 : md5).startChunkedConversion(out);
        _read(file, sink.add);
        sink.close();
        return '${out.value}' == (sha1Want ?? md5Want);
      }
      if (crcWant == null) return true;
      var crc = 0;
      _read(file, (chunk) => crc = getCrc32(chunk, crc));
      return crc.toRadixString(16).padLeft(8, '0') == crcWant.padLeft(8, '0');
    } finally {
      file.closeSync();
    }
  });
}

void _read(io.RandomAccessFile file, void Function(List<int>) add) {
  while (true) {
    final chunk = file.readSync(1 << 20);
    if (chunk.isEmpty) return;
    add(chunk);
  }
}

class _Digest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// The names among [files] whose copy under [dir] (found by name, at any
/// depth) doesn't match; a file not found there isn't checked.
Future<List<String>> damagedIn(String dir, List<RomFileHashes> files) async {
  final byName = <String, String>{};
  for (final e in io.Directory(dir).listSync(recursive: true, followLinks: false)) {
    if (e is io.File) byName.putIfAbsent(p.basename(e.path).toLowerCase(), () => e.path);
  }
  final damaged = <String>[];
  for (final f in files) {
    final path = byName[f.name.toLowerCase()];
    if (f.hasAny && path != null && !await fileMatches(path, f)) damaged.add(f.name);
  }
  return damaged;
}

/// Settings → Storage → Check downloads (#225): app-wide, on by default.
class DownloadCheck {
  static const key = 'downloads.check';

  static bool of(AppPreferences prefs) => prefs.getBool(key) ?? true;
}
