// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: init() also writes every line, redacted, with time, level and the
// profile's short id, to a FileLogSink (issue #1); error() for uncaught errors.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'file_log_sink.dart';
import 'log_redaction.dart';

class LogEntry {
  final DateTime timestamp;
  final String message;
  final String? level;

  LogEntry(this.message, {this.level, DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[${timestamp.toIso8601String().substring(11, 19)}] ${level != null ? '[$level] ' : ''}$message';
}

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  final List<LogEntry> _logs = [];
  final StreamController<List<LogEntry>> _controller = StreamController<List<LogEntry>>.broadcast();

  List<LogEntry> get logs => List.unmodifiable(_logs);
  Stream<List<LogEntry>> get logStream => _controller.stream;

  static FileLogSink? _sink;
  static String? Function() _tag = () => null;
  static DebugPrintCallback? _originalDebugPrint;

  /// The open profile's short id for the file log (`[p:452988cf]`), never
  /// its name; set by GargosyApp when the profile changes.
  static String? profileTag;

  /// The short id [profileTag] holds for a profile [id].
  static String shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

  /// The file log, when [init] was given one.
  static FileLogSink? get sink => _sink;

  void log(String message, {String? level}) {
    final entry = LogEntry(message, level: level);
    _logs.add(entry);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    _controller.add(logs);
    _toFile(entry);
  }

  void clear() {
    _logs.clear();
    _controller.add(logs);
  }

  /// An uncaught error and its stack, to the log as level ERROR.
  void error(Object error, StackTrace? stack, {String? context}) =>
      log('${context == null ? '' : '$context: '}$error${stack == null ? '' : '\n$stack'}', level: 'ERROR');

  /// Hooks `debugPrint`: every line is kept in memory (the last 500) and,
  /// with [sink], written to the file log, redacted, with the time, the
  /// level and [tag] (the open profile's short id, or null). Calling it
  /// again replaces the sink and tag; `debugPrint` is hooked once.
  static void init({FileLogSink? sink, String? Function()? tag}) {
    _sink = sink;
    if (tag != null) _tag = tag;
    if (_originalDebugPrint != null) return;
    final originalDebugPrint = _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        LoggerService().log(message);
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
  }

  /// Writes [line] (a header line) to the file log as it is, redacted.
  static void writeRaw(String line) => _sink?.write(redact(line));

  static int? _day;

  static void _toFile(LogEntry entry) {
    final sink = _sink;
    if (sink == null) return;
    final t = entry.timestamp;
    String two(int n) => n.toString().padLeft(2, '0');
    // Lines carry the time only; a session past midnight says the new date.
    final day = t.year * 10000 + t.month * 100 + t.day;
    if (_day != null && _day != day) sink.write('--- ${t.year}-${two(t.month)}-${two(t.day)} ---');
    _day = day;
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
    final tag = _tag();
    final head = '$time${entry.level == null ? '' : ' [${entry.level}]'}${tag == null ? '' : ' [p:$tag]'} ';
    // Continuation lines (a stack, a multi-line message) are indented under the first.
    final text = redact(entry.message).replaceAll('\r\n', '\n').replaceAll('\n', '\r\n${' ' * head.length}');
    sink.write('$head$text');
  }
}
