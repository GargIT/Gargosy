import 'dart:ffi';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'sigil_bindings.dart';
import 'sigil_engine.dart';
import 'sigil_library.dart';

/// One collect or restore: the emulator (sigil layout), the game, and the
/// folder its saves are in (the save root).
class SigilSyncCall {
  const SigilSyncCall({
    required this.layout,
    required this.platform,
    required this.contentPath,
    required this.saveRoot,
    this.gameIds = const [],
    this.titleId,
    this.rawSerial,
    this.saveId,
    this.usage,
    this.options = const {},
    this.state,
    this.overwriteLocal = false,
    this.repair = false,
  });

  /// sigil's layout id, e.g. `pcsx2_standalone`.
  final String layout;

  /// sigil's platform slug (`ps2`, `psx`, `gamecube`, `psp`, `dreamcast`, `gb`).
  final String platform;

  /// The ROM the emulator loads (only its file name matters to sigil).
  final String contentPath;

  /// The folder sigil reads and writes, and nothing outside it.
  final String saveRoot;

  /// Every id the game's saves may carry (all discs of a set).
  final List<String> gameIds;

  /// The game's id and save name as RomM read them (`title_id`,
  /// `save_target`) and how its saves are laid out (sigil_usage: RomM's
  /// `save_target_layout` in order). Null: sigil reads them from the ROM.
  final String? titleId;

  /// The id as the disc spells it, when it differs from [titleId]
  /// (GameCube: `GZLE`, whose `title_id` is the hex `475A4C45`).
  final String? rawSerial;
  final String? saveId;
  final int? usage;

  /// Emulator settings that change file names (`Slot1_Filename`, ...).
  final Map<String, String> options;

  /// The state blob the last collect or restore for this game returned.
  final Uint8List? state;

  final bool overwriteLocal;
  final bool repair;
}

/// What collect gathered.
class SigilCollected {
  const SigilCollected({
    required this.artifact,
    required this.data,
    required this.contentHash,
    required this.identityHash,
    required this.changed,
    required this.state,
    required this.holding,
    required this.unowned,
    required this.restoreAgain,
    this.newestRead,
    this.reads = const {},
  });

  /// The file name the unit travels under.
  final String artifact;

  /// The unit to upload; null when the game has no saves there.
  final Uint8List? data;

  /// RomM's `content_hash` of the unit.
  final String contentHash;

  /// A hash over the saves themselves (timestamps and placement don't move it).
  final String identityHash;

  /// The saves changed since the last sync (the state passed in).
  final bool changed;

  /// To store once the upload succeeded and pass back next time.
  final Uint8List? state;

  /// Saturn, Sega CD, Dreamcast: the unclaimed saves on a shared volume, zipped.
  final Uint8List? holding;
  final List<String> unowned;

  /// Unmanaged: the saves the last restore wrote were overwritten since.
  final bool restoreAgain;

  /// When the newest file sigil read was written: the save's own time
  /// (a card other games share counts too, when sigil opened it).
  final DateTime? newestRead;

  /// Every file sigil read (root-relative) and when it was last written.
  final Map<String, DateTime> reads;
}

/// What restore did.
class SigilRestored {
  const SigilRestored({required this.state, required this.hardcoreMarker});
  final Uint8List? state;

  /// The unit ended in Argosy's old hardcore marker (left out of the saves).
  final bool hardcoreMarker;
}

/// sigil refused a collect or restore; [problem] names the save or file.
class SigilSyncError extends SigilException {
  const SigilSyncError(super.code, super.message, {this.problem = '', this.blocksShort = 0});
  final String problem;
  final int blocksShort;

  @override
  String toString() => 'sigil: $message ($code)${problem.isEmpty ? '' : ': $problem'}';
}

