import 'dart:convert';
import 'dart:typed_data';

import '../platform/platform_info.dart';
import '../security/secret_store.dart';
import 'app_preferences.dart';

/// Freegosy's SecureStorageService API, kept so copied code compiles, but
/// portable: a secret is encrypted by the OS's [SecretStore] and kept in the [AppPreferences]
/// given, which in Gargosy are the profile's own. On another PC the value
/// can't be decrypted and reads as missing, so that profile signs in again
/// (spec §5).
class SecureStorageService {
  static SecretStore? _configured;
  static SecretStore get _store => _configured ??= secretStoreFor(PlatformInfo.current);

  /// [secrets], else [platform]'s store; by default the running OS's.
  static void configure({PlatformInfo? platform, SecretStore? secrets}) {
    if (secrets != null) {
      _configured = secrets;
    } else if (platform != null) {
      _configured = secretStoreFor(platform);
    }
  }

  static String _key(String key) => 'secure.$key';

  static Future<String?> read(String key, AppPreferences prefs) async {
    final stored = prefs.getString(_key(key));
    if (stored == null) return null;
    try {
      final plain = _store.unprotect(base64Decode(stored));
      return plain == null ? null : utf8.decode(plain);
    } on FormatException {
      return null;
    }
  }

  static Future<void> write(String key, String value, AppPreferences prefs) async {
    final cipher = _store.protect(Uint8List.fromList(utf8.encode(value)));
    await prefs.setString(_key(key), base64Encode(cipher));
  }

  static Future<void> delete(String key, AppPreferences prefs) async {
    await prefs.remove(_key(key));
  }
}
