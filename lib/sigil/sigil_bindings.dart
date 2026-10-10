// Hand-written bindings for the parts of argosy-sigil's C API (include/sigil.h,
// v1.0.0) that Gargosy calls. Struct layouts are pinned against MSVC's (x64) in
// test/unit/sigil_bindings_test.dart: a field typed wrong fails there, not in
// memory. Only lib/sigil/ uses these.
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

const sigilResultV4 = 4;

const sigilOk = 0;
const sigilErrInvalidArg = -1;
const sigilErrIo = -2;
const sigilErrUnknownPlatform = -3;
const sigilErrUnsupportedFormat = -4;
const sigilErrNotFound = -5;
const sigilErrNeedsKey = -6;
const sigilErrCrypto = -7;
const sigilErrOom = -8;
const sigilErrConflict = -9;
const sigilErrExists = -10;
const sigilErrNoSpace = -11;
const sigilErrUncollected = -12;
const sigilErrDamaged = -13;
const sigilErrRegion = -14;
const sigilErrNoTarget = -15;
const sigilErrAmbiguous = -16;
const sigilErrKeysIncompatible = -17;

/// `sigil_source`: where the id came from.
const sigilSourceBinary = 0;
const sigilSourceFilename = 1;

/// The text in a fixed `char[n]` field, up to its first NUL (UTF-8).
String sigilText(Array<Uint8> field, int length) {
  final bytes = <int>[];
  for (var i = 0; i < length; i++) {
    final b = field[i];
    if (b == 0) break;
    bytes.add(b);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// `sigil_result`: what identification read from a ROM.
final class SigilResult extends Struct {
  @Uint32()
  external int structVersion;

  @Array(32)
  external Array<Uint8> titleId;

  @Array(32)
  external Array<Uint8> rawSerial;

  @Array(32)
  external Array<Uint8> saveId;

  /// `sigil_platform`.
  @Int32()
  external int platform;

  /// `sigil_source`.
  @Int32()
  external int source;

  /// `sigil_usage`.
  @Int32()
  external int usage;

  @Int32()
  external int experimental;

  @Int32()
  external int switchContentType;

  @Uint32()
  external int titleVersion;

  @Uint32()
  external int features;

  @Array(24)
  external Array<Uint8> n64Header;

  @Array(33)
  external Array<Uint8> n64Md5;

  @Array(33)
  external Array<Uint8> n64Md5N64;

  String get titleIdText => sigilText(titleId, 32);
  String get rawSerialText => sigilText(rawSerial, 32);
  String get saveIdText => sigilText(saveId, 32);
}

/// `int sigil_extract_from_path(const char *path, sigil_platform hint, const sigil_options *opts, sigil_result *out)`.
typedef SigilExtractNative = Int32 Function(
  Pointer<Utf8> path,
  Int32 hint,
  Pointer<Void> opts,
  Pointer<SigilResult> out,
);
typedef SigilExtract = int Function(Pointer<Utf8> path, int hint, Pointer<Void> opts, Pointer<SigilResult> out);

/// `sigil_platform sigil_platform_from_slug(const char *slug)`.
typedef SigilPlatformFromSlugNative = Int32 Function(Pointer<Utf8> slug);
typedef SigilPlatformFromSlug = int Function(Pointer<Utf8> slug);

/// `const char *sigil_platform_to_slug(sigil_platform p)`.
typedef SigilPlatformToSlugNative = Pointer<Utf8> Function(Int32 platform);
typedef SigilPlatformToSlug = Pointer<Utf8> Function(int platform);

/// `const char *sigil_strerror(int code)`.
typedef SigilStrerrorNative = Pointer<Utf8> Function(Int32 code);
typedef SigilStrerror = Pointer<Utf8> Function(int code);

/// `int sigil_extract_from_io(const sigil_io *io, const char *filename_hint, sigil_platform hint,
/// const sigil_options *opts, sigil_result *out)`.
typedef SigilExtractFromIoNative = Int32 Function(
  Pointer<Void> io,
  Pointer<Utf8> filenameHint,
  Int32 hint,
  Pointer<Void> opts,
  Pointer<SigilResult> out,
);
typedef SigilExtractFromIo = int Function(
  Pointer<Void> io,
  Pointer<Utf8> filenameHint,
  int hint,
  Pointer<Void> opts,
  Pointer<SigilResult> out,
);

/// `sigil_io *sigil_io_open_raw_cd(const char *path)`: a raw 2352-byte CD
/// image presented as 2048-byte sectors; null when it isn't one.
typedef SigilIoOpenNative = Pointer<Void> Function(Pointer<Utf8> path);
typedef SigilIoOpen = Pointer<Void> Function(Pointer<Utf8> path);

/// `void sigil_io_close(sigil_io *io)`.
typedef SigilIoCloseNative = Void Function(Pointer<Void> io);
typedef SigilIoClose = void Function(Pointer<Void> io);

// ---- Sync (sigil.h "Save units" and "Sync"), stage 2 ----

const sigilSaveRequestV1 = 1;
const sigilSyncRequestV1 = 1;
const sigilSyncResultV1 = 1;
const sigilSyncUnmanaged = 1;
const sigilCardNameMax = 64;

/// `sigil_save_option`: a core option or setting that changes file names.
final class SigilSaveOption extends Struct {
  external Pointer<Utf8> key;
  external Pointer<Utf8> value;
}

/// `sigil_save_request`: the emulator, content, options and save root.
final class SigilSaveRequest extends Struct {
  @Uint32()
  external int structVersion;
  external Pointer<Utf8> layout;
  external Pointer<Utf8> platform;
  external Pointer<Utf8> contentPath;
  external Pointer<SigilResult> result;
  @Uint32()
  external int features;
  external Pointer<SigilSaveOption> options;
  @Size()
  external int optionCount;
  external Pointer<Pointer<Utf8>> listing;
  @Size()
  external int listingCount;
  external Pointer<NativeFunction<SigilSaveOpenFn>> open;
  external Pointer<Void> openCtx;
  external Pointer<Utf8> rootPath;
  external Pointer<Utf8> profile;
}

/// `sigil_sync_request`.
final class SigilSyncRequest extends Struct {
  @Uint32()
  external int structVersion;
  external SigilSaveRequest save;
  external Pointer<Pointer<Utf8>> gameIds;
  @Size()
  external int gameIdCount;
  @Int32()
  external int mode;
  external Pointer<Uint8> state;
  @Size()
  external int stateLen;
  @Int32()
  external int overwriteLocal;
  external Pointer<NativeFunction<SigilSaveWriteFn>> write;
  external Pointer<Void> writeCtx;
  external Pointer<Pointer<Utf8>> claimed;
  @Size()
  external int claimedCount;
  external Pointer<NativeFunction<SigilSaveRemoveFn>> remove;
  external Pointer<Void> companions;
  @Size()
  external int companionCount;
  @Int32()
  external int repair;
}

/// `sigil_sync_companion_result`.
final class SigilSyncCompanionResult extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int len;
  @Array(33)
  external Array<Uint8> contentHash;
  @Array(33)
  external Array<Uint8> identityHash;
  @Int32()
  external int changed;
}

/// `sigil_sync_result`.
final class SigilSyncResult extends Struct {
  @Uint32()
  external int structVersion;
  @Array(256)
  external Array<Uint8> artifact;
  @Int32()
  external int shape;
  external Pointer<Uint8> data;
  @Size()
  external int len;
  @Array(33)
  external Array<Uint8> contentHash;
  @Array(33)
  external Array<Uint8> identityHash;
  @Int32()
  external int changed;
  @Int32()
  external int conflict;
  external Pointer<Uint8> state;
  @Size()
  external int stateLen;
  external Pointer<Uint8> holding;
  @Size()
  external int holdingLen;

  /// `char (*)[64]`: [unownedCount] names, 64 bytes each.
  external Pointer<Uint8> unowned;
  @Size()
  external int unownedCount;
  @Int32()
  external int restoreAgain;
  external Pointer<SigilSyncCompanionResult> companions;
  @Size()
  external int companionCount;
  @Array(512)
  external Array<Uint8> problem;
  @Uint32()
  external int blocksShort;
  external Pointer<Void> profiles;
  @Size()
  external int profileCount;
  @Array(64)
  external Array<Uint8> profile;
  external Pointer<Void> alternates;
  @Size()
  external int alternateCount;
  @Int32()
  external int hardcoreMarker;
  @Size()
  external int unownedChanged;
}

/// `sigil_io *(*)(void *ctx, const char *relative_path)`.
typedef SigilSaveOpenFn = Pointer<Void> Function(Pointer<Void> ctx, Pointer<Utf8> relativePath);

/// `int (*)(void *ctx, const char *relative_path, const uint8_t *data, size_t len)`.
typedef SigilSaveWriteFn = Int32 Function(Pointer<Void> ctx, Pointer<Utf8> relativePath, Pointer<Uint8> data, Size len);

/// `int (*)(void *ctx, const char *relative_path)`.
typedef SigilSaveRemoveFn = Int32 Function(Pointer<Void> ctx, Pointer<Utf8> relativePath);

/// `size_t sigil_save_layout_subdirs(const char *layout, const char **out, size_t cap)`.
typedef SigilLayoutSubdirsNative = Size Function(Pointer<Utf8> layout, Pointer<Pointer<Utf8>> out, Size cap);
typedef SigilLayoutSubdirs = int Function(Pointer<Utf8> layout, Pointer<Pointer<Utf8>> out, int cap);

/// `int sigil_collect(const sigil_sync_request *req, sigil_sync_result **out)`.
typedef SigilCollectNative = Int32 Function(Pointer<SigilSyncRequest> req, Pointer<Pointer<SigilSyncResult>> out);
typedef SigilCollect = int Function(Pointer<SigilSyncRequest> req, Pointer<Pointer<SigilSyncResult>> out);

/// `int sigil_restore(const sigil_sync_request *req, const uint8_t *unit, size_t unit_len, sigil_sync_result **out)`.
typedef SigilRestoreNative = Int32 Function(
  Pointer<SigilSyncRequest> req,
  Pointer<Uint8> unit,
  Size unitLen,
  Pointer<Pointer<SigilSyncResult>> out,
);
typedef SigilRestore = int Function(
  Pointer<SigilSyncRequest> req,
  Pointer<Uint8> unit,
  int unitLen,
  Pointer<Pointer<SigilSyncResult>> out,
);

/// `void sigil_sync_result_free(sigil_sync_result *result)`.
typedef SigilSyncResultFreeNative = Void Function(Pointer<SigilSyncResult> result);
typedef SigilSyncResultFree = void Function(Pointer<SigilSyncResult> result);
