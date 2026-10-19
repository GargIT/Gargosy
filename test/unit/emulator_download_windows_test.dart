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
    adapter.onGet(
      'https://api.github.com/repos/PCSX2/pcsx2/releases/latest',
      (s) => s.reply(200, {
        'assets': [
          asset('pcsx2-v2.8.2-linux-appimage-x64-Qt.AppImage'),
          asset('pcsx2-v2.8.2-windows-x64-Qt-symbols.7z'),
          asset('pcsx2-v2.8.2-windows-arm64-Qt.7z'),
          asset('pcsx2-v2.8.2-windows-x64-Qt.7z'),
          asset('pcsx2-v2.8.2-macos-Qt.tar.xz'),
        ],
      }),
    );
    expect(await service.resolveCurrentDownloadUrl('pcsx2'), 'https://dl/pcsx2-v2.8.2-windows-x64-Qt.7z');
  });

  test("RetroArch's (a direct link) is its Windows link", () async {
    expect(await service.resolveCurrentDownloadUrl('retroarch'), contains('/windows/x86_64/RetroArch.7z'));
  });

  test("Dolphin's download is its Windows x64 build, from the update API Dolphin's own updater reads", () async {
    // dolphin-emu.org/download/ is behind a bot check that answers programs with a 403 page.
    adapter.onGet(
      'https://dolphin-emu.org/update/latest/beta',
      (s) => s.reply(200, {
        'shortrev': '2609a',
        'artifacts': [
          for (final (system, file) in [
            ('Linux x86_64 (Flatpak)', 'dolphin-2609a-x86_64.flatpak'),
            ('Android', 'dolphin-2609a.apk'),
            ('macOS (ARM/Intel Universal)', 'dolphin-2609a-universal.dmg'),
            ('Windows arm64', 'dolphin-2609a-arm64.7z'),
            ('Windows x64', 'dolphin-2609a-x64.7z'),
          ])
            {'system': system, 'url': 'https://dl.dolphin-emu.org/releases/2609a/$file'},
        ],
      }),
    );
    expect(
      await service.resolveCurrentDownloadUrl('dolphin'),
      'https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a-x64.7z',
    );
  });

  test("DuckStation's download is the portable x64 zip, not the installer or the SSE2 build", () async {
    // In the release's own order: the installer comes first.
    adapter.onGet(
      'https://api.github.com/repos/stenzek/duckstation/releases/latest',
      (s) => s.reply(200, {
        'assets': [
          asset('duckstation-windows-x64-installer.exe'),
          asset('duckstation-windows-x64-release.zip'),
          asset('duckstation-windows-x64-sse2-installer.exe'),
          asset('duckstation-windows-x64-sse2-release.zip'),
          asset('duckstation-windows-arm64-release.zip'),
        ],
      }),
    );
    expect(await service.resolveCurrentDownloadUrl('duckstation'), 'https://dl/duckstation-windows-x64-release.zip');
  });

  test("with GitHub's API quota used up, the download is still the latest release, never a pre-release", () async {
    adapter.onGet(
      'https://api.github.com/repos/xemu-project/xemu/releases/latest',
      (s) => s.reply(403, {'message': 'API rate limit exceeded'}),
    );
    // The website's /releases/latest points at the latest real release (the
    // feed would list the newer "pre-release" first).
    adapter.onGet(
      'https://github.com/xemu-project/xemu/releases/latest',
      (s) => s.reply(
        302,
        '',
        headers: {
          'location': ['https://github.com/xemu-project/xemu/releases/tag/v0.8.136'],
        },
      ),
    );
    // The release's files as its page lists them, as plain HTML (the mock
    // adapter would JSON-encode a text reply).
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (o.uri.toString() != 'https://github.com/xemu-project/xemu/releases/expanded_assets/v0.8.136') {
            return h.next(o);
          }
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: '''
        <a href="/xemu-project/xemu/releases/download/v0.8.136/xemu-v0.8.136-x86_64.AppImage">AppImage</a>
        <a href="/xemu-project/xemu/releases/download/v0.8.136/xemu-win-x86_64-release.zip">zip</a>
        <a href="/xemu-project/xemu/releases/download/v0.8.136/xemu-win-x86_64-release-pdb.zip">pdb</a>
        ''',
            ),
          );
        },
      ),
    );
    expect(
      await service.resolveCurrentDownloadUrl('xemu'),
      'https://github.com/xemu-project/xemu/releases/download/v0.8.136/xemu-win-x86_64-release.zip',
    );
  });

  test('a symbols package is never the download', () async {
    adapter.onGet(
      'https://api.github.com/repos/stenzek/duckstation/releases/latest',
      (s) => s.reply(200, {
        'assets': [asset('duckstation-windows-x64-release-symbols.zip'), asset('duckstation-windows-x64-release.zip')],
      }),
    );
    expect(await service.resolveCurrentDownloadUrl('duckstation'), 'https://dl/duckstation-windows-x64-release.zip');
  });
}
