import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/extraction/unpacker.dart';
import '../core/platform/platform_info.dart';
import '../core/romm/romm_models.dart';
import '../profiles/path_guard.dart';
import 'disk_space.dart';
import 'rom_files.dart';
import 'xbox_disc.dart';
import '../l10n/tr.dart';

/// Unpacking or converting a ROM failed; the ROM is left as it was.
class RomPrepareException implements Exception {
  const RomPrepareException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Readies a downloaded ROM for the emulator about to play it, once:
/// - a `.zip` the emulator can't open is unpacked into the game's folder
///   (`RomFiles.unpackedDirFor`), and the zip goes;
/// - for xemu, an original Xbox disc becomes an XISO (xemu.app/docs/disc-images:
///   a Redump image loses its video partition).
///
/// The OS's [Unpacker] unpacks (Windows' `tar.exe`). An Xbox disc streams
/// out of it straight into its XISO, so it needs no room beyond the result.
/// Work is staged in `userdata\app\temp`; `roms\` only gets the finished
/// folder or file, and a failure leaves the ROM as it was.
class RomPreparer {
  RomPreparer({
    required this.files,
    required this.guard,
    required this.tempDir,
    this.gamePartition = xgd1GamePartition,
    this.disk,
    Unpacker? unpacker,
    PlatformInfo? platform,
  }) : _unpacker = unpacker ?? unpackerFor(platform ?? PlatformInfo.current);

  final RomFiles files;
  final PathGuard guard;
  final String tempDir;
  final int gamePartition;

  /// The free space on a path's volume (#142); null skips the check.
  final DiskInfo? disk;
  final Unpacker _unpacker;

  /// Emulators that open a zipped ROM themselves.
  static const zipReaders = {'retroarch', 'mame', 'ares', 'mgba', 'flycast'};

  /// Platforms whose zip is the game itself (arcade sets): never unpacked.
  static const zipPlatforms = {
    'arcade', 'mame', 'fbneo', 'neogeo', 'neo-geo', 'neogeoaes', 'neogeomvs', 'neo-geo-aes', 'neo-geo-mvs', //
    'cps1', 'cps2', 'cps3', 'naomi', 'naomi2', 'atomiswave',
  };

  /// Readies [romPath] for [emulatorId]. Returns the folder a zip was
  /// unpacked into (look the ROM up again there), or null when the ROM
  /// stays where it is. [onProgress] hears what's happening, with a percentage.
  Future<String?> ready(Game game, String romPath, String emulatorId, {void Function(String)? onProgress}) async {
    final isZip = p.extension(romPath).toLowerCase() == '.zip';
    if (isZip && io.File(romPath).existsSync()) {
      if (zipReaders.contains(emulatorId) || zipPlatforms.contains(game.platformSlug?.toLowerCase())) return null;
      // Unpacked already, but the zip stayed (an older Gargosy, or a delete
      // that failed): play the folder, and the zip goes as after an unpack.
      // An unpack is moved in whole, so a folder with files is a finished one.
      final dest = files.unpackedDirFor(game);
      if (dest != null && _hasFiles(dest)) {
        try {
          io.File(guard.check(romPath)).deleteSync();
        } on io.FileSystemException {
          // In use: it goes on a later start; the folder plays meanwhile.
        }
        return dest;
      }
      return _unpack(game, romPath, emulatorId, onProgress);
    }
    if (emulatorId == 'xemu' && p.extension(romPath).toLowerCase() == '.iso' && io.File(romPath).existsSync()) {
      await _toXiso(game, romPath, onProgress);
    }
    return null;
  }

  Future<String> _unpack(Game game, String zip, String emulatorId, void Function(String)? onProgress) async {
    final dest = files.unpackedDirFor(game)!;
    // Checked before unpacking, not after minutes of it: an empty folder
    // goes, anything else in the way refuses.
    if (io.Directory(dest).existsSync()) io.Directory(guard.check(dest)).deleteSync();
    if (io.FileSystemEntity.typeSync(dest) != io.FileSystemEntityType.notFound) {
      throw RomPrepareException(tr('{0} is already in the way in {1}.', [p.basename(dest), p.dirname(dest)]));
    }
    final staging = guard.check(p.join(tempDir, 'unpack-${game.id}'));
    _remove(staging);
    io.Directory(staging).createSync(recursive: true);
    try {
      final entries = await _list(zip, game);
      if (disk case final disk?) {
        final total = entries.fold<int>(0, (n, e) => n + e.size);
        // Unpacked in temp, then moved into roms\ (copied when that's another volume).
        checkSpace({staging: total, if (disk.volumeOf(dest) != disk.volumeOf(staging)) dest: total}, disk);
      }
      final isos = [
        for (final e in entries)
          if (p.extension(e.name).toLowerCase() == '.iso') e,
      ];
      final label = tr('Unpacking {0}', [game.displayName]);
      if (emulatorId == 'xemu' && isos.length == 1) {
        final iso = isos.single;
        if (entries.length > 1) await _run(zip, staging, game, exclude: [iso.name]);
        final name = RomFiles.safeName(p.basename(iso.name.replaceAll('\\', '/')));
        await _streamXiso(zip, iso.name, p.join(staging, name), iso.size, game, onProgress);
      } else {
        final total = entries.fold<int>(0, (n, e) => n + e.size);
        await _run(zip, staging, game, progress: () => _report(onProgress, label, _sizeOf(staging), total));
      }
      _checkInside(staging);
      if (io.FileSystemEntity.typeSync(dest) != io.FileSystemEntityType.notFound) {
        throw RomPrepareException(tr('{0} is already in the way in {1}.', [p.basename(dest), p.dirname(dest)]));
      }
      _move(staging, guard.check(dest));
      io.File(guard.check(zip)).deleteSync();
      return dest;
    } finally {
      _remove(staging);
    }
  }

