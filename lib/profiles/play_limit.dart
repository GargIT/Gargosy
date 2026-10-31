import '../library/download_schedule.dart';
import '../l10n/tr.dart';

/// #235: how long and when a profile may play: minutes a day (counted
/// across every PC) and a daily window. Kept in `profile.json` beside the
/// age limit, changed only with a parent's PIN.
class PlayLimit {
  const PlayLimit({this.minutesPerDay, this.window});

  /// Off when null.
  final int? minutesPerDay;

  /// Off when null; one that ends before it starts runs over midnight.
  final DownloadWindow? window;

  static const off = PlayLimit();

  /// What Settings offers.
  static const minuteChoices = [30, 60, 90, 120, 180];
  static const windowChoices = [
    DownloadWindow(15 * 60, 20 * 60),
    DownloadWindow(16 * 60, 19 * 60),
    DownloadWindow(10 * 60, 20 * 60),
    DownloadWindow(9 * 60, 21 * 60),
  ];

  /// The warning comes this long before the time is up.
  static const warnBefore = Duration(minutes: 5);

  bool get isOn => minutesPerDay != null || window != null;

  PlayLimit copyWith({int? Function()? minutesPerDay, DownloadWindow? Function()? window}) => PlayLimit(
    minutesPerDay: minutesPerDay == null ? this.minutesPerDay : minutesPerDay(),
    window: window == null ? this.window : window(),
  );

  Map<String, Object?> toJson() => {'minutesPerDay': ?minutesPerDay, 'window': ?window?.toString()};

  static PlayLimit fromJson(Object? json) {
    if (json is! Map) return off;
    final minutes = json['minutesPerDay'];
    return PlayLimit(
      minutesPerDay: minutes is int && minutes > 0 ? minutes : null,
      window: DownloadWindow.parse(json['window'] is String ? json['window'] as String : null),
    );
  }

  static String minutesLabel(int? m) => m == null
      ? tr('No limit')
      : m % 60 == 0
      ? tr('{0} h a day', [m ~/ 60])
      : tr('{0} min a day', [m]);

  static String windowLabel(DownloadWindow? w) => w == null ? tr('Any time') : w.label;

  @override
  bool operator ==(Object other) =>
      other is PlayLimit && other.minutesPerDay == minutesPerDay && other.window == window;

  @override
  int get hashCode => Object.hash(minutesPerDay, window);
}

/// Whether a game may start now, and until when.
sealed class PlayAllowance {
  const PlayAllowance();
}

/// It may; [until] is when the time is up (null: no limit today).
class PlayAllowed extends PlayAllowance {
  const PlayAllowed(this.until);
  final DateTime? until;
}

/// It may not, said in [reason]; back at [backAt].
class PlayRefused extends PlayAllowance {
  const PlayRefused(this.reason, this.backAt);
  final String reason;
  final DateTime backAt;
}

/// Midnight starting [t]'s day, on the calendar (a day with a clock change
/// has 23 or 25 hours).
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime _nextDay(DateTime t) => DateTime(t.year, t.month, t.day + 1);
DateTime _at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

/// When the day [limit]'s minutes count from began, at [now]: midnight, or
/// with a window over midnight, when it last opened (an evening's play
/// isn't given fresh minutes at 00:00).
DateTime playDayStart(PlayLimit limit, DateTime now) {
  final w = limit.window;
  final midnight = startOfDay(now);
  if (w == null || w.from < w.to) return midnight;
  final opened = _at(midnight, w.from);
  return now.isBefore(opened) ? _at(DateTime(now.year, now.month, now.day - 1), w.from) : opened;
}

/// The time [sessions] (start, end) spent from [from] to [to], each cut to it.
Duration playedBetween(DateTime from, DateTime to, Iterable<(DateTime, DateTime)> sessions) {
  var total = Duration.zero;
  for (final (start, end) in sessions) {
    final s = start.isBefore(from) ? from : start;
    final e = end.isAfter(to) ? to : end;
    if (e.isAfter(s)) total += e.difference(s);
  }
  return total;
}

/// The time [sessions] spent on [day].
Duration playedOn(DateTime day, Iterable<(DateTime, DateTime)> sessions) =>
    playedBetween(startOfDay(day), _nextDay(day), sessions);

/// When [w], open at [now], closes.
DateTime windowClosesAt(DownloadWindow w, DateTime now) {
  final today = _at(now, w.to);
  return today.isAfter(now) ? today : _at(_nextDay(now), w.to);
}

/// Less than this left counts as used up: a start that could only run for
/// seconds would never be logged (sessions under 5 s aren't), so the time
/// would never run out.
const _leastLeft = Duration(minutes: 1);

/// Whether [limit] lets a game start at [now], with [used] already played
/// in this play day ([playDayStart]), and until when.
PlayAllowance allowanceFor(PlayLimit limit, Duration used, DateTime now) {
  if (!limit.isOn) return const PlayAllowed(null);
  String at(DateTime t) {
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return startOfDay(t) == startOfDay(now) ? hm : tr('{0} tomorrow', [hm]);
  }

  final window = limit.window;
  if (window != null && !window.allows(now)) {
    final back = window.opensAt(now);
    return PlayRefused(tr('This profile plays {0}. Back at {1}.', [window.label, at(back)]), back);
  }
  final minutes = limit.minutesPerDay;
  DateTime? until;
  if (minutes != null) {
    final left = Duration(minutes: minutes) - used;
    if (left < _leastLeft) {
      final back = window == null ? _nextDay(now) : window.opensAt(windowClosesAt(window, now));
      return PlayRefused(tr('Today\'s play time is used up. Back at {0}.', [at(back)]), back);
    }
    until = now.add(left);
  }
  if (window != null) {
    final closes = windowClosesAt(window, now);
    if (until == null || closes.isBefore(until)) until = closes;
  }
  return PlayAllowed(until);
}
