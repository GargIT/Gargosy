import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/platform/platform_info.dart';
import '../core/romm/romm_models.dart';
import '../profiles/path_guard.dart';
import 'rom_files.dart';
import 'xbox_disc.dart';

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
/// Windows' `tar.exe` unpacks (hundreds of MB/s). An Xbox disc streams out
/// of it straight into its XISO, so it needs no room beyond the result.
/// Work is staged in `userdata\app\temp`; `roms\` only gets the finished
/// folder or file, and a failure leaves the ROM as it was.
class RomPreparer {
  RomPreparer({
    required this.files,
    required this.guard,
    required this.tempDir,
    this.gamePartition = xgd1GamePartition,
    PlatformInfo? platform,
  }) : _tar = p.join((platform ?? PlatformInfo.current).environment['SystemRoot'] ?? r'C:\Windows', 'System32', 'tar.exe');

  final RomFiles files;
  final PathGuard guard;
  final String tempDir;
  final int gamePartition;
  final String _tar;

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
      return _unpack(game, romPath, emulatorId, onProgress);
    }
    if (emulatorId == 'xemu' && p.extension(romPath).toLowerCase() == '.iso' && io.File(romPath).existsSync()) {
      await _toXiso(game, romPath, onProgress);
    }
    return null;
  }

  Future<String> _unpack(Game game, String zip, String emulatorId, void Function(String)? onProgress) async {
    final dest = files.unpackedDirFor(game)!;
    final staging = guard.check(p.join(tempDir, 'unpack-${game.id}'));
    _remove(staging);
    io.Directory(staging).createSync(recursive: true);
    try {
      final entries = await _list(zip, game);
      final isos = [for (final e in entries) if (p.extension(e.name).toLowerCase() == '.iso') e];
      final label = 'Unpacking ${game.displayName}';
      if (emulatorId == 'xemu' && isos.length == 1) {
        if (entries.length > 1) await _run(['-xf', zip, '-C', staging, '--exclude', '*.iso'], game);
        final name = RomFiles.safeName(p.basename(isos.single.name.replaceAll('\\', '/')));
        await _streamXiso(zip, p.join(staging, name), isos.single.size, game, onProgress);
      } else {
        final total = entries.fold<int>(0, (n, e) => n + e.size);
        await _run(['-xf', zip, '-C', staging], game, progress: () => _report(onProgress, label, _sizeOf(staging), total));
      }
      _checkInside(staging);
      if (io.FileSystemEntity.typeSync(dest) != io.FileSystemEntityType.notFound) {
        throw RomPrepareException('${p.basename(dest)} is already in the way in ${p.dirname(dest)}.');
      }
      _move(staging, guard.check(dest));
      io.File(guard.check(zip)).deleteSync();
      return dest;
    } finally {
      _remove(staging);
    }
  }

  /// Streams the zip's one `.iso` out of tar into [dst] as an XISO.
  Future<void> _streamXiso(String zip, String dst, int size, Game game, void Function(String)? onProgress) async {
    final out = io.File(guard.check(dst)).openSync(mode: io.FileMode.write);
    final writer = XisoWriter(out, name: game.displayName, gamePartition: gamePartition);
    final proc = await io.Process.start(_tar, ['-xOf', zip, '*.iso']);
    final err = StringBuffer();
    final errDone = proc.stderr.transform(io.systemEncoding.decoder).forEach(err.write);
    var read = 0;
    try {
      await for (final chunk in proc.stdout) {
        writer.add(chunk);
        read += chunk.length;
        _report(onProgress, writer.kind == XboxDisc.redump ? 'Converting ${game.displayName} for xemu' : 'Unpacking ${game.displayName}', read, size);
      }
      writer.close();
    } on Object {
      proc.kill();
      rethrow;
    } finally {
      await proc.exitCode;
      await errDone;
      out.closeSync();
    }
    if (await proc.exitCode != 0) throw RomPrepareException("Couldn't unpack ${game.displayName}: ${err.toString().trim()}");
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
          await redumpToXiso(iso, tmp,
              gamePartition: gamePartition,
              onProgress: (done, total) => _report(onProgress, 'Converting ${game.displayName} for xemu', done, total));
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

  /// The zip's files and their sizes, from `tar -tvf`.
  Future<List<({String name, int size})>> _list(String zip, Game game) async {
    final r = await io.Process.run(_tar, ['-tvf', zip]);
    if (r.exitCode != 0) {
      throw RomPrepareException("Couldn't open ${game.displayName}'s zip: ${(r.stderr as String).trim()}");
    }
    // -rw-rw-r--  0 0      0  7825162240 dec 24  1996 Name.iso (the month is localised)
    final line = RegExp(r'^(\S)\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+\S+\s(.*)$');
    return [
      for (final l in const LineSplitter().convert(r.stdout as String))
        if (line.firstMatch(l.trimRight()) case final m? when m.group(1) == '-') (name: m.group(3)!, size: int.parse(m.group(2)!)),
    ];
  }

  Future<void> _run(List<String> args, Game game, {void Function()? progress}) async {
    final proc = await io.Process.start(_tar, args);
    final err = StringBuffer();
    final errDone = proc.stderr.transform(io.systemEncoding.decoder).forEach(err.write);
    final outDone = proc.stdout.drain<void>();
    final timer = progress == null ? null : Timer.periodic(const Duration(milliseconds: 500), (_) => progress());
    final code = await proc.exitCode;
    timer?.cancel();
    await errDone;
    await outDone;
    if (code != 0) throw RomPrepareException("Couldn't unpack ${game.displayName}: ${err.toString().trim()}");
  }

  static int _sizeOf(String dir) {
    var n = 0;
    for (final e in io.Directory(dir).listSync(recursive: true)) {
      if (e is io.File) n += e.lengthSync();
    }
    return n;
  }

  /// tar refuses `..` and absolute names; checked again so nothing lands
  /// outside the game's folder.
  static void _checkInside(String dir) {
    for (final e in io.Directory(dir).listSync(recursive: true, followLinks: false)) {
      if (e is io.Link || !p.isWithin(dir, p.normalize(e.absolute.path))) {
        throw RomPrepareException('The zip holds ${p.basename(e.path)}, which points outside the game folder.');
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
