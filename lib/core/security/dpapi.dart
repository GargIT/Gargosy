// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'secret_store.dart';

const _cryptProtectUiForbidden = 0x1;

/// DPAPI in user scope, never showing UI: only the same Windows user on
/// this PC reads it back. The PC is Windows' MachineGuid.
class DpapiSecretStore implements SecretStore {
  @override
  String? machineId() => readMachineGuid();

  @override
  Uint8List protect(Uint8List data) => _run(data, protect: true)!;

  @override
  Uint8List? unprotect(Uint8List data) => _run(data, protect: false);

  Uint8List? _run(Uint8List data, {required bool protect}) {
    return using((Arena arena) {
      final input = arena<Uint8>(data.isEmpty ? 1 : data.length);
      if (data.isNotEmpty) input.asTypedList(data.length).setAll(0, data);
      final inBlob = arena<CRYPT_INTEGER_BLOB>()
        ..ref.cbData = data.length
        ..ref.pbData = input;
      final outBlob = arena<CRYPT_INTEGER_BLOB>();
      final result = protect
          ? CryptProtectData(inBlob, null, null, null, _cryptProtectUiForbidden, outBlob)
          : CryptUnprotectData(inBlob, null, null, null, _cryptProtectUiForbidden, outBlob);
      if (!result.value) {
        if (protect) throw WindowsException(result.error.toHRESULT(), message: 'CryptProtectData failed');
        return null;
      }
      final out = outBlob.ref.pbData;
      if (out.address == 0) {
        if (protect) {
          throw WindowsException(ERROR_OUTOFMEMORY.toHRESULT(), message: 'CryptProtectData returned no data');
        }
        return null;
      }
      try {
        return Uint8List.fromList(out.asTypedList(outBlob.ref.cbData));
      } finally {
        LocalFree(HLOCAL(out));
      }
    });
  }
}

/// Windows' per-install machine id, or null if it can't be read.
String? readMachineGuid() {
  return using((Arena arena) {
    final subKey = r'SOFTWARE\Microsoft\Cryptography'.toNativeUtf16(allocator: arena);
    final value = 'MachineGuid'.toNativeUtf16(allocator: arena);
    final size = arena<Uint32>()..value = 256;
    final buffer = arena<Uint8>(256);
    final result = RegGetValue(
      HKEY_LOCAL_MACHINE,
      PCWSTR(subKey),
      PCWSTR(value),
      RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY,
      null,
      buffer,
      size,
    );
    if (result != ERROR_SUCCESS) return null;
    return buffer.cast<Utf16>().toDartString();
  });
}
