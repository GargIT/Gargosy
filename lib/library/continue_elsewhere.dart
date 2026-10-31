import '../core/romm/romm_models.dart';

/// #229: another PC (RomM device) saved this game after this one last had
/// its save: Home's header says where the player left off.
class ElsewhereSave {
  const ElsewhereSave(this.deviceName, this.at);

  /// The other PC's name on RomM, else null ("another PC").
  final String? deviceName;
  final DateTime at;
}

/// Of RomM's saves of a game ([saves], `/api/saves` with this PC's
/// [deviceId], so each has `device_syncs`), the newest of each slot only
/// (an old version this PC skipped says nothing): one this PC isn't current
/// with that another device synced within [within] of [now] gives that
/// device. Null when this PC has the newest everywhere, or RomM lists no
/// other devices (a RomM before it listed every device that synced a save).
ElsewhereSave? newestElsewhere(
  List<Map<String, dynamic>> saves,
  String deviceId, {
  required DateTime now,
  Duration within = const Duration(days: 14),
}) {
  final newestBySlot = <String, Map<String, dynamic>>{};
  DateTime? updated(Map<String, dynamic> s) => DateTime.tryParse('${s['updated_at'] ?? ''}');
  for (final s in saves) {
    final slot = '${s['slot'] ?? s['file_name'] ?? s['id']}';
    final had = newestBySlot[slot];
    final at = updated(s), hadAt = had == null ? null : updated(had);
    if (had == null || (at != null && (hadAt == null || at.isAfter(hadAt)))) newestBySlot[slot] = s;
  }
  ElsewhereSave? best;
  for (final save in newestBySlot.values) {
    final syncs = SaveFile.fromJson(save).deviceSyncs;
    if (syncs.any((d) => d.deviceId == deviceId && d.isCurrent)) continue;
    for (final d in syncs) {
      final at = d.lastSyncedAt;
      if (d.deviceId == deviceId || at == null || now.difference(at) > within) continue;
      if (best == null || at.isAfter(best.at)) {
        final name = d.deviceName?.trim() ?? '';
        best = ElsewhereSave(name.isEmpty ? null : name, at);
      }
    }
  }
  return best;
}
