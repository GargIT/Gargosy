import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_library_api.dart';
import '../core/romm/romm_models.dart';
import '../core/romm/romm_service.dart';
import '../core/romm/server_error_retry.dart';
import '../profiles/profile_providers.dart';

/// The active profile's RomM client (spec §4: every RomM call goes through the
/// profile's own session). Rebuilt only when the server or token changes.
final rommServiceProvider = Provider<RommService?>((ref) {
  final key = ref.watch(activeProfileProvider.select((c) =>
      c == null ? null : (c.profile.serverUrl, c.login.token, c.profile.trustSelfSigned)));
  if (key == null) return null;
  final (url, token, trust) = key;
  final service = RommService(
    RomMConfig(baseUrl: url, username: '', password: '', token: token, trustSelfSigned: trust),
    skipConnectivityCheck: true,
  );
  // A read RomM answers with a passing server error is asked again.
  service.dio.interceptors.add(ServerErrorRetry(service.dio));
  ref.onDispose(service.stopHeartbeat);
  return service;
});

/// Gallery, collections and favourites for the active profile.
final libraryApiProvider = Provider<LibraryApi?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  return romm == null ? null : RommLibraryApi(romm.dio, () => romm.authOptions);
});

/// Whether RomM's heartbeat runs (every 5 s). Off in tests: no timers.
final rommHeartbeatEnabledProvider = Provider<bool>((ref) => true);

/// RomM can't be reached (its heartbeat fails). Starts the heartbeat.
final rommOfflineProvider = Provider<bool>((ref) {
  final romm = ref.watch(rommServiceProvider);
  if (romm == null) return false;
  if (ref.watch(rommHeartbeatEnabledProvider)) romm.startHeartbeat();
  void changed() => ref.invalidateSelf();
  romm.isOffline.addListener(changed);
  ref.onDispose(() => romm.isOffline.removeListener(changed));
  return romm.isOffline.value;
});
