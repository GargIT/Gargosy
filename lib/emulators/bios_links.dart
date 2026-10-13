import 'dart:ffi';
import 'dart:io' as io;

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../core/emulator/bios_registry.dart';
import '../profiles/path_guard.dart';

/// Puts the shared `bios\` files into a profile's RetroArch `system\` folder,
/// where its cores look (spec §6): the folder as it is, and each BIOS also in
/// the folder its core expects (Freegosy's BIOS registry: PS2 dumps in
/// `pcsx2\bios`, Flycast's in `dc`, …). Hard links, so every profile shares
/// the bytes; a copy where the drive can't link (exFAT). Nothing in
/// `system\` is ever removed: cores keep their own files there.
void linkBiosInto(String bios, String system, PathGuard guard) {
  final src = io.Directory(bios);
  if (!src.existsSync()) return;
  for (final e in src.listSync(recursive: true)) {
    if (e is! io.File) continue;
    final rel = p.relative(e.path, from: bios);
    _place(e, p.join(system, rel), guard);
    if (p.split(rel).length > 1) continue; // already in a core's folder
    final name = p.basename(rel);
    for (final folder in _coreFoldersFor(name, e.lengthSync())) {
      _place(e, p.join(system, folder, name), guard);
    }
  }
}

/// A PS2 BIOS dump is 4 MiB; any name works for the PS2 core.
const _ps2BiosBytes = 4 * 1024 * 1024;

/// The core folders a file at the root of `bios\` also belongs in.
Iterable<String> _coreFoldersFor(String name, int bytes) sync* {
  final lower = name.toLowerCase();
  if (lower.endsWith('.bin') && bytes == _ps2BiosBytes) yield p.join('pcsx2', 'bios');
  for (final spec in kBiosRegistry.values) {
    final folder = spec.fallbackSubdirectoryLibretro;
    if (folder == null || folder == 'pcsx2/bios') continue;
    if (spec.files.any((f) => f.fileName.toLowerCase() == lower)) yield p.joinAll(folder.split('/'));
  }
}

/// The files in `bios\`, listed once for several [find]s.
class BiosFiles {
  BiosFiles(this.bios)
      : _files = io.Directory(bios).existsSync()
            ? io.Directory(bios).listSync(recursive: true, followLinks: false).whereType<io.File>().toList()
            : const [];

  final String bios;
  final List<io.File> _files;

  /// The file named one of [names] (any case), or null. RomM's firmware
  /// lands in `bios\` or a platform folder: [platforms] (`nds`, `switch` …)
  /// come first, then `bios\` itself, then the shallowest elsewhere, so a
  /// generic name (firmware.bin, keys.txt) from another system isn't taken
  /// when this one's is there.
  io.File? find(List<String> names, {List<String> platforms = const []}) {
    final wanted = {for (final n in names) n.toLowerCase()};
    final found = _files.where((f) => wanted.contains(p.basename(f.path).toLowerCase())).toList();
    int rank(io.File f) {
      final parts = p.split(p.relative(f.path, from: bios));
      if (parts.length > 1 && platforms.contains(parts.first.toLowerCase())) return 0;
      return parts.length; // 1 for bios\ itself
    }

    found.sort((a, b) => rank(a).compareTo(rank(b)));
    return found.firstOrNull;
  }
}

/// [from] copied to [to] when nothing is there yet. For files the emulator
/// may change itself (keys it adds to): a profile's own copy, never a link
/// to the shared one, and never replaced once there.
void copySharedFileIfMissing(io.File from, String to, PathGuard guard) {
  final dest = io.File(guard.check(to));
  if (dest.existsSync()) return;
  dest.parent.createSync(recursive: true);
  from.copySync(dest.path);
}

void _place(io.File from, String to, PathGuard guard) {
  final dest = io.File(guard.check(to));
  final size = from.lengthSync();
  if (dest.existsSync()) {
    if (dest.lengthSync() == size) return;
    dest.deleteSync();
  }
  dest.parent.createSync(recursive: true);
  if (!_hardLink(from.path, dest.path)) from.copySync(dest.path);
}

final _createHardLink = DynamicLibrary.open('kernel32.dll').lookupFunction<
    Int32 Function(Pointer<Utf16> newFile, Pointer<Utf16> existing, Pointer<Void> security),
    int Function(Pointer<Utf16> newFile, Pointer<Utf16> existing, Pointer<Void> security)>('CreateHardLinkW');

bool _hardLink(String existing, String newFile) {
  // Windows' CreateHardLinkW; elsewhere (tests on Linux) a copy instead.
  try {
    _createHardLink;
  } on Object {
    return false;
  }
  final a = newFile.toNativeUtf16();
  final b = existing.toNativeUtf16();
  try {
    return _createHardLink(a, b, nullptr) != 0;
  } finally {
    calloc.free(a);
    calloc.free(b);
  }
}
