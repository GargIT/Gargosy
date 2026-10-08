import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/security/dpapi.dart';

void main() {
  test('DPAPI protects and unprotects for the current Windows user', () {
    final protector = DpapiDataProtector();
    final data = Uint8List.fromList('secret'.codeUnits);
    final protected = protector.protect(data);
    expect(protected, isNot(data));
    expect(protector.unprotect(protected), data);
  });

  test('data that is not DPAPI output is refused, not thrown', () {
    expect(DpapiDataProtector().unprotect(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('MachineGuid is read from the registry', () {
    expect(readMachineGuid(), matches(RegExp(r'^[0-9a-fA-F-]{36}$')));
  });
}
