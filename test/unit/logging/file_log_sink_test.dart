import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/storage/file_log_sink.dart';
import 'package:path/path.dart' as p;

void main() {
  late io.Directory dir;
  var now = DateTime(2026, 10, 12, 9, 5, 7);

  setUp(() {
    dir = io.Directory.systemTemp.createTempSync('gargosy_logs');
    now = DateTime(2026, 10, 12, 9, 5, 7);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> names() => dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  test('a file per open, named by the time', () {
    final a = FileLogSink.open(dir.path, clock: () => now)!;
    now = now.add(const Duration(minutes: 1));
    final b = FileLogSink.open(dir.path, clock: () => now)!;
    a.close();
    b.close();
    expect(names(), ['gargosy-20261012-090507.log', 'gargosy-20261012-090607.log']);
  });

  test('two starts in the same second get their own files', () {
    final a = FileLogSink.open(dir.path, clock: () => now)!;
    final b = FileLogSink.open(dir.path, clock: () => now)!;
    a.close();
    b.close();
    expect(names(), ['gargosy-20261012-090507-2.log', 'gargosy-20261012-090507.log']);
  });

  test('only the newest [keep] remain; other files in the folder are left alone', () {
    io.File(p.join(dir.path, 'notes.txt')).writeAsStringSync('mine');
    for (var i = 0; i < 5; i++) {
      FileLogSink.open(dir.path, keep: 3, clock: () => now.add(Duration(hours: i)))!.close();
    }
    expect(names(), [
      'gargosy-20261012-110507.log',
      'gargosy-20261012-120507.log',
      'gargosy-20261012-130507.log',
      'notes.txt',
    ]);
  });

  test('lines are on disk at once, UTF-8, CRLF', () {
    final sink = FileLogSink.open(dir.path, clock: () => now)!;
    sink.write('first');
    sink.write('Pokémon – Röd');
    expect(io.File(sink.path).readAsStringSync(), 'first\r\nPokémon – Röd\r\n', reason: 'before close');
    sink.close();
  });

  test('it stops at maxBytes with a last line saying so', () {
    final sink = FileLogSink.open(dir.path, maxBytes: 100, clock: () => now)!;
    for (var i = 0; i < 50; i++) {
      sink.write('line $i of a loop');
    }
    sink.close();
    final text = io.File(sink.path).readAsStringSync();
    expect(text, startsWith('line 0 of a loop\r\n'));
    expect(text.trim().split('\r\n').last, contains('The log reached 100 bytes'));
    expect(text.split('The log reached').length, 2, reason: 'said once');
    expect(sink.isFull, isTrue);
  });

  test('a folder that cannot be made means no file log, not an error', () {
    final blocker = io.File(p.join(dir.path, 'logs'))..writeAsStringSync('a file where the folder should be');
    expect(FileLogSink.open(p.join(blocker.path, 'inner')), isNull);
  });

  test('writing after close does nothing', () {
    final sink = FileLogSink.open(dir.path, clock: () => now)!;
    sink.close();
    sink.write('late');
    expect(io.File(sink.path).readAsStringSync(), isEmpty);
  });
}
