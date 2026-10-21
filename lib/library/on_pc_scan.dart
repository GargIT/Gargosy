import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_library_api.dart';
import '../core/romm/romm_models.dart';
import '../providers/download_providers.dart';
import '../providers/romm_providers.dart';
import 'library_snapshot.dart';
import 'rom_files.dart';

/// On this PC's Scan (#95): every game RomM has for [platformId], in pages
/// of [pageSize], checked against `roms\`; the ones there that the profile's
/// list ([snapshot]) doesn't have yet (another profile's downloads, files
/// put there by hand, downloads from before the list) are added in one
/// write. Returns how many were added. Throws when RomM can't be reached.
Future<int> scanPlatformOnPc({
  required LibraryApi api,
  required int platformId,
  required RomFiles files,
  required LibrarySnapshot snapshot,
  int pageSize = 500,
}) async {
  final query = GalleryQuery(platformId: platformId);
  final found = <Game>[];
  var offset = 0;
  while (true) {
    final page = await api.page(query, offset: offset, limit: pageSize);
    for (final g in page.games) {
      if (snapshot.find(g.id) == null && files.isDownloaded(g)) found.add(g);
    }
    offset += page.games.length;
    if (page.games.isEmpty || offset >= page.total) break;
  }
  if (found.isNotEmpty) await snapshot.rememberAll(found);
  return found.length;
}

/// Scans a platform for the active profile; the seam tests replace.
typedef PlatformScan = Future<int> Function(int platformId);

final platformScanProvider = Provider<PlatformScan?>((ref) {
  final api = ref.watch(libraryApiProvider);
  final snapshot = ref.watch(librarySnapshotProvider);
  if (api == null || snapshot == null) return null;
  final files = ref.watch(romFilesProvider);
  return (platformId) async {
    final n = await scanPlatformOnPc(api: api, platformId: platformId, files: files, snapshot: snapshot);
    // On this PC's list is read again.
    if (n > 0) ref.read(romFilesVersionProvider.notifier).state++;
    return n;
  };
});
