import '../../core/romm/romm_play_sessions.dart';
import '../../l10n/tr.dart';

/// 1.4 GB, 512 MB, 12 KB.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value >= 10 || unit == 0 ? value.toStringAsFixed(0) : decimal(value, 1)} ${units[unit]}';
}

/// 2026-10-09 14:05 (local time).
String formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// 12 h 40 min, 35 min, under a minute (#146).
String formatPlayTime(Duration d) {
  if (d.inMinutes < 1) return tr('under a minute');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return tr('{0} min', [m]);
  return m == 0 ? tr('{0} h', [h]) : tr('{0} h {1} min', [h, m]);
}

/// "Played 12 h 40 min · 8 sessions", "… on this PC" when RomM's aren't in it.
String playTimeLine(PlayTime t) => tr('Played {0} · {1} {2}{3}', [
  formatPlayTime(t.total),
  t.sessions,
  t.sessions == 1 ? tr('session') : tr('sessions'),
  t.thisPcOnly ? tr(' on this PC') : '',
]);
