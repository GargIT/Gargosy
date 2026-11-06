import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/romm/install_request.dart';
import '../core/romm/romm_service.dart';
import '../library/remote_installs.dart';
import '../profiles/profile_providers.dart';
import 'download_providers.dart';
import 'engine_providers.dart';
import 'notification_providers.dart';
import 'romm_providers.dart';

/// Whether the open profile takes games sent from RomM's web page (#288).
class RemoteInstallSettingNotifier extends StateNotifier<bool> {
  RemoteInstallSettingNotifier(this._ref) : super(RemoteInstallSetting.of(_ref.read(profilePrefsProvider)));

  final Ref _ref;

  Future<void> set(bool on) async {
    state = on;
    await _ref.read(profilePrefsProvider)?.setBool(RemoteInstallSetting.key, on);
  }
}

final remoteInstallOnProvider = StateNotifierProvider<RemoteInstallSettingNotifier, bool>((ref) {
  ref.watch(profilePrefsProvider);
  return RemoteInstallSettingNotifier(ref);
});

class _RommInstallApi implements RemoteInstallApi {
  _RommInstallApi(this._romm, this._deviceId);

  final RommService _romm;
  final String _deviceId;

  @override
  Future<InstallClaim> claim() => _romm.claimInstalls(_deviceId);

  @override
  Future<void> report(String requestId, InstallOutcome outcome, {String? reason}) =>
      _romm.reportInstall(_deviceId, requestId, outcome, reason: reason);
}

/// The open profile's [RemoteInstalls], looking at RomM while it lasts: only
/// for a paired login (RomM lets only a token bound to the device claim) and
/// with the setting on. RomM is told whether this PC takes them either way.
/// Null when it doesn't run.
final remoteInstallsProvider = Provider<RemoteInstalls?>((ref) {
  // Only what decides it: an avatar or a rename doesn't start it again.
  final login = ref.watch(activeProfileProvider.select((c) => c == null ? null : (c.profile.id, c.login)));
  final romm = ref.watch(rommServiceProvider);
  final on = ref.watch(remoteInstallOnProvider);
  final deviceId = login?.$2.deviceId;
  if (romm == null || deviceId == null || login?.$2.kind != 'device') return null;
  unawaited(romm.setRemoteInstall(deviceId, on));
  if (!on) return null;
  final files = ref.read(romFilesProvider);
  final installs = RemoteInstalls(
    api: _RommInstallApi(romm, deviceId),
    gameOf: romm.getGame,
    download: (game) => ref.read(downloadsProvider.notifier).start(game),
    isOnPc: files.isDownloaded,
    installedAt: files.installedAt,
    errorOf: (game) => ref.read(downloadsProvider)[game.id]?.error,
    allows: (game) => ref.read(ageLimitProvider).allows(game),
    onStarted: (game) => ref.read(noticesProvider.notifier).post(Notice.sentFromRomm(game.id, game.displayName)),
    isOffline: () => ref.read(rommOfflineProvider),
  );
  ref.onDispose(installs.dispose);
  // No timers where RomM's heartbeat is off (tests), as the shell's notices.
  if (ref.watch(rommHeartbeatEnabledProvider)) installs.watch();
  return installs;
});

/// How the open profile's last look went, for Settings.
final remoteInstallStateProvider = Provider<RemoteInstallState?>((ref) {
  final installs = ref.watch(remoteInstallsProvider);
  if (installs == null) return null;
  void changed() => ref.invalidateSelf();
  installs.state.addListener(changed);
  ref.onDispose(() => installs.state.removeListener(changed));
  return installs.state.value;
});
