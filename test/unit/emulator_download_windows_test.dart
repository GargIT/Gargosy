import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_download_service.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/extraction/extraction_service.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

class _Dirs extends Fake implements DirectoryService {
  @override
  Future<String?> getEmulatorUrlOverride(String emulatorId) async => null;
}

class _Extract extends Fake implements ExtractionService {}

class _Registry extends Fake implements StrategyRegistry {}

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late EmulatorDownloadService service;

  setUp(() {
    dio = Dio();
    adapter = DioAdapter(dio: dio);
    service = EmulatorDownloadService(dio, _Dirs(), _Extract(), _Registry(), platform: const PlatformInfo('windows'));
  });

  Map<String, dynamic> asset(String name) => {'name': name, 'browser_download_url': 'https://dl/$name'};

  test("on Windows, PCSX2's latest download is the Windows build, not the release's first file", () async {
    adapter.onGet('https://api.github.com/repos/PCSX2/pcsx2/releases/latest', (s) => s.reply(200, {
          'assets': [
            asset('pcsx2-v2.8.2-linux-appimage-x64-Qt.AppImage'),
            asset('pcsx2-v2.8.2-windows-x64-Qt-symbols.7z'),
            asset('pcsx2-v2.8.2-windows-arm64-Qt.7z'),
            asset('pcsx2-v2.8.2-windows-x64-Qt.7z'),
            asset('pcsx2-v2.8.2-macos-Qt.tar.xz'),
          ],
        }));
    expect(await service.resolveCurrentDownloadUrl('pcsx2'), 'https://dl/pcsx2-v2.8.2-windows-x64-Qt.7z');
  });

  test("RetroArch's (a direct link) is its Windows link", () async {
    expect(await service.resolveCurrentDownloadUrl('retroarch'), contains('/windows/x86_64/RetroArch.7z'));
  });

  test('a symbols package is never the download', () async {
    adapter.onGet('https://api.github.com/repos/stenzek/duckstation/releases/latest', (s) => s.reply(200, {
          'assets': [asset('duckstation-windows-x64-release-symbols.zip'), asset('duckstation-windows-x64-release.zip')],
        }));
    expect(await service.resolveCurrentDownloadUrl('duckstation'), 'https://dl/duckstation-windows-x64-release.zip');
  });
}
