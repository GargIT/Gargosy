import 'dart:ffi';
import 'dart:io' as io;

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// The sigil version the bindings in sigil_bindings.dart were written for
/// (the submodule's tag). Another version's structs may differ, so its
/// library is refused rather than read wrongly.
const sigilPinnedVersion = '1.0.0';

/// sigil.dll could not be used: not built, not beside Gargosy.exe, or
/// another version than Gargosy was built for.
class SigilUnavailable implements Exception {
  const SigilUnavailable(this.path, this.reason);
  final String path;
  final String reason;

  @override
  String toString() => 'sigil.dll could not be used from $path ($reason)';
}

/// Where argosy-sigil's library is: beside Gargosy.exe (the Windows build
/// installs it there), or what [path] says (tests point it at a build).
abstract final class SigilLibrary {
  static String? path;

  static String get resolvedPath => path ?? p.join(p.dirname(io.Platform.resolvedExecutable), 'sigil.dll');

  /// Libraries whose version was checked in this isolate.
  static final _checked = <String>{};

  /// The library, checked once per isolate to be [sigilPinnedVersion].
  static DynamicLibrary open() {
    final file = resolvedPath;
    final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open(file);
    } on ArgumentError catch (e) {
      throw SigilUnavailable(file, '${e.message}');
    }
    if (_checked.add(file)) {
      try {
        checkVersion(file, _version(lib));
      } catch (_) {
        _checked.remove(file);
        rethrow;
      }
    }
    return lib;
  }

  /// Why the library can't be used, null when it can (checked at start: Gargosy
  /// doesn't run without it, #57).
  static SigilUnavailable? problem() {
    try {
      open();
      return null;
    } on SigilUnavailable catch (e) {
      return e;
    }
  }

  /// Throws unless [reported] is the version Gargosy's bindings fit.
  static void checkVersion(String file, String reported) {
    if (reported != sigilPinnedVersion) {
      throw SigilUnavailable(file, 'it is sigil $reported; Gargosy was built for sigil $sigilPinnedVersion');
    }
  }
}

String _version(DynamicLibrary lib) =>
    lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('sigil_version')().toDartString();

/// sigil's version, as `sigil_version()` reports it.
String sigilVersion() => _version(SigilLibrary.open());
