import 'dart:convert';
import 'dart:typed_data';

import '../security/secret_store.dart';
import 'app_preferences.dart';

/// Freegosy's SecureStorageService, kept for the copied code, but portable:
/// a secret is encrypted by the [SecretStore] it's given (`secretStoreProvider`'s,
/// the one source) and kept in the [AppPreferences] given, which in Gargosy
/// are the profile's own. On another PC the value can't be decrypted and
/// reads as missing, so that profile signs in again (spec §5).
class SecureStorageService {
  const SecureStorageService(this.secrets);

  final SecretStore secrets;

  static String _key(String key) => 'secure.$key';

  Future<String?> read(String key, AppPreferences prefs) async {
    final stored = prefs.getString(_key(key));
    if (stored == null) return null;
    try {
      final plain = secrets.unprotect(base64Decode(stored));
      return plain == null ? null : utf8.decode(plain);
    } on FormatException {
      return null;
    }
  }

  Future<void> write(String key, String value, AppPreferences prefs) async {
    final cipher = secrets.protect(Uint8List.fromList(utf8.encode(value)));
    await prefs.setString(_key(key), base64Encode(cipher));
  }

  Future<void> delete(String key, AppPreferences prefs) async {
    await prefs.remove(_key(key));
  }
}
