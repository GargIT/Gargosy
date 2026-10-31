import 'dart:ffi';
import 'dart:io' as io;

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../core/platform/platform_info.dart';
import '../ui/widgets/format.dart';
import '../l10n/tr.dart';

/// The volumes paths are on, and their room (#201): the checks before a
/// download or an unpack (#142), Storage's drive line (#145).
abstract class DiskInfo {
  /// The bytes free to this user and the size of [path]'s volume, or null
  /// when it can't be told (a check is then skipped).
  ({int free, int total})? usage(String path);

  /// The volume [path] is on, as the player knows it (`D:`, a share). Two
  /// paths on one volume give the same.
  String volumeOf(String path);
}

extension DiskFree on DiskInfo {
  /// The bytes free to this user on [path]'s volume, or null.
  int? freeOf(String path) => usage(path)?.free;
}

/// [DiskInfo.usage] for a screen: the game page rebuilds on each download
/// tick, and a slow or network drive would stall it, so a path's volume is
/// read again only once [refresh] has passed; a build after that sees what
/// other writers (queued downloads, an unpack, the image cache) did.
class DiskUsageCache {
  DiskUsageCache(this._disk, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const refresh = Duration(seconds: 5);

  final DiskInfo _disk;
  final DateTime Function() _now;
  final _read = <String, (DateTime, ({int free, int total})?)>{};

  ({int free, int total})? usage(String path) {
    final now = _now();
    if (_read[path] case (final at, final usage) when now.difference(at) < refresh) return usage;
    final usage = _disk.usage(path);
    _read[path] = (now, usage);
    return usage;
  }
}

/// The [DiskInfo] of [platform]'s OS.
DiskInfo diskInfoFor(PlatformInfo platform) {
  if (platform.isWindows) return const WindowsDiskInfo();
  throw UnsupportedError('No disk info on ${platform.os} yet');
}

/// Windows: `GetDiskFreeSpaceExW` on the nearest folder of a path that
/// exists; volumes are drive letters (or a share), any case.
class WindowsDiskInfo implements DiskInfo {
  const WindowsDiskInfo();

  @override
  ({int free, int total})? usage(String path) {
    var dir = p.normalize(p.absolute(path));
    while (!io.Directory(dir).existsSync()) {
      final up = p.dirname(dir);
      if (up == dir) return null;
      dir = up;
    }
    return using((arena) {
      final free = arena<Uint64>();
      final total = arena<Uint64>();
      final ok = GetDiskFreeSpaceEx(PCWSTR(dir.toNativeUtf16(allocator: arena)), free, total, null);
      return ok.value ? (free: free.value, total: total.value) : null;
    });
  }

  /// `D:` for a path on D:, the share for a network path.
  @override
  String volumeOf(String path) {
    final root = p.rootPrefix(p.absolute(path));
    return (root.endsWith(r'\') || root.endsWith('/') ? root.substring(0, root.length - 1) : root).toUpperCase();
  }
}

/// Not enough room on [drive] (a volume) for what's about to be written there.
class NotEnoughSpace implements Exception {
  const NotEnoughSpace({required this.drive, required this.needed, required this.free});

  final String drive;
  final int needed;
  final int free;

  @override
  String toString() => tr('Needs {0}, {1} free on {2}.', [formatBytes(needed), formatBytes(free), drive]);
}

/// Kept free beyond what's written, so the drive isn't filled to the byte.
const spaceHeadroom = 200 * 1024 * 1024;

/// Checks that each volume has room for the bytes [writes] puts on it (a
/// path and how much goes there; paths on one volume add up), plus
/// [spaceHeadroom]. Throws [NotEnoughSpace] for the first that hasn't.
void checkSpace(Map<String, int> writes, DiskInfo disk) {
  final byDrive = <String, (String, int)>{};
  for (final MapEntry(key: path, value: bytes) in writes.entries) {
    if (bytes <= 0) continue;
    final d = disk.volumeOf(path);
    final had = byDrive[d];
    byDrive[d] = (had?.$1 ?? path, (had?.$2 ?? 0) + bytes);
  }
  for (final MapEntry(key: drive, value: (path, bytes)) in byDrive.entries) {
    final free = disk.freeOf(path);
    if (free == null) continue;
    if (free < bytes + spaceHeadroom) throw NotEnoughSpace(drive: drive, needed: bytes, free: free);
  }
}

/// Whether [free] bytes is tight for [size]: less than twice it.
bool spaceIsTight(int size, int? free) => free != null && size > 0 && free < size * 2 + spaceHeadroom;
