import '../core/storage/app_preferences.dart';
import '../l10n/tr.dart';

/// #228: how fast and when downloads may run. App-wide (one connection for
/// every profile): Settings → Storage → Downloads.
class DownloadLimits {
  const DownloadLimits({this.megabytesPerSecond = 0, this.window});

  /// 0: no limit.
  final int megabytesPerSecond;

  /// When downloads start; null: any time.
  final DownloadWindow? window;

  static const speedKey = 'downloads.speedLimit';
  static const windowKey = 'downloads.window';

  /// The speeds Settings offers, in MB/s (0 is Off).
  static const speeds = [0, 2, 5, 10, 25, 50];

  int get bytesPerSecond => megabytesPerSecond * 1024 * 1024;

  static DownloadLimits of(AppPreferences prefs) {
    final speed = int.tryParse(prefs.getString(speedKey) ?? '') ?? 0;
    return DownloadLimits(
      megabytesPerSecond: speeds.contains(speed) ? speed : 0,
      window: DownloadWindow.parse(prefs.getString(windowKey)),
    );
  }

  static String speedLabel(int mbps) => mbps == 0 ? tr('No limit') : tr('{0} MB/s', [mbps]);
}

/// A daily window, from [from] to [to] (minutes after midnight); one that
/// ends before it starts runs over midnight.
class DownloadWindow {
  const DownloadWindow(this.from, this.to);

  final int from, to;

  /// The windows Settings offers.
  static const presets = [
    DownloadWindow(22 * 60, 7 * 60),
    DownloadWindow(23 * 60, 6 * 60),
    DownloadWindow(0, 8 * 60),
    DownloadWindow(1 * 60, 7 * 60),
    DownloadWindow(9 * 60, 17 * 60),
  ];

  /// `HH:MM-HH:MM`, as kept in the pref; null for anything else.
  static DownloadWindow? parse(String? text) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$').firstMatch(text ?? '');
    if (m == null) return null;
    int at(int h, int min) => int.parse(m.group(h)!) * 60 + int.parse(m.group(min)!);
    final from = at(1, 2), to = at(3, 4);
    if (from >= 24 * 60 || to >= 24 * 60 || from == to) return null;
    return DownloadWindow(from, to);
  }

  static String _hm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  String toString() => '${_hm(from)}-${_hm(to)}';

  /// As shown: `22:00–07:00`.
  String get label => '${_hm(from)}–${_hm(to)}';

  /// Whether [t] is inside the window.
  bool allows(DateTime t) {
    final m = t.hour * 60 + t.minute;
    return from < to ? m >= from && m < to : m >= from || m < to;
  }

  /// When the window next opens after [t] ([t] itself when it's open).
  DateTime opensAt(DateTime t) {
    if (allows(t)) return t;
    final today = DateTime(t.year, t.month, t.day).add(Duration(minutes: from));
    return today.isAfter(t) ? today : today.add(const Duration(days: 1));
  }

  @override
  bool operator ==(Object other) => other is DownloadWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}
