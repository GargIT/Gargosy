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

/// [from] (a file in the shared `bios\`) at [to], hard-linked where the
/// drive allows it, else copied; a file of the same size there is kept.
void placeSharedFile(io.File from, String to, PathGuard guard) => _place(from, to, guard);

/// The first file named one of [names] (any case) in [bios] or its
/// subfolders (RomM's firmware lands in `bios\` or a platform folder), or null.
io.File? findBiosFile(String bios, List<String> names) {
  final dir = io.Directory(bios);
  if (!dir.existsSync()) return null;
  final wanted = {for (final n in names) n.toLowerCase()};
  final found = dir
      .listSync(recursive: true, followLinks: false)
      .whereType<io.File>()
      .where((f) => wanted.contains(p.basename(f.path).toLowerCase()))
      .toList()
    ..sort((a, b) => p.split(a.path).length.compareTo(p.split(b.path).length)); // bios\ itself first
  return found.firstOrNull;
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
