// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io' as io;
import 'dart:typed_data';

/// A save state stored on RomM (`/api/states`). States belong to one RomM
/// user and are private unless the owner flips `is_public` (Gargosy's Share,
/// #92).
class RommState {
  final int id;
  final String fileName;

  /// RomM's `updated_at`. Only ever compared for equality against the value
  /// stored right after our own upload/download: RomM sets it on rescans too,
  /// so it says "something happened", not "the bytes are newer".
  final String? updatedAt;

  /// The `emulator` value the state was uploaded with, if any. Gargosy sends
  /// its emulator id; other clients may send anything.
  final String? emulator;

  /// Server path of the state's screenshot (`screenshot.download_path`), if any.
  final String? screenshotUrl;

  /// Gargosy: the state's free-text labels (RomM 5.4+); Gargosy adds the
  /// RetroArch core that made it.
  final List<String> labels;

  /// Gargosy (#92): the owner shares it with every other user (`is_public`).
  final bool isPublic;

  const RommState({
    required this.id,
    required this.fileName,
    this.updatedAt,
    this.emulator,
    this.screenshotUrl,
    this.labels = const [],
    this.isPublic = false,
  });

  factory RommState.fromJson(Map<String, dynamic> json) {
    final screenshot = json['screenshot'];
    return RommState(
      id: (json['id'] as num).toInt(),
      fileName: json['file_name'].toString(),
      updatedAt: json['updated_at']?.toString(),
      emulator: json['emulator']?.toString(),
      screenshotUrl: screenshot is Map ? screenshot['download_path']?.toString() : null,
      labels: [for (final l in json['labels'] is List ? json['labels'] as List : const []) l.toString()],
      isPublic: json['is_public'] == true,
    );
  }
}

/// RomM answered 404 for a state id: the state was deleted on the server, or
/// the id belongs to a different RomM account than the one now logged in.
class RommStateNotFoundException implements Exception {
  final int stateId;
  const RommStateNotFoundException(this.stateId);

  @override
  String toString() => 'RomM state $stateId not found';
}

/// The slice of RomM's states API that state sync depends on. Kept narrow so
/// StateSyncService can be tested against an in-memory fake.
abstract class RommStatesApi {
  Future<List<RommState>> listStates(String romId);

  /// [emulator] is recorded as the state's `emulator` (RomM keeps the value it
  /// was created with; updates cannot change it). [screenshot] is stored as
  /// the state's screenshot.
  Future<RommState> uploadState(
    String romId,
    io.File file, {
    required String fileName,
    String? emulator,
    Uint8List? screenshot,
  });

  /// Throws [RommStateNotFoundException] if [stateId] no longer exists.
  Future<RommState> updateState(int stateId, io.File file, {required String fileName, Uint8List? screenshot});

  /// Throws [RommStateNotFoundException] if [stateId] no longer exists.
  Future<Uint8List> downloadState(int stateId);

  /// The screenshot at [url] (a [RommState.screenshotUrl]).
  Future<Uint8List> downloadStateScreenshot(String url);

  /// Gargosy: replaces [stateId]'s labels (`PUT /api/states/{id}/labels`).
  Future<RommState> setStateLabels(int stateId, List<String> labels);
}
