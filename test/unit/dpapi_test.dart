import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/security/dpapi.dart';
import 'package:gargosy/core/security/secret_store.dart';
import 'package:gargosy/core/storage/secure_storage_service.dart';
import 'package:gargosy/profiles/pc_identity.dart';

import '../helpers/fake_secret_store.dart';
import '../helpers/profile_test_env.dart';

void main() {
  test('DPAPI protects and unprotects for the current Windows user', () {
    final secrets = DpapiSecretStore();
    final data = Uint8List.fromList('secret'.codeUnits);
    final protected = secrets.protect(data);
    expect(protected, isNot(data));
    expect(secrets.unprotect(protected), data);
  });

  test('data that is not DPAPI output is refused, not thrown', () {
    expect(DpapiSecretStore().unprotect(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('MachineGuid is read from the registry', () {
    expect(readMachineGuid(), matches(RegExp(r'^[0-9a-fA-F-]{36}$')));
  });

  test("DPAPI's store is bound to the MachineGuid", () {
    expect(DpapiSecretStore().machineId(), readMachineGuid());
  });

  group('secretStoreFor (#198)', () {
    test('Windows gets DPAPI', () {
      expect(secretStoreFor(const PlatformInfo('windows')), isA<DpapiSecretStore>());
    });

    test('an OS without a store yet is refused, not given DPAPI', () {
      expect(() => secretStoreFor(const PlatformInfo('linux')), throwsUnsupportedError);
    });
  });

  test("a login file is named after the store's machine id", () {
    final a = PcIdentity.current(FakeSecretStore());
    expect(a.machineId, 'test-machine');
  });

  test('SecureStorageService encrypts with the store it is given', () async {
    final store = FakeSecretStore();
    final prefs = MemoryPrefs();
    final secure = SecureStorageService(store);
    await secure.write('k', 'token', prefs);
    expect(prefs.getString('secure.k'), isNot(contains('token')));
    expect(await secure.read('k', prefs), 'token');
    store.fail = true;
    expect(await secure.read('k', prefs), isNull);
  });
}
