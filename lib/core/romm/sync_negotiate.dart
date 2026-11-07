/// RomM's sync negotiation (#294, RomM 5.4: `POST /api/sync/negotiate`), as
/// Gargosy asks it to compare, not to act on (see docs/negotiate-sync.md).
library;

/// A save on this PC as negotiate is told of it.
class NegotiateSave {
  const NegotiateSave({
    required this.romId,
    required this.fileName,
    required this.slot,
    required this.emulator,
    required this.contentHash,
    required this.updatedAt,
    required this.sizeBytes,
  });

  final String romId;
  final String fileName;
  final String slot;
  final String emulator;

  /// RomM's hash of the save as a push would upload it; null when it can't
  /// be had.
  final String? contentHash;
  final DateTime updatedAt;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
    'rom_id': int.tryParse(romId) ?? romId,
    'file_name': fileName,
    'slot': slot,
    'emulator': emulator,
    'content_hash': ?contentHash,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'file_size_bytes': sizeBytes,
  };
}

/// One of negotiate's answers.
class SyncOperation {
  const SyncOperation({required this.action, this.saveId, this.slot, this.emulator, this.reason});

  /// `upload`, `download`, `conflict`, `delete` or `no_op`.
  final String action;
  final int? saveId;
  final String? slot;
  final String? emulator;
  final String? reason;

  static SyncOperation? fromJson(Object? json) {
    if (json is! Map) return null;
    final action = json['action'];
    if (action is! String) return null;
    String? text(String key) => json[key] is String ? json[key] as String : null;
    return SyncOperation(
      action: action,
      saveId: json['save_id'] is int ? json['save_id'] as int : null,
      slot: text('slot'),
      emulator: text('emulator'),
      reason: text('reason'),
    );
  }

  @override
  String toString() =>
      '$action${saveId == null ? '' : ' save $saveId'}${slot == null ? '' : ' [$slot]'}'
      '${emulator == null ? '' : ' $emulator'}${reason == null ? '' : ': $reason'}';
}

/// What negotiate answered: its session (to complete) and its operations.
class NegotiateResult {
  const NegotiateResult(this.sessionId, this.operations);
  final int sessionId;
  final List<SyncOperation> operations;
}
