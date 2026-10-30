import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/retroachievements/retroachievements_emulator_login.dart';
import '../core/retroachievements/retroachievements_service.dart';
import '../core/security/secret_store.dart';
import '../core/storage/app_preferences.dart';
import '../core/storage/secure_storage_service.dart';
import '../profiles/profile_providers.dart';
import '../providers/engine_providers.dart';

typedef RaTokenFetcher = Future<({String username, String token})> Function(String username, String password);

/// The profile's RetroAchievements login, as the emulators use it (spec §2
/// Settings). The password is exchanged once for RA's Connect token and
/// never stored; the token is kept DPAPI-protected in the profile's prefs.
/// RetroArch signs in with it at launch (`--appendconfig`).
class RaAccount {
  RaAccount(this._prefs, {required SecretStore secrets, required this.fetchToken, this.signOutEmulators})
    : _secure = SecureStorageService(secrets);

  final AppPreferences _prefs;
  final SecureStorageService _secure;

  /// Exchanges the password for RA's Connect token.
  final RaTokenFetcher fetchToken;

  /// Takes the login out of the profile's emulator settings (RetroArch's
  /// and PCSX2's keep it once written).
  final Future<void> Function()? signOutEmulators;

  /// Null when no account is connected.
  String? get username {
    final u = _prefs.getString(kRaUsernameKey);
    return u == null || u.isEmpty ? null : u;
  }

  bool get hardcore => _prefs.getBool(kRaHardcoreKey) ?? false;

  /// Throws RetroAchievementsAuthException when RA refuses; nothing is
  /// stored then.
  Future<void> connect(String username, String password) async {
    final r = await fetchToken(username.trim(), password);
    await _secure.write(kRaConnectTokenSecureKey, r.token, _prefs);
    await _prefs.setString(kRaUsernameKey, r.username);
  }

  Future<void> setHardcore(bool on) => _prefs.setBool(kRaHardcoreKey, on);

  Future<void> disconnect() async {
    await _prefs.remove(kRaUsernameKey);
    await _secure.delete(kRaConnectTokenSecureKey, _prefs);
    await RetroAchievementsEmulatorLogin.deleteEmulatorFiles();
    await signOutEmulators?.call();
  }
}

/// The active profile's account; null without a profile.
final raAccountProvider = Provider<RaAccount?>((ref) {
  final prefs = ref.watch(profilePrefsProvider);
  if (prefs == null) return null;
  final dirs = ref.watch(launchDirectoriesProvider);
  return RaAccount(
    prefs,
    // The store the launch reads the token with.
    secrets: dirs?.secrets ?? ref.watch(secretStoreProvider),
    fetchToken: (u, p) => RetroAchievementsService().fetchConnectToken(u, p),
    signOutEmulators: dirs == null ? null : () async => dirs.signOutRetroAchievements(),
  );
});
