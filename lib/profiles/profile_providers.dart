import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_auth_client.dart';
import '../core/platform/platform_info.dart';
import '../core/security/secret_store.dart';
import '../core/storage/app_preferences.dart';
import 'app_root.dart';
import 'avatar_refresh.dart';
import 'login_store.dart';
import 'path_guard.dart';
import 'pc_identity.dart';
import 'pin.dart';
import 'profile.dart';
import 'profile_paths.dart';
import 'profile_store.dart';

final appRootProvider = Provider<AppRoot>((ref) => throw UnimplementedError('overridden in main'));
final appPreferencesProvider = Provider<AppPreferences>((ref) => throw UnimplementedError('overridden in main'));
final secretStoreProvider = Provider<SecretStore>((ref) => secretStoreFor(PlatformInfo.current));
final pcIdentityProvider = Provider<PcIdentity>((ref) => PcIdentity.current(ref.watch(secretStoreProvider)));
final rommAuthFactoryProvider = Provider<RommAuth Function(String baseUrl, bool trustSelfSigned)>(
  (ref) =>
      (url, trust) => RommAuthClient(url, trustSelfSigned: trust),
);

final profileStoreProvider = Provider<ProfileStore>(
  (ref) => ProfileStore(ref.watch(appRootProvider), ref.watch(appPreferencesProvider)),
);
final profilesProvider = FutureProvider<List<Profile>>((ref) => ref.watch(profileStoreProvider).list());

/// PIN lockouts per profile, for as long as Gargosy runs.
final pinGatesProvider = Provider<Map<String, PinGate>>((ref) => {});

ProfileLoginStore _loginStore(AppRoot root, SecretStore secrets, PcIdentity pc, Profile p) =>
    ProfileLoginStore(profileDir: ProfilePaths(root, p.id).dir, secrets: secrets, pc: pc);

ProfileLoginStore loginStoreFor(Ref ref, Profile p) =>
    _loginStore(ref.read(appRootProvider), ref.read(secretStoreProvider), ref.read(pcIdentityProvider), p);

ProfileLoginStore loginStoreForWidget(WidgetRef ref, Profile p) =>
    _loginStore(ref.read(appRootProvider), ref.read(secretStoreProvider), ref.read(pcIdentityProvider), p);

/// The profile in use: the only source of paths and of the RomM session (spec §4).
class ProfileContext {
  const ProfileContext({required this.profile, required this.paths, required this.guard, required this.login});

  final Profile profile;
  final ProfilePaths paths;
  final PathGuard guard;
  final ProfileLogin login;
}

class ActiveProfileNotifier extends StateNotifier<ProfileContext?> {
  ActiveProfileNotifier(this._ref) : super(null);

  final Ref _ref;

  /// The background avatar check started by the last [activate].
  @visibleForTesting
  Future<void> avatarRefresh = Future.value();

  Future<void> activate(Profile profile, ProfileLogin login) async {
    final paths = ProfilePaths(_ref.read(appRootProvider), profile.id);
    await _ref.read(profileStoreProvider).setLastUsed(profile.id);
    state = ProfileContext(profile: profile, paths: paths, guard: paths.guard, login: login);
    avatarRefresh = _refreshAvatar(profile, login, paths);
  }

  /// Picks up an avatar added or changed in RomM since the profile was made.
  /// Offline or failing, the profile simply keeps its picture.
  Future<void> _refreshAvatar(Profile profile, ProfileLogin login, ProfilePaths paths) async {
    try {
      final updated = await refreshAvatar(
        profile: profile,
        login: login,
        auth: _ref.read(rommAuthFactoryProvider)(profile.serverUrl, profile.trustSelfSigned),
        store: _ref.read(profileStoreProvider),
        paths: paths,
      );
      if (updated == null || !mounted) return;
      final current = state;
      if (current != null && current.profile.id == profile.id) {
        state = ProfileContext(profile: updated, paths: current.paths, guard: current.guard, login: current.login);
      }
      _ref.invalidate(profilesProvider);
    } on Object catch (e) {
      debugPrint('[Profiles] Avatar check for ${profile.id} failed: $e');
    }
  }

  /// Keeps [deviceId], this PC as a RomM device, in [profileId]'s login on
  /// this PC (not in the profile's settings: the folder moves between PCs).
  Future<void> setDeviceId(String profileId, String deviceId) async {
    final current = state;
    if (current == null || current.profile.id != profileId) return;
    final login = current.login.withDeviceId(deviceId);
    await loginStoreFor(_ref, current.profile).write(current.guard, login);
    if (!mounted || state?.profile.id != profileId) return;
    state = ProfileContext(profile: state!.profile, paths: current.paths, guard: current.guard, login: login);
  }

  /// Back to the profile picker. The login stays on this PC.
  void signOut() => state = null;

  /// Saves [profile] (renamed, PIN changed) and keeps it open.
  Future<void> update(Profile profile) async {
    final current = state;
    if (current == null || current.profile.id != profile.id) return;
    await _ref.read(profileStoreProvider).save(profile);
    if (!mounted) return;
    state = ProfileContext(profile: profile, paths: current.paths, guard: current.guard, login: current.login);
    _ref.invalidate(profilesProvider);
  }
}

final activeProfileProvider = StateNotifierProvider<ActiveProfileNotifier, ProfileContext?>(
  (ref) => ActiveProfileNotifier(ref),
);