/// [relative] (as sigil gives it, `/` separated) inside [root], or null when
/// it would leave the root (`..`, an absolute path, a drive).
String? sigilRootPath(String root, String relative) {
  if (relative.isEmpty || p.isAbsolute(relative) || relative.startsWith('/') || relative.startsWith(r'\')) return null;
  if (relative.contains(':')) return null;
  final parts = relative.split(RegExp(r'[/\\]'));
  if (parts.any((s) => s == '..')) return null;
  final full = p.normalize(p.joinAll([root, ...parts.where((s) => s.isNotEmpty && s != '.')]));
  return p.isWithin(p.normalize(root), full) ? full : null;
}

/// Every file directly in [root] and under [subdirs], 12 levels deep, as
/// root-relative `/` paths (sigil's listing).
List<String> sigilListing(String root, List<String> subdirs) {
  final out = <String>{};
  final dir = io.Directory(root);
  if (!dir.existsSync()) return const [];
  for (final e in dir.listSync()) {
    if (e is io.File) out.add(p.basename(e.path));
  }
  void walk(String rel, int depth) {
    final d = io.Directory(p.join(root, rel));
    if (depth > 12 || !d.existsSync()) return;
    for (final e in d.listSync()) {
      final child = '$rel/${p.basename(e.path)}';
      if (e is io.File) {
        out.add(child);
      } else if (e is io.Directory) {
        walk(child, depth + 1);
      }
    }
  }

  for (final s in subdirs) {
    walk(s.replaceAll(RegExp(r'/+$'), ''), 1);
  }
  return out.toList()..sort();
}

const _resultRoom = 1024;

/// collect (unit == null) or restore, in the calling isolate.
Object runSigilSync(String lib, SigilSyncCall call, Uint8List? unit) {
  SigilLibrary.path = lib;
  final dll = SigilLibrary.open();
  final strerror = dll.lookupFunction<SigilStrerrorNative, SigilStrerror>('sigil_strerror');
  final subdirsFn = dll.lookupFunction<SigilLayoutSubdirsNative, SigilLayoutSubdirs>('sigil_save_layout_subdirs');
  final fromSlug = dll.lookupFunction<SigilPlatformFromSlugNative, SigilPlatformFromSlug>('sigil_platform_from_slug');
  final extract = dll.lookupFunction<SigilExtractNative, SigilExtract>('sigil_extract_from_path');
  final openFile = dll.lookupFunction<SigilIoOpenNative, SigilIoOpen>('sigil_io_open_file');
  final collect = dll.lookupFunction<SigilCollectNative, SigilCollect>('sigil_collect');
  final restore = dll.lookupFunction<SigilRestoreNative, SigilRestore>('sigil_restore');
  final free = dll.lookupFunction<SigilSyncResultFreeNative, SigilSyncResultFree>('sigil_sync_result_free');
  final root = p.normalize(call.saveRoot);
  DateTime? newest;
  final reads = <String, DateTime>{};

  final open = NativeCallable<SigilSaveOpenFn>.isolateLocal((Pointer<Void> _, Pointer<Utf8> rel) {
    final full = sigilRootPath(root, rel.toDartString());
    if (full == null) return nullptr;
    try {
      final m = io.File(full).lastModifiedSync();
      reads[rel.toDartString()] = m;
      if (newest == null || m.isAfter(newest!)) newest = m;
    } catch (_) {}
    final path = full.toNativeUtf8();
    try {
      return openFile(path);
    } finally {
      malloc.free(path);
    }
  });
  final write = NativeCallable<SigilSaveWriteFn>.isolateLocal((
    Pointer<Void> _,
    Pointer<Utf8> rel,
    Pointer<Uint8> data,
    int len,
  ) {
    final full = sigilRootPath(root, rel.toDartString());
    if (full == null) return -1;
    try {
      io.Directory(p.dirname(full)).createSync(recursive: true);
      final tmp = io.File('$full.gargosy-sigil');
      tmp.writeAsBytesSync(len == 0 ? const <int>[] : data.asTypedList(len), flush: true);
      tmp.renameSync(full);
      return 0;
    } catch (_) {
      return -1;
    }
  }, exceptionalReturn: -1);
  final remove = NativeCallable<SigilSaveRemoveFn>.isolateLocal((Pointer<Void> _, Pointer<Utf8> rel) {
    final relative = rel.toDartString();
    final full = sigilRootPath(root, relative.replaceAll(RegExp(r'/+$'), ''));
    if (full == null || full == root) return -1;
    try {
      if (relative.endsWith('/')) {
        final d = io.Directory(full);
        if (d.existsSync()) d.deleteSync(recursive: true);
      } else {
        final f = io.File(full);
        if (f.existsSync()) f.deleteSync();
      }
      return 0;
    } catch (_) {
      return -1;
    }
  }, exceptionalReturn: -1);

  try {
    return using((arena) {
      Pointer<Utf8> s(String v) => v.toNativeUtf8(allocator: arena);
      Pointer<Pointer<Utf8>> strings(List<String> list) {
        final a = arena<Pointer<Utf8>>(list.isEmpty ? 1 : list.length);
        for (var i = 0; i < list.length; i++) {
          a[i] = s(list[i]);
        }
        return a;
      }

      final layout = s(call.layout);
      final subdirsOut = arena<Pointer<Utf8>>(32);
      final n = subdirsFn(layout, subdirsOut, 32);
      final subdirs = [for (var i = 0; i < (n < 32 ? n : 32); i++) subdirsOut[i].toDartString()];
      final listing = sigilListing(root, subdirs);

      // The game's identity: RomM's ids, else read from the ROM by sigil.
      Pointer<SigilResult> result = nullptr;
      if (call.titleId != null) {
        result = arena.allocate<Uint8>(_resultRoom).cast<SigilResult>();
        final r = result.ref
          ..structVersion = sigilResultV4
          ..platform = fromSlug(s(call.platform))
          ..usage = call.usage ?? 0
          ..source = sigilSourceBinary;
        _putText(r.titleId, call.titleId!, 32);
        _putText(r.rawSerial, call.rawSerial ?? call.titleId!, 32);
        _putText(r.saveId, call.saveId ?? call.titleId!, 32);
      } else if (io.File(call.contentPath).existsSync()) {
        final read = arena.allocate<Uint8>(_resultRoom).cast<SigilResult>();
        if (extract(s(call.contentPath), fromSlug(s(call.platform)), nullptr, read) == sigilOk) result = read;
      }

      final options = arena<SigilSaveOption>(call.options.isEmpty ? 1 : call.options.length);
      var i = 0;
      for (final e in call.options.entries) {
        options[i].key = s(e.key);
        options[i].value = s(e.value);
        i++;
      }

      final req = arena<SigilSyncRequest>();
      req.ref
        ..structVersion = sigilSyncRequestV1
        ..gameIds = strings(call.gameIds)
        ..gameIdCount = call.gameIds.length
        ..mode = sigilSyncUnmanaged
        ..overwriteLocal = call.overwriteLocal ? 1 : 0
        ..write = write.nativeFunction
        ..remove = remove.nativeFunction
        ..repair = call.repair ? 1 : 0;
      req.ref.save
        ..structVersion = sigilSaveRequestV1
        ..layout = layout
        ..platform = s(call.platform)
        ..contentPath = s(call.contentPath)
        ..result = result
        ..options = options
        ..optionCount = call.options.length
        ..listing = strings(listing)
        ..listingCount = listing.length
        ..open = open.nativeFunction
        ..rootPath = s(root);
      final state = call.state;
      if (state != null && state.isNotEmpty) {
        final buf = arena<Uint8>(state.length)..asTypedList(state.length).setAll(0, state);
        req.ref
          ..state = buf
          ..stateLen = state.length;
      }

      final out = arena<Pointer<SigilSyncResult>>();
      final int code;
      if (unit == null) {
        code = collect(req, out);
      } else {
        final buf = arena<Uint8>(unit.isEmpty ? 1 : unit.length)..asTypedList(unit.length).setAll(0, unit);
        code = restore(req, buf, unit.length, out);
      }
      final res = out.value;
      try {
        if (code != sigilOk) {
          throw SigilSyncError(
            code,
            strerror(code).toDartString(),
            problem: res == nullptr ? '' : sigilText(res.ref.problem, 512),
            blocksShort: res == nullptr ? 0 : res.ref.blocksShort,
          );
        }
        if (res == nullptr) throw const SigilSyncError(sigilErrInvalidArg, 'sigil returned no result');
        final r = res.ref;
        if (r.structVersion != sigilSyncResultV1) {
          throw SigilSyncError(sigilErrInvalidArg, 'sigil_sync_result is version ${r.structVersion}');
        }
        Uint8List? bytes(Pointer<Uint8> ptr, int len) =>
            ptr == nullptr ? null : Uint8List.fromList(ptr.asTypedList(len));
        if (unit != null) {
          return SigilRestored(state: bytes(r.state, r.stateLen), hardcoreMarker: r.hardcoreMarker != 0);
        }
        return SigilCollected(
          artifact: sigilText(r.artifact, 256),
          data: bytes(r.data, r.len),
          contentHash: sigilText(r.contentHash, 33),
          identityHash: sigilText(r.identityHash, 33),
          changed: r.changed != 0,
          state: bytes(r.state, r.stateLen),
          holding: bytes(r.holding, r.holdingLen),
          unowned: [
            for (var k = 0; k < r.unownedCount; k++) _cString(r.unowned + k * sigilCardNameMax, sigilCardNameMax),
          ],
          restoreAgain: r.restoreAgain != 0,
          newestRead: newest,
          reads: reads,
        );
      } finally {
        if (res != nullptr) free(res);
      }
    });
  } finally {
    open.close();
    write.close();
    remove.close();
  }
}

void _putText(Array<Uint8> field, String text, int length) {
  final bytes = text.codeUnits;
  for (var i = 0; i < length; i++) {
    field[i] = i < bytes.length && i < length - 1 ? bytes[i] : 0;
  }
}

String _cString(Pointer<Uint8> at, int max) {
  final b = <int>[];
  for (var i = 0; i < max; i++) {
    final c = at[i];
    if (c == 0) break;
    b.add(c);
  }
  return String.fromCharCodes(b);
}
