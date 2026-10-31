/// #229: another PC (RomM device) saved this game after this one last had
/// its save: Home's header says where the player left off.
class ElsewhereSave {
  const ElsewhereSave(this.deviceName, this.at);

  /// The other PC's name on RomM, else null ("another PC").
  final String? deviceName;
  final DateTime at;
}

/// Of RomM's saves of a game ([saves], `/api/saves` with this PC's
/// [deviceId], so each has `device_syncs`), the newest one this PC isn't
/// current with that another device synced within [within] of [now]; null
/// when this PC has the newest, or RomM says nothing of devices.
ElsewhereSave? newestElsewhere(
  List<Map<String, dynamic>> saves,
  String deviceId, {
  required DateTime now,
  Duration within = const Duration(days: 14),
}) {
  ElsewhereSave? best;
  for (final save in saves) {
    final syncs = save['device_syncs'];
    if (syncs is! List) continue;
    final mine = syncs.whereType<Map>().where((d) => '${d['device_id']}' == deviceId).firstOrNull;
    if (mine?['is_current'] == true) continue;
    for (final d in syncs.whereType<Map>()) {
      if ('${d['device_id']}' == deviceId) continue;
      final at = DateTime.tryParse('${d['last_synced_at'] ?? ''}');
      if (at == null || now.difference(at) > within) continue;
      if (best == null || at.isAfter(best.at)) {
        final name = '${d['device_name'] ?? ''}'.trim();
        best = ElsewhereSave(name.isEmpty ? null : name, at);
      }
    }
  }
  return best;
}
