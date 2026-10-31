import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:path/path.dart' as p;

/// Gargosy's log on disk (issue #1): `userdata\app\logs\gargosy-<yyyyMMdd-HHmmss>.log`,
/// a new file per start, the newest [keep] kept. Each line is written at once
/// (a crash loses nothing) until the file reaches [maxBytes]: then a last
/// line says so and the rest of the session isn't written, so a loop can't
/// fill the disk.
class FileLogSink {
  FileLogSink._(this.path, this._file, this.maxBytes);

  final String path;
  final int maxBytes;
  io.RandomAccessFile? _file;
  int _written = 0;

  static const defaultKeep = 10;
  static const defaultMaxBytes = 5 * 1024 * 1024;

  /// A longer line (a dumped response) is cut, so one line can't use up the
  /// file and silence the rest of the session.
  static const maxLineChars = 16 * 1024;
  static final _name = RegExp(r'^gargosy-\d{8}-\d{6}(-\d+)?\.log$');

  /// A new log file in [dir] (made when missing), the oldest beyond [keep]
  /// deleted. Null when the folder can't be written: Gargosy starts without
  /// a file log rather than not at all.
  static FileLogSink? open(
    String dir, {
    int keep = defaultKeep,
    int maxBytes = defaultMaxBytes,
    DateTime Function()? clock,
  }) {
    try {
      io.Directory(dir).createSync(recursive: true);
      final stamp = _stamp((clock ?? DateTime.now)());
      var path = p.join(dir, 'gargosy-$stamp.log');
      // Two starts in the same second (a crash and a restart) get their own files.
      for (var n = 2; io.File(path).existsSync(); n++) {
        path = p.join(dir, 'gargosy-$stamp-$n.log');
      }
      final file = io.File(path).openSync(mode: io.FileMode.writeOnly);
      _prune(dir, keep);
      return FileLogSink._(path, file, maxBytes);
    } on io.FileSystemException {
      return null;
    }
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// The logs in [dir], oldest first (a second start in the same second
  /// after the first); none when it can't be read.
  static List<io.File> logsIn(String dir) {
    try {
      return io.Directory(dir).listSync().whereType<io.File>().where((f) => _name.hasMatch(p.basename(f.path))).toList()
        ..sort((a, b) => _order(p.basename(a.path)).compareTo(_order(p.basename(b.path))));
    } on io.FileSystemException {
      return const [];
    }
  }

  /// Deletes the oldest logs so [keep] remain (names sort by time).
  static void _prune(String dir, int keep) {
    final logs = logsIn(dir);
    for (final old in logs.take(math.max(0, logs.length - keep))) {
      try {
        old.deleteSync();
      } on io.FileSystemException {
        // Open in another Gargosy (two copies running): it goes next time.
      }
    }
  }

  /// `gargosy-20261012-120000-2.log` sorts after `…-120000.log`.
  static String _order(String name) {
    final m = RegExp(r'^gargosy-(\d{8}-\d{6})(?:-(\d+))?\.log$').firstMatch(name)!;
    return '${m.group(1)}-${(m.group(2) ?? '1').padLeft(4, '0')}';
  }

  bool get isFull => _written >= maxBytes;

  /// Writes [line] and a line break. Never throws: a write that fails ends
  /// the file log for this session.
  void write(String line) {
    final file = _file;
    if (file == null || isFull) return;
    try {
      final text = line.length > maxLineChars ? '${line.substring(0, maxLineChars)} … (line cut)' : line;
      final bytes = utf8.encode('$text\r\n');
      final last = utf8.encode(
        '--- The log reached ${_size(maxBytes)}; the rest of this session is not written. ---\r\n',
      );
      // The last line always has room kept for it.
      if (_written + bytes.length > maxBytes - last.length) {
        file.writeFromSync(last);
        _written = maxBytes;
        return;
      }
      file.writeFromSync(bytes);
      _written += bytes.length;
    } on io.FileSystemException {
      close();
    }
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${bytes ~/ (1024 * 1024)} MB'
      : bytes >= 1024
      ? '${bytes ~/ 1024} KB'
      : '$bytes bytes';

  void close() {
    try {
      _file?.closeSync();
    } on io.FileSystemException {
      // Already gone.
    }
    _file = null;
  }
}
