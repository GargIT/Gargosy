import 'dart:ffi';
import 'dart:io' as io;

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../ui/widgets/format.dart';
import '../l10n/tr.dart';

/// The bytes free to this user on the drive of a path, or null when it
/// can't be told (the check is then skipped).
typedef FreeSpaceOf = int? Function(String path);

/// [FreeSpaceOf] on Windows: `GetDiskFreeSpaceExW` on the nearest folder of
/// [path] that exists.
int? windowsFreeSpace(String path) => windowsDiskUsage(path)?.free;

/// The free bytes (to this user) and the size of [path]'s drive (#145).
({int free, int total})? windowsDiskUsage(String path) {
  var dir = p.normalize(p.absolute(path));
  while (!io.Directory(dir).existsSync()) {
    final up = p.dirname(dir);
    if (up == dir) return null;
    dir = up;
  }
  return using((arena) {
    final free = arena<Uint64>();
    final total = arena<Uint64>();
    final ok = GetDiskFreeSpaceEx(dir.toNativeUtf16(allocator: arena), free, total, nullptr);
    return ok == 0 ? null : (free: free.value, total: total.value);
  });
}

/// Not enough room on [drive] for what's about to be written there.
class NotEnoughSpace implements Exception {
  const NotEnoughSpace({required this.drive, required this.needed, required this.free});

  final String drive;
  final int needed;
  final int free;

  @override
  String toString() => tr('Needs {0}, {1} free on {2}.', [formatBytes(needed), formatBytes(free), drive]);
}

/// `D:` for a path on D:, the share for a network path.
String driveOf(String path) {
  final root = p.rootPrefix(p.absolute(path));
  return root.endsWith(r'\') || root.endsWith('/') ? root.substring(0, root.length - 1) : root;
}

/// Kept free beyond what's written, so the drive isn't filled to the byte.
const spaceHeadroom = 200 * 1024 * 1024;

/// Checks that each drive has room for the bytes [writes] puts on it (a
/// path and how much goes there; paths on one drive add up), plus
/// [spaceHeadroom]. Throws [NotEnoughSpace] for the first that hasn't.
void checkSpace(Map<String, int> writes, FreeSpaceOf freeOf) {
  final byDrive = <String, (String, int)>{};
  for (final MapEntry(key: path, value: bytes) in writes.entries) {
    if (bytes <= 0) continue;
    final d = driveOf(path).toUpperCase();
    final had = byDrive[d];
    byDrive[d] = (had?.$1 ?? path, (had?.$2 ?? 0) + bytes);
  }
  for (final MapEntry(key: drive, value: (path, bytes)) in byDrive.entries) {
    final free = freeOf(path);
    if (free == null) continue;
    if (free < bytes + spaceHeadroom) throw NotEnoughSpace(drive: drive, needed: bytes, free: free);
  }
}

/// Whether [free] bytes is tight for [size]: less than twice it.
bool spaceIsTight(int size, int? free) => free != null && size > 0 && free < size * 2 + spaceHeadroom;
