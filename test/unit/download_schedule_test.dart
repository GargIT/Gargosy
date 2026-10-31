import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/download_schedule.dart';
import 'package:gargosy/library/throttled_download.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_dio_adapter.dart';
import '../helpers/profile_test_env.dart';

void main() {
  group('DownloadWindow', () {
    test('kept as HH:MM-HH:MM; anything else is no window', () {
      final w = DownloadWindow.parse('22:00-07:00')!;
      expect(w, const DownloadWindow(22 * 60, 7 * 60));
      expect('$w', '22:00-07:00');
      expect(w.label, '22:00–07:00');
      for (final bad in [null, '', '25:00-07:00', '07:00-07:00', 'night']) {
        expect(DownloadWindow.parse(bad), isNull, reason: '$bad');
      }
    });

    test('over midnight: open late and early, closed in the day; it says when it opens', () {
      const w = DownloadWindow(22 * 60, 7 * 60);
      expect(w.allows(DateTime(2026, 10, 31, 23, 30)), isTrue);
      expect(w.allows(DateTime(2026, 10, 31, 6, 59)), isTrue);
      expect(w.allows(DateTime(2026, 10, 31, 7)), isFalse);
      expect(w.opensAt(DateTime(2026, 10, 31, 12)), DateTime(2026, 10, 31, 22));
      const day = DownloadWindow(9 * 60, 17 * 60);
      expect(day.allows(DateTime(2026, 10, 31, 12)), isTrue);
      expect(day.opensAt(DateTime(2026, 10, 31, 18)), DateTime(2026, 11, 1, 9));
    });

    test('the speed: a choice Settings offers, else none', () {
      expect(DownloadLimits.of(MemoryPrefs()..setString(DownloadLimits.speedKey, '5')).bytesPerSecond, 5 * 1024 * 1024);
      expect(DownloadLimits.of(MemoryPrefs()..setString(DownloadLimits.speedKey, '7')).megabytesPerSecond, 0);
      expect(DownloadLimits.of(MemoryPrefs()).window, isNull);
    });
  });

  group('downloadThrottled', () {
    late String dir;
    setUp(() async => dir = (await tempAppRoot()).appData);

    test('waits so the bytes come no faster than the limit', () async {
      final sleeps = <Duration>[];
      await downloadThrottled(
        fakeDio(FakeDioAdapter((r) => (status: 200, body: List<int>.filled(3000, 1)))),
        '/x',
        p.join(dir, 'a.part'),
        options: Options(),
        bytesPerSecond: () => 1000,
        clock: Stopwatch(), // never started: no time passes
        sleep: (d) async => sleeps.add(d),
      );
      expect(io.File(p.join(dir, 'a.part')).lengthSync(), 3000);
      expect(sleeps.fold(Duration.zero, (a, b) => a + b), const Duration(seconds: 3));
    });

    test('a failure deletes what was written', () async {
      final path = p.join(dir, 'b.part');
      await expectLater(
        downloadThrottled(
          fakeDio(FakeDioAdapter((r) => (status: 500, body: 'no'))),
          '/x',
          path,
          options: Options(),
          bytesPerSecond: () => 1000,
        ),
        throwsA(isA<DioException>()),
      );
      expect(io.File(path).existsSync(), isFalse);
    });
  });
}
