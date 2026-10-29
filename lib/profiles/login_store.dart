import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/security/secret_store.dart';
import 'json_file.dart';
import 'path_guard.dart';
import 'pc_identity.dart';

/// A profile's RomM token on this PC. [kind] is `device` (device pairing) or
/// `client-token` (made after a password login). The password is never kept.
/// [deviceId] is this PC as a RomM device: a paired login's own, or one
/// registered for a password login once the profile opens.
class ProfileLogin {
  const ProfileLogin({required this.token, required this.kind, this.deviceId});

  final String token;
  final String kind;
  final String? deviceId;

  ProfileLogin withDeviceId(String id) => ProfileLogin(token: token, kind: kind, deviceId: id);

  Map<String, dynamic> toJson() => {'token': token, 'kind': kind, if (deviceId != null) 'deviceId': deviceId};

  factory ProfileLogin.fromJson(Map<String, dynamic> json) =>
      ProfileLogin(token: json['token'] as String, kind: json['kind'] as String, deviceId: json['deviceId'] as String?);
}

/// `login.<PC>-<user>-<id>.dpapi` in a profile's folder: one file per PC and
/// Windows user, DPAPI-encrypted, so the folder can move between PCs and each
/// PC keeps its own login (spec §5).
class ProfileLoginStore {
  ProfileLoginStore({required this.profileDir, required this.secrets, required this.pc});

  final String profileDir;
  final SecretStore secrets;
  final PcIdentity pc;

  String get filePath => p.join(profileDir, 'login.${pc.loginFileTag}.dpapi');

  /// Synchronous file read on purpose (one tiny file; see ProfileStore.list).
  Future<ProfileLogin?> read() async {
    final file = io.File(filePath);
    if (!file.existsSync()) return null;
    final plain = secrets.unprotect(file.readAsBytesSync());
    if (plain == null) {
      debugPrint('[Login] ${p.basename(filePath)} cannot be decrypted here; log in again');
      return null;
    }
    try {
      return ProfileLogin.fromJson(jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
    } on Object catch (e) {
      debugPrint('[Login] ${p.basename(filePath)} is unreadable (${e.runtimeType}); log in again');
      return null;
    }
  }

  Future<void> write(PathGuard guard, ProfileLogin login) =>
      writeBytesAtomic(guard, filePath, secrets.protect(Uint8List.fromList(utf8.encode(jsonEncode(login.toJson())))));

  Future<void> clear(PathGuard guard) async {
    final file = io.File(guard.check(filePath));
    if (await file.exists()) await file.delete();
  }
}
