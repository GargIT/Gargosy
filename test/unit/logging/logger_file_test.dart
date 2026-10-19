import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/storage/file_log_sink.dart';
import 'package:gargosy/core/storage/logger_service.dart';

void main() {
  late io.Directory dir;
  late FileLogSink sink;

  setUp(() {
    dir = io.Directory.systemTemp.createTempSync('gargosy_logger');
    sink = FileLogSink.open(dir.path)!;
  });
  tearDown(() {
    LoggerService.init(sink: null);
    LoggerService.profileTag = null;
    sink.close();
    dir.deleteSync(recursive: true);
  });

  String file() => io.File(sink.path).readAsStringSync();

  test('a debugPrint reaches the file, redacted and tagged with the profile', () {
    LoggerService.init(sink: sink, tag: () => LoggerService.profileTag);
    LoggerService.profileTag = LoggerService.shortId('452988cf-1111-2222-3333-444455556666');
    debugPrint('[RomM] GET /api/roms?token=secret123&id=1');
    final text = file();
    expect(
      text,
      matches(RegExp(r'^\d\d:\d\d:\d\d\.\d{3} \[p:452988cf\] \[RomM\] GET /api/roms\?token=\*\*\*&id=1\r\n$')),
    );
    expect(text, isNot(contains('secret123')));
    expect(
      LoggerService().logs.last.message,
      contains('secret123'),
      reason: 'memory keeps the line as it was (never written)',
    );
  });

  test('no profile: no tag', () {
    LoggerService.init(sink: sink, tag: () => LoggerService.profileTag);
    debugPrint('starting');
    expect(file(), isNot(contains('[p:')));
  });

  test('an error with its stack: level ERROR, the stack indented under it', () {
    LoggerService.init(sink: sink, tag: () => null);
    LoggerService().error(
      StateError('boom'),
      StackTrace.fromString('#0 main (file.dart:1)\n#1 run (file.dart:2)'),
      context: 'Uncaught',
    );
    final lines = file().split('\r\n');
    expect(lines[0], contains('[ERROR] Uncaught: Bad state: boom'));
    expect(lines[1], matches(RegExp(r'^ +#0 main')));
    expect(lines[2], matches(RegExp(r'^ +#1 run')));
  });

  test('init twice hooks debugPrint once: a line is written once', () {
    LoggerService.init(sink: sink);
    LoggerService.init(sink: sink);
    debugPrint('once');
    expect('once'.allMatches(file()).length, 1);
  });

  test('writeRaw: header lines as they are, redacted', () {
    LoggerService.init(sink: sink);
    LoggerService.writeRaw('Gargosy 0.2.0');
    LoggerService.writeRaw('Authorization: Bearer abcdefghijkl');
    expect(file(), 'Gargosy 0.2.0\r\nAuthorization: Bearer ***\r\n');
  });
}