  /// Streams the zip's one `.iso`, [entry] as the unpacker lists it, into
  /// [dst] as an XISO.
  Future<void> _streamXiso(
    String zip,
    String entry,
    String dst,
    int size,
    Game game,
    void Function(String)? onProgress,
  ) async {
    final out = io.File(guard.check(dst)).openSync(mode: io.FileMode.write);
    final writer = XisoWriter(out, name: game.displayName, gamePartition: gamePartition);
    var read = 0;
    try {
      await for (final chunk in _unpacker.open(zip, entry)) {
        writer.add(chunk);
        read += chunk.length;
        _report(
          onProgress,
          writer.kind == XboxDisc.redump
              ? tr('Converting {0} for xemu', [game.displayName])
              : tr('Unpacking {0}', [game.displayName]),
          read,
          size,
        );
      }
      writer.close();
    } on UnpackException catch (e) {
      throw RomPrepareException(tr('Couldn\'t unpack {0}: {1}', [game.displayName, e.detail]));
    } finally {
      out.closeSync();
    }
  }

  /// A Redump `.iso` on disk becomes an XISO in place; an XISO stays.
  Future<void> _toXiso(Game game, String iso, void Function(String)? onProgress) async {
    switch (detectXboxDisc(iso, gamePartition: gamePartition)) {
      case XboxDisc.xiso:
        return;
      case XboxDisc.unknown:
        throw NotAnXboxDisc(game.displayName);
      case XboxDisc.redump:
        final tmp = guard.check(p.join(tempDir, 'xiso-${game.id}.iso'));
        io.Directory(tempDir).createSync(recursive: true);
        try {
          await redumpToXiso(
            iso,
            tmp,
            gamePartition: gamePartition,
            onProgress: (done, total) =>
                _report(onProgress, tr('Converting {0} for xemu', [game.displayName]), done, total),
          );
          // Renaming over the original replaces it in one step (same drive).
          _moveFile(tmp, guard.check(iso));
        } finally {
          if (io.File(tmp).existsSync()) io.File(tmp).deleteSync();
        }
    }
  }

  int _lastPercent = -1;

  void _report(void Function(String)? onProgress, String label, int done, int total) {
    if (onProgress == null || total <= 0) return;
    final percent = (done * 100 ~/ total).clamp(0, 100);
    if (percent == _lastPercent) return;
    _lastPercent = percent;
    onProgress('$label… $percent %');
  }

  /// The zip's files and their sizes.
  Future<List<ZipEntry>> _list(String zip, Game game) async {
    try {
      return await _unpacker.list(zip);
    } on UnpackException catch (e) {
      throw RomPrepareException(tr('Couldn\'t open {0}\'s zip: {1}', [game.displayName, e.detail]));
    }
  }

  Future<void> _run(
    String zip,
    String into,
    Game game, {
    List<String> exclude = const [],
    void Function()? progress,
  }) async {
    try {
      await _unpacker.unpack(zip, into, exclude: exclude, tick: progress);
    } on UnpackException catch (e) {
      throw RomPrepareException(tr('Couldn\'t unpack {0}: {1}', [game.displayName, e.detail]));
    }
  }

  static bool _hasFiles(String dir) =>
      io.Directory(dir).existsSync() && io.Directory(dir).listSync(recursive: true).any((e) => e is io.File);

  static int _sizeOf(String dir) {
    var n = 0;
    for (final e in io.Directory(dir).listSync(recursive: true)) {
      if (e is io.File) n += e.lengthSync();
    }
    return n;
  }

  /// The unpacker refuses `..` and absolute names; checked again so nothing lands
  /// outside the game's folder.
  static void _checkInside(String dir) {
    for (final e in io.Directory(dir).listSync(recursive: true, followLinks: false)) {
      if (e is io.Link || !p.isWithin(dir, p.normalize(e.absolute.path))) {
        throw RomPrepareException(tr('The zip holds {0}, which points outside the game folder.', [p.basename(e.path)]));
      }
    }
  }

  static void _move(String from, String to) {
    io.Directory(p.dirname(to)).createSync(recursive: true);
    try {
      io.Directory(from).renameSync(to);
    } on io.FileSystemException {
      // Another drive: copy, then the staging folder goes in `finally`.
      for (final e in io.Directory(from).listSync(recursive: true)) {
        final target = p.join(to, p.relative(e.path, from: from));
        if (e is io.Directory) {
          io.Directory(target).createSync(recursive: true);
        } else if (e is io.File) {
          io.Directory(p.dirname(target)).createSync(recursive: true);
          e.copySync(target);
        }
      }
    }
  }

  static void _moveFile(String from, String to) {
    try {
      io.File(from).renameSync(to);
    } on io.FileSystemException {
      io.File(from).copySync(to);
    }
  }

  static void _remove(String path) {
    if (io.Directory(path).existsSync()) io.Directory(path).deleteSync(recursive: true);
  }
}
