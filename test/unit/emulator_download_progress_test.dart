import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_download_service.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/extraction/extraction_service.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Temp extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Temp(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _Dirs extends Fake implements DirectoryService {
  _Dirs(this.dir);
  final String dir;
  @override
  Future<String?> getEmulatorUrlOverride(String emulatorId) async => null;
  @override
  Future<String> getEmulatorDirectory(String emulatorId) async => dir;
}

class _Extract extends Fake implements ExtractionService {}

class _Registry extends Fake implements StrategyRegistry {}

/// Serves a 4-byte download in two halves; the second waits for [gate].
class _HalvesAdapter implements HttpClientAdapter {
  final gate = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = StreamController<Uint8List>();
    () async {
      body.add(Uint8List.fromList([1, 2]));
      await gate.future;
      body.add(Uint8List.fromList([3, 4]));
      await body.close();
    }();
    return ResponseBody(
      body.stream,
      200,
      headers: {
        'content-length': ['4'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('download progress reaches the screen while the download runs, not all at the end', () async {
    final tmp = await io.Directory.systemTemp.createTemp('gargosy_dl_progress');
    addTearDown(() => tmp.delete(recursive: true));
    final was = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Temp(tmp.path);
    addTearDown(() => PathProviderPlatform.instance = was);

    final adapter = _HalvesAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final dirs = _Dirs(tmp.path);
    final service = EmulatorDownloadService(
      dio,
      dirs,
      _Extract(),
      _Registry(),
      platform: const PlatformInfo('windows'),
    );

    final half = Completer<void>();
    final done = Completer<void>();
    service.downloadEmulator('pcsx2', urlOverride: 'https://example.test/pcsx2.7z').listen((pr) {
      if (pr.percent == 0.5 && !half.isCompleted) half.complete();
    }, onDone: done.complete);

    // Half the bytes are in: the screen must already know, before the rest comes.
    await half.future.timeout(const Duration(seconds: 5), onTimeout: () => fail('no 50 % before the download ended'));
    adapter.gate.complete();
    await done.future; // the download's file is closed and gone before the folder is
  });
}
