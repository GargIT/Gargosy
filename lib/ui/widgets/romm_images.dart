import 'dart:io' as io;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/io_client.dart';

import '../../core/romm/romm_models.dart';
import '../../providers/romm_providers.dart';

/// Whether to take [host]'s certificate though it doesn't check out: only
/// the profile's own RomM server, and only when the profile trusts its
/// self-signed certificate (as RomM's own requests do). IGDB and other
/// sites keep the normal checks.
bool trustCertificate(RomMConfig? config, String host) =>
    config != null && config.trustSelfSigned && Uri.tryParse(config.baseUrl)?.host == host;

/// Covers and platform logos: downloaded with the server's certificate
/// setting and kept on disk (under `userdata\app\`, through Gargosy's path
/// provider), so a restart shows them without asking RomM again.
final rommImageCacheProvider = Provider<BaseCacheManager>((ref) {
  // A new cache only for another server or trust setting, not each token refresh.
  ref.watch(rommServiceProvider.select((r) => (r?.config.baseUrl, r?.config.trustSelfSigned)));
  final http = io.HttpClient()
    ..badCertificateCallback = (cert, host, port) => trustCertificate(ref.read(rommServiceProvider)?.config, host);
  final manager = CacheManager(
    Config('gargosy-images', maxNrOfCacheObjects: 1000, fileService: HttpFileService(httpClient: IOClient(http))),
  );
  ref.onDispose(manager.dispose);
  return manager;
});
