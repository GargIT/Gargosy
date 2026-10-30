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

  /// The files whose bytes don't match RomM's, or that didn't come.
  final List<String> files;

  @override
  String toString() => tr('The download is damaged ({0}). Download it again.', [files.join(', ')]);
}

/// One of RomM's files for a game (`Game.files`): where it sits in the game's
/// folder ([path], `/`-separated) and its hashes.
class RomFileHashes {
  const RomFileHashes(this.path, {this.sha1, this.md5, this.crc});

  final String path;
  final String? sha1, md5, crc;

  String get name => p.posix.basename(path);

  bool get hasAny => sha1 != null || md5 != null || crc != null;

  /// [json] of a game whose folder is [folder] (its `fs_name`): RomM's
  /// `full_path` below that folder, else the file's name.
  static RomFileHashes? fromJson(Map<String, dynamic> json, {String? folder}) {
    final name = '${json['file_name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    final full = '${json['full_path'] ?? ''}'.replaceAll(r'\', '/');
    final marker = folder == null ? null : '/$folder/';
    final at = marker == null ? -1 : full.indexOf(marker);
    String? hash(String key) {
      final v = '${json[key] ?? ''}'.trim().toLowerCase();
      return v.isEmpty ? null : v;
    }

    return RomFileHashes(
      at < 0 ? name : full.substring(at + marker!.length),
      sha1: hash('sha1_hash'),
      md5: hash('md5_hash'),
      crc: hash('crc_hash'),
    );
  }
}

/// The ROM types RomM hashes by what's inside: a game that is one of these
/// (an arcade set, a zipped cartridge) isn't checked against RomM's hashes.
const archiveExtensions = {'.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.bz2', '.xz'};

/// Whether [path]'s bytes are [want]'s: SHA-1 when RomM has it, else MD5,
/// else CRC32. True when RomM has none. In another isolate (multi-GB discs).
Future<bool> fileMatches(String path, RomFileHashes want) => Isolate.run(() => _matches(path, want));

/// The files among [files] whose copy under [dir] doesn't match, or isn't
/// there: found by its path in the game's folder, else by name when only
/// one file has it. Listed and read in one other isolate.
Future<List<String>> damagedIn(String dir, List<RomFileHashes> files) => Isolate.run(() {
  final byName = <String, List<String>>{};
  for (final e in io.Directory(dir).listSync(recursive: true, followLinks: false)) {
    if (e is io.File) (byName[p.basename(e.path).toLowerCase()] ??= []).add(e.path);
  }
  final damaged = <String>[];
  for (final f in files) {
    if (!f.hasAny) continue;
    final atPath = p.joinAll([dir, ...p.posix.split(f.path)]);
    final named = byName[f.name.toLowerCase()] ?? const [];
    final path = io.File(atPath).existsSync() ? atPath : (named.length == 1 ? named.single : null);
    if (path == null || !_matches(path, f)) damaged.add(f.path);
  }
  return damaged;
});

bool _matches(String path, RomFileHashes want) {
  final file = io.File(path).openSync();
  try {
    if (want.sha1 != null || want.md5 != null) {
      final out = _Digest();
      final sink = (want.sha1 != null ? sha1 : md5).startChunkedConversion(out);
      _read(file, sink.add);
      sink.close();
      return '${out.value}' == (want.sha1 ?? want.md5);
    }
    final crcWant = want.crc;
    if (crcWant == null) return true;
    var crc = 0;
    _read(file, (chunk) => crc = getCrc32(chunk, crc));
    return crc.toRadixString(16).padLeft(8, '0') == crcWant.padLeft(8, '0');
  } finally {
    file.closeSync();
  }
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

/// Settings → Storage → Check downloads (#225): app-wide, on by default.
class DownloadCheck {
  static const key = 'downloads.check';

  static bool of(AppPreferences prefs) => prefs.getBool(key) ?? true;
}
