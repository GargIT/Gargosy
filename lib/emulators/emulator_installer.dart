import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emulator/emulator_download_service.dart';
import '../core/extraction/extraction_service.dart';
import '../core/extraction/unpacker.dart';
import '../providers/engine_providers.dart';
import 'emulator_library.dart';
import '../l10n/tr.dart';

/// How an install is going: 'downloading', 'extracting', 'done' or 'error'.
class InstallProgress {
  const InstallProgress(this.status, this.percent, {this.error});
  final String status;
  final double percent;
  final String? error;
}

/// Downloads an emulator into `emulators\<id>\` (spec §6). An update
/// replaces only the program: every profile's data is in its own folder.
abstract class EmulatorInstaller {
  /// The newest download for [id]; null when none is found.
  Future<String?> latestUrl(String id);

  /// Installs [url] and records it (EmulatorLibrary.recordInstall).
  Stream<InstallProgress> install(String id, String url);
}

/// [EmulatorInstaller] on Freegosy's download service (direct URLs and
/// GitHub releases).
class GargosyEmulatorInstaller implements EmulatorInstaller {
  GargosyEmulatorInstaller(this._service, this._library);

  final EmulatorDownloadService _service;
  final EmulatorLibrary _library;

  @override
  Future<String?> latestUrl(String id) => _service.resolveCurrentDownloadUrl(id);

  @override
  Stream<InstallProgress> install(String id, String url) async* {
    // A release zip with its own user\ or portable\ must not unpack into a
    // profile through a folder link (issue #8): the links go first, and the
    // next launch points them again.
    _library.removeFolderLinks(id);
    var finished = false;
    await for (final pr in _service.downloadEmulator(id, urlOverride: url)) {
      if (pr.error != null) {
        yield InstallProgress('error', pr.percent, error: pr.error);
        return;
      }
      if (pr.status == 'selection_required') {
        yield InstallProgress('error', 0, error: tr('more than one download matches; nothing was installed'));
        return;
      }
      if (pr.isComplete) finished = true;
      yield InstallProgress(pr.status, pr.percent);
    }
    if (!finished) {
      yield InstallProgress('error', 0, error: tr('the download stopped before it finished'));
      return;
    }
    await _library.recordInstall(id, from: url);
    yield const InstallProgress('done', 1);
  }
}

final emulatorInstallerProvider = Provider<EmulatorInstaller?>((ref) {
  final dirs = ref.watch(launchDirectoriesProvider);
  final registry = ref.watch(strategyRegistryProvider);
  final library = ref.watch(emulatorLibraryProvider);
  final unpacker = ref.watch(unpackerProvider);
  if (dirs == null || registry == null || library == null) return null;
  return GargosyEmulatorInstaller(
    EmulatorDownloadService(Dio(), dirs, ExtractionService(dirs, unpacker: () => unpacker), registry),
    library,
  );
});
