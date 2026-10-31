import 'dart:io' as io;

import 'dart:typed_data';

import 'package:dio/io.dart';
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

  group('ThrottledAdapter', () {
    Stream<Uint8List> chunks(int n, int size) => Stream.fromIterable([for (var i = 0; i < n; i++) Uint8List(size)]);

    test('waits so the bytes come no faster than the limit, in waits of at most half a second', () async {
      final sleeps = <Duration>[];
      final a = ThrottledAdapter(
        IOHttpClientAdapter(),
        () => 1000,
        clock: Stopwatch.new, // never started: no time passes
        sleep: (d) async => sleeps.add(d),
      );
      expect((await a.paced(chunks(3, 1000)).toList()).length, 3);
      expect(sleeps.fold(Duration.zero, (x, y) => x + y), const Duration(seconds: 6), reason: '1 + 2 + 3 s due');
      expect(sleeps.every((d) => d <= ThrottledAdapter.maxWait), isTrue);
    });

    test('a changed limit counts from when it changed; none passes straight through', () async {
      final sleeps = <Duration>[];
      var rate = 1000;
      final a = ThrottledAdapter(
        IOHttpClientAdapter(),
        () => rate,
        clock: Stopwatch.new,
        sleep: (d) async {
          sleeps.add(d);
          rate = 0;
        },
      );
      await a.paced(chunks(3, 1000)).toList();
      expect(
        sleeps.fold(Duration.zero, (x, y) => x + y),
        const Duration(milliseconds: 500),
        reason: 'the first wait, then no limit',
      );
    });

    test('a Dio with it downloads as before', () async {
      final dir = (await tempAppRoot()).appData;
      final dio = throttledDio(fakeDio(FakeDioAdapter((r) => (status: 200, body: List<int>.filled(3000, 1)))), () => 0);
      await dio.download('/x', p.join(dir, 'a.part'));
      expect(io.File(p.join(dir, 'a.part')).lengthSync(), 3000);
    });
  });

  test('the window opens on the calendar, also on a day the clock changes', () {
    const w = DownloadWindow(22 * 60, 7 * 60);
    expect(w.opensAt(DateTime(2026, 10, 25, 12)), DateTime(2026, 10, 25, 22));
    expect(w.opensAt(DateTime(2026, 3, 29, 12)), DateTime(2026, 3, 29, 22));
  });
}
