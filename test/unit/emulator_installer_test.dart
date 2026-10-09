import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/downloader/download_service.dart';
import 'package:gargosy/core/emulator/emulator_download_service.dart';
import 'package:gargosy/emulators/emulator_installer.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

class _Service extends Fake implements EmulatorDownloadService {
  _Service(this.steps);
  final List<DownloadProgress> steps;
  String? usedOverride;

  @override
  Stream<DownloadProgress> downloadEmulator(String emulatorId,
      {String? architecture, String? buildType, String? urlOverride, Object? cancelToken}) async* {
    usedOverride = urlOverride;
    yield* Stream.fromIterable(steps);
  }
}

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  Future<(List<InstallProgress>, String?)> run(List<DownloadProgress> steps) async {
    final lib = EmulatorLibrary(root, const []);
    final installer = GargosyEmulatorInstaller(_Service(steps), lib);
    io.Directory(p.join(root.emulators, 'pcsx2')).createSync(recursive: true);
    final out = await installer.install('pcsx2', 'https://dl/pcsx2-windows.7z').toList();
    final record = io.File(p.join(root.emulators, 'pcsx2', '.gargosy-install.json'));
    return (out, record.existsSync() ? record.readAsStringSync() : null);
  }

  test('a finished download is recorded', () async {
    final (out, record) = await run([
      DownloadProgress(id: 'pcsx2', gameName: 'PCSX2', status: 'Downloading...'),
      DownloadProgress(id: 'pcsx2', gameName: 'PCSX2', percent: 1, isComplete: true, status: 'Done!'),
    ]);
    expect(out.last.status, 'done');
    expect(record, contains('pcsx2-windows.7z'));
  });

  test('several matching files, or a download that stops without finishing, is an error and records nothing', () async {
    var (out, record) = await run([DownloadProgress(id: 'pcsx2', gameName: 'PCSX2', status: 'selection_required')]);
    expect(out.last.error, isNotNull);
    expect(record, isNull);
    (out, record) = await run([DownloadProgress(id: 'pcsx2', gameName: 'PCSX2', status: 'Downloading...')]);
    expect(out.last.error, isNotNull);
    expect(record, isNull);
  });
}
