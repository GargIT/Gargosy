import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'sigil_bindings.dart';
import 'sigil_library.dart';
import 'sigil_platforms.dart';
import 'sigil_sync.dart';

/// What sigil read from a ROM: the game's own id (`SLUS-20152`), as the
/// binary spells it (`SLUS_201.52`), and the name its saves go under.
class SigilId {
  const SigilId({
    required this.titleId,
    required this.rawSerial,
    required this.saveId,
    required this.platform,
    required this.fromBinary,
    this.usage = 0,
  });

  final String titleId;
  final String rawSerial;
  final String saveId;

  /// sigil's platform slug (`ps2`, `psx`, `gamecube`, …).
  final String platform;

  /// Read from the ROM's contents (false: from its file name).
  final bool fromBinary;

  /// How the saves are laid out (sigil_usage: folder-exact 0, folder-prefix 1,
  /// file-exact 2, file-prefix 3, folder-split 4).
  final int usage;

  @override
  String toString() => 'SigilId($platform $titleId${fromBinary ? '' : ', from the file name'})';
}

/// sigil refused for a reason other than "this isn't something it reads".
class SigilException implements Exception {
  const SigilException(this.code, this.message);
  final int code;
  final String message;

  @override
  String toString() => 'sigil: $message ($code)';
}

/// argosy-sigil, called off the UI isolate: each call runs in a background
/// isolate (sigil reads files and blocks), which opens the library itself.
abstract final class SigilEngine {
  /// sigil's version (`sigil_version`).
  static Future<String> version() {
    final lib = SigilLibrary.resolvedPath;
    return Isolate.run(() {
      SigilLibrary.path = lib;
      return sigilVersion();
    });
  }

  /// Gathers [call]'s game's saves into the unit that travels to RomM.
  static Future<SigilCollected> collect(SigilSyncCall call) {
    final lib = SigilLibrary.resolvedPath;
    return Isolate.run(() => runSigilSync(lib, call, null) as SigilCollected);
  }

  /// Puts [unit] back for [call]'s game. A local change since the last sync
  /// without [SigilSyncCall.overwriteLocal] is a [SigilSyncError] (code -9).
  static Future<SigilRestored> restore(SigilSyncCall call, Uint8List unit) {
    final lib = SigilLibrary.resolvedPath;
    return Isolate.run(() => runSigilSync(lib, call, unit) as SigilRestored);
  }

  /// The game id in the ROM at [path]; [platform] is RomM's slug (mapped to
  /// sigil's; unknown → sigil guesses from the extension). Null when sigil
  /// reads nothing there: not a game it knows, no id, not a file.
  static Future<SigilId?> identify(String path, {String? platform}) {
    final lib = SigilLibrary.resolvedPath;
    final sigilPlatform = platform == null ? null : (sigilPlatformFor(platform) ?? platform);
    return Isolate.run(() => _identify(lib, path, sigilPlatform));
  }
}

/// Codes that mean "nothing to read here", not a failure.
const _nothing = {sigilErrNotFound, sigilErrUnsupportedFormat, sigilErrUnknownPlatform, sigilErrIo};

SigilId? _identify(String lib, String path, String? platform) {
  SigilLibrary.path = lib;
  final dll = SigilLibrary.open();
  final extract = dll.lookupFunction<SigilExtractNative, SigilExtract>('sigil_extract_from_path');
  final fromSlug = dll.lookupFunction<SigilPlatformFromSlugNative, SigilPlatformFromSlug>('sigil_platform_from_slug');
  final toSlug = dll.lookupFunction<SigilPlatformToSlugNative, SigilPlatformToSlug>('sigil_platform_to_slug');
  final strerror = dll.lookupFunction<SigilStrerrorNative, SigilStrerror>('sigil_strerror');
  return using((arena) {
    final hint = platform == null ? 0 : fromSlug(platform.toNativeUtf8(allocator: arena));
    final nativePath = path.toNativeUtf8(allocator: arena);
    // Room for a bigger sigil_result than the bindings know: a sigil that
    // grew it can't write past the buffer before struct_version is checked.
    final out = arena.allocate<Uint8>(_resultRoom).cast<SigilResult>();
    var code = extract(nativePath, hint, nullptr, out);
    // sigil cooks raw 2352-byte .bin sectors itself only for PS1 and
    // Dreamcast; a PS2 CD as a raw BIN (Redump) goes through its raw-CD reader.
    if (code == sigilErrNotFound && platform == 'ps2' && path.toLowerCase().endsWith('.bin')) {
      code = _extractRawCd(dll, nativePath, hint, out, arena);
    }
    if (_nothing.contains(code)) return null;
    if (code != sigilOk) throw SigilException(code, strerror(code).toDartString());
    final r = out.ref;
    if (r.structVersion != sigilResultV4) {
      throw SigilException(sigilErrInvalidArg, 'sigil_result is version ${r.structVersion}, not $sigilResultV4');
    }
    if (r.titleIdText.isEmpty) return null;
    return SigilId(
      titleId: r.titleIdText,
      rawSerial: r.rawSerialText,
      saveId: r.saveIdText,
      platform: toSlug(r.platform).toDartString(),
      fromBinary: r.source == sigilSourceBinary,
      usage: r.usage,
    );
  });
}

const _resultRoom = 1024;

/// [path] read through `sigil_io_open_raw_cd`; NOT_FOUND when it isn't a raw CD.
int _extractRawCd(DynamicLibrary dll, Pointer<Utf8> path, int hint, Pointer<SigilResult> out, Arena arena) {
  final open = dll.lookupFunction<SigilIoOpenNative, SigilIoOpen>('sigil_io_open_raw_cd');
  final close = dll.lookupFunction<SigilIoCloseNative, SigilIoClose>('sigil_io_close');
  final fromIo = dll.lookupFunction<SigilExtractFromIoNative, SigilExtractFromIo>('sigil_extract_from_io');
  final io = open(path);
  if (io == nullptr) return sigilErrNotFound;
  try {
    return fromIo(io, path, hint, nullptr, out);
  } finally {
    close(io);
  }
}
