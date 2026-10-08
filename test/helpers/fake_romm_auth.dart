import 'dart:typed_data';

import 'package:gargosy/core/romm/romm_auth_client.dart';

/// A scripted [RommAuth]. Each item in [polls] is a [DevicePoll] to return or
/// a [RommAuthException] to throw, in order.
class FakeRommAuth implements RommAuth {
  FakeRommAuth({
    this.polls = const [],
    this.start,
    this.me = const RommUser(id: 7, username: 'anna', avatarPath: '', oauthScopes: []),
    this.passwordToken = 'rmm_pw',
    this.startError,
    this.passwordError,
    this.avatar,
  });

  /// What [fetchAvatar] returns; null is "no avatar".
  Uint8List? avatar;

  final List<Object> polls;
  final DeviceAuthStart? start;
  RommUser me;
  final String passwordToken;
  final RommAuthException? startError;
  final RommAuthException? passwordError;
  int pollCount = 0;
  final passwordLogins = <String>[];

  @override
  Future<DeviceAuthStart?> startDeviceAuth({required String deviceIdentifier, required String deviceName}) async {
    if (startError != null) throw startError!;
    return start;
  }

  @override
  Future<DevicePoll> pollDeviceAuth(String deviceCode) async {
    final next = polls[pollCount++];
    if (next is RommAuthException) throw next;
    return next as DevicePoll;
  }

  @override
  Future<String> loginWithPassword(
      {required String username, required String password, required String tokenName, int? expectedUserId}) async {
    if (passwordError != null) throw passwordError!;
    if (expectedUserId != null && me.id != expectedUserId) {
      throw RommAuthException(RommAuthFailure.wrongUser, me.username);
    }
    passwordLogins.add(username);
    return passwordToken;
  }

  @override
  Future<RommUser> fetchMe(String token) async => me;

  @override
  Future<Uint8List?> fetchAvatar(String token, int userId) async => avatar;
}
