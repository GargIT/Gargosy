import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/platform/platform_info.dart';
import '../core/security/secret_store.dart';

/// This PC and its user. A [SecretStore] only decrypts for the same user on
/// the same PC, so each login file is named after both.
class PcIdentity {
  const PcIdentity({required this.machineName, required this.userName, required this.machineId});

  final String machineName;
  final String userName;
  final String machineId;

  static PcIdentity current(SecretStore secrets) {
    final env = PlatformInfo.current.environment;
    final machine = env['COMPUTERNAME'] ?? 'PC';
    return PcIdentity(
      machineName: machine,
      userName: env['USERNAME'] ?? 'user',
      machineId: secrets.machineId() ?? machine,
    );
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[<>:"/\\|?*.\s]'), '_');

  String get loginFileTag {
    final id = sha256.convert(utf8.encode('$machineId\n$userName')).toString().substring(0, 8);
    return '${_safe(machineName)}-${_safe(userName)}-$id';
  }
}
