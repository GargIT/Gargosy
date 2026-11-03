import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/download_schedule.dart';
import 'package:gargosy/play/play_limits.dart';
import 'package:gargosy/play/play_time_left.dart';
import 'package:gargosy/profiles/play_limit.dart';
import 'package:gargosy/ui/widgets/play_time_left.dart';

void main() {
  final start = DateTime(2026, 11, 3, 16);
  const hour = PlayLimit(minutesPerDay: 60);

  group('PlayCheck.allowanceAt', () {
    test('idle, the minutes left stay; a running game counts down', () {
      final check = PlayCheck(const PlayAllowed(null), used: const Duration(minutes: 20), at: start);
      final later = start.add(const Duration(minutes: 10));
      final idle = check.allowanceAt(hour, later) as PlayAllowed;
      expect(idle.until!.difference(later), const Duration(minutes: 40));
      final playing = check.allowanceAt(hour, later, playingSince: start) as PlayAllowed;
      expect(playing.until!.difference(later), const Duration(minutes: 30));
    });

    test('a window counts down to its close even while idle', () {
      const limit = PlayLimit(window: DownloadWindow(15 * 60, 20 * 60));
      final check = PlayCheck(const PlayAllowed(null), used: Duration.zero, at: start);
      final a = check.allowanceAt(limit, start) as PlayAllowed;
      expect(a.until, DateTime(2026, 11, 3, 20));
    });

    test('used up: back at midnight; while a game still runs, it is the last minute', () {
      final check = PlayCheck(const PlayAllowed(null), used: const Duration(minutes: 60), at: start);
      final idle = check.allowanceAt(hour, start) as PlayRefused;
      expect(idle.backAt, DateTime(2026, 11, 4));
      final playing = check.allowanceAt(hour, start, playingSince: start);
      expect(playing, isA<PlayAllowed>());
    });
  });

  group('playTimeLeftLabel', () {
    test('says the time left, when play is back, and nothing without a limit', () {
      expect(playTimeLeftLabel(null, start), isNull);
      expect(playTimeLeftLabel(const PlayAllowed(null), start), isNull);
      expect(playTimeLeftLabel(PlayAllowed(start.add(const Duration(minutes: 42))), start), '42 min left');
      expect(playTimeLeftLabel(PlayAllowed(start.add(const Duration(minutes: 80))), start), '1 h 20 min left');
      expect(playTimeLeftLabel(PlayRefused('', DateTime(2026, 11, 3, 18, 5)), start), 'Back at 18:05');
      expect(playTimeLeftLabel(PlayRefused('', DateTime(2026, 11, 4, 15)), start), 'Back at 15:00 tomorrow');
      expect(playTimeLeftLabel(PlayRefused('', start), start), 'Play time not counted');
    });
  });

  group('PlayTimeLeftNotifier', () {
    test('no limit: nothing counted, nothing shown', () {
      var counts = 0;
      final n = PlayTimeLeftNotifier(
        limit: PlayLimit.off,
        count: () async {
          counts++;
          return PlayCheck(const PlayAllowed(null), used: Duration.zero, at: start);
        },
        clock: () => start,
        playingSince: () => null,
      );
      expect(n.state, isNull);
      expect(counts, 0);
      n.dispose();
    });

    test('counts down while a game runs, counts again when it ends and after a while', () {
      fakeAsync((async) {
        DateTime now() => start.add(async.elapsed);
        DateTime? since;
        var used = const Duration(minutes: 10);
        var counts = 0;
        final n = PlayTimeLeftNotifier(
          limit: hour,
          count: () async {
            counts++;
            return PlayCheck(const PlayAllowed(null), used: used, at: now());
          },
          clock: now,
          playingSince: () => since,
        );
        Duration left() => (n.state as PlayAllowed).until!.difference(now());
        async.flushMicrotasks();
        expect(counts, 1);
        expect(left(), const Duration(minutes: 50));

        since = now();
        n.sessionChanged(ended: false);
        async.elapse(const Duration(minutes: 5));
        expect(left(), const Duration(minutes: 45));
        expect(counts, 1);

        // The session ends and is logged: counted again, from the log.
        used += now().difference(since);
        since = null;
        n.sessionChanged(ended: true);
        async.flushMicrotasks();
        expect(counts, 2);
        expect(left(), const Duration(minutes: 45));

        // Another PC played meanwhile: seen at the next count.
        used += const Duration(minutes: 15);
        async.elapse(const Duration(minutes: 10, seconds: 15));
        expect(counts, 3);
        expect(left(), const Duration(minutes: 30));
        n.dispose();
      });
    });

    test('a count asked during one runs after it; the last one stays shown meanwhile', () {
      fakeAsync((async) {
        var counts = 0;
        final n = PlayTimeLeftNotifier(
          limit: hour,
          count: () async {
            counts++;
            await Future<void>.delayed(const Duration(seconds: 1));
            return PlayCheck(
              const PlayAllowed(null),
              used: Duration(minutes: counts),
              at: start,
            );
          },
          clock: () => start,
          playingSince: () => null,
        );
        n.recount();
        n.recount();
        expect(n.state, isNull);
        async.elapse(const Duration(seconds: 3));
        expect(counts, 2);
        expect((n.state as PlayAllowed).until, start.add(const Duration(minutes: 58)));
        n.dispose();
      });
    });
  });
}
