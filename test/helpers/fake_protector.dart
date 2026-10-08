import 'dart:typed_data';

import 'package:gargosy/core/security/dpapi.dart';

/// Reversible "encryption" for tests; [fail] makes unprotect behave like
/// DPAPI on another PC.
class FakeProtector implements DataProtector {
  bool fail = false;
  @override
  Uint8List protect(Uint8List data) => Uint8List.fromList([for (final b in data) b ^ 0x5A]);
  @override
  Uint8List? unprotect(Uint8List data) => fail ? null : Uint8List.fromList([for (final b in data) b ^ 0x5A]);
}
