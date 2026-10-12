import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/update/app_files.dart';
import 'package:gargosy/update/update_checker.dart';
import 'package:gargosy/update/update_downloader.dart';
import 'package:gargosy/update/update_version.dart';
import 'package:path/path.dart' as p;

import '../../helpers/profile_test_env.dart';

/// Serves [bytes] for any download; [cancelAfterFirstChunk] cancels mid-way.
class _ZipServer implements HttpClientAdapter {
  _ZipServer(this.bytes);
  Uint8List bytes;
  int status = 200;
  CancelToken? cancelMidway;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (cancelMidway != null) {
      final token = cancelMidway!;
      final half = bytes.length ~/ 2;
      Stream<Uint8List> chunks() async* {
        yield Uint8List.sublistView(bytes, 0, half);
        token.cancel('B');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        yield Uint8List.sublistView(bytes, half);
      }

      return ResponseBody(chunks(), status, headers: {
        Headers.contentLengthHeader: ['${bytes.length}'],
      });
    }
    return ResponseBody.fromBytes(bytes, status, headers: {
      Headers.contentLengthHeader: ['${bytes.length}'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Uint8List releaseZip(Map<String, String> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final data = Uint8List.fromList(e.value.codeUnits);
    archive.addFile(ArchiveFile(e.key, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, String> goodRelease({String list = 'Gargosy.exe\r\napp-files.txt\r\ndata\\icudtl.dat\r\n'}) => {
      'Gargosy/Gargosy.exe': 'MZ new',
      'Gargosy/app-files.txt': list,
      'Gargosy/data/icudtl.dat': 'icu',
      'Gargosy/userdata/settings.json': '{"should":"never be unpacked"}',
      'Gargosy/roms/readme.txt': 'never unpacked either',
    };

void main() {
  late AppRoot root;
  late _ZipServer server;
  late UpdateDownloader downloader;

  setUp(() async {
    root = await tempAppRoot();
    server = _ZipServer(releaseZip(goodRelease()));
    downloader = UpdateDownloader(dio: Dio()..httpClientAdapter = server, root: root);
  });
  tearDown(() => deleteTempDir(root.root));

  ReleaseInfo release({int? size, String? sha}) => ReleaseInfo(
        version: UpdateVersion.parse('0.2.0')!,
        assetName: 'Gargosy-0.2.0.zip',
        assetUrl: 'https://github.com/GargIT/Gargosy/releases/download/v0.2.0/Gargosy-0.2.0.zip',
        size: size ?? server.bytes.length,
        sha256: sha,
        htmlUrl: 'https://github.com/GargIT/Gargosy/releases/tag/v0.2.0',
      );

  List<String> leftovers() {
    final dir = io.Directory(downloader.paths.dir);
    return dir.existsSync() ? dir.listSync().map((e) => p.basename(e.path)).toList() : [];
  }

  test('downloads into userdata\\app\\update, checks it and unpacks without the top folder', () async {
    final progress = <int>[];
    final sha = sha256.convert(server.bytes).toString();
    final out = await downloader.download(release(sha: sha.toUpperCase()), onProgress: (r, t) => progress.add(r));
    expect(out, p.join(root.appData, 'update', 'Gargosy'));
    expect(io.File(p.join(out, 'Gargosy.exe')).readAsStringSync(), 'MZ new');
    expect(io.File(p.join(out, 'data', 'icudtl.dat')).existsSync(), isTrue);
    expect(io.File(downloader.paths.zip('0.2.0')).existsSync(), isTrue);
    expect(progress.last, server.bytes.length);
  });

  test("the user's folders in the zip are never unpacked", () async {
    final out = await downloader.download(release());
    expect(io.Directory(p.join(out, 'userdata')).existsSync(), isFalse);
    expect(io.Directory(p.join(out, 'roms')).existsSync(), isFalse);
  });

  test('a wrong size deletes the download and says why', () async {
    await expectLater(downloader.download(release(size: 12)),
        throwsA(isA<UpdateDownloadException>().having((e) => e.message, 'message', contains('GitHub says 12'))));
    expect(leftovers(), isEmpty);
  });

  test('a wrong SHA-256 deletes the download', () async {
    await expectLater(downloader.download(release(sha: 'ab' * 32)),
        throwsA(isA<UpdateDownloadException>().having((e) => e.message, 'message', contains('checksum'))));
    expect(leftovers(), isEmpty);
  });

  test('a zip without Gargosy.exe is refused', () async {
    server.bytes = releaseZip({'Gargosy/app-files.txt': 'app-files.txt\n'});
    await expectLater(downloader.download(release()),
        throwsA(isA<UpdateDownloadException>().having((e) => e.message, 'message', contains('no Gargosy.exe'))));
    expect(leftovers(), isEmpty);
  });

  test('a zip without app-files.txt is refused', () async {
    server.bytes = releaseZip({'Gargosy/Gargosy.exe': 'MZ'});
    await expectLater(downloader.download(release()), throwsA(isA<UpdateDownloadException>()));
  });

  test('a list naming a file the zip lacks is refused', () async {
    server.bytes = releaseZip(goodRelease(list: 'Gargosy.exe\nsigil.dll\n'));
    await expectLater(downloader.download(release()),
        throwsA(isA<UpdateDownloadException>().having((e) => e.message, 'message', contains('sigil.dll'))));
  });

  test("a list naming the user's folders is refused", () async {
    server.bytes = releaseZip(goodRelease(list: 'Gargosy.exe\nuserdata\\settings.json\n'));
    await expectLater(downloader.download(release()), throwsA(isA<UpdateDownloadException>()));
  });

  test('a zip that is not a Gargosy release (no Gargosy\\ top folder) is refused', () async {
    server.bytes = releaseZip({'Gargosy.exe': 'MZ', 'app-files.txt': 'Gargosy.exe'});
    await expectLater(downloader.download(release()), throwsA(isA<UpdateDownloadException>()));
    expect(leftovers(), isEmpty);
  });

  test('a zip entry escaping its folder is refused (no zip-slip)', () async {
    server.bytes = releaseZip({...goodRelease(), 'Gargosy/../../evil.txt': 'x'});
    await expectLater(downloader.download(release()), throwsA(isA<UpdateDownloadException>()));
    expect(io.File(p.join(root.root, 'evil.txt')).existsSync(), isFalse);
    expect(io.File(p.join(root.appData, 'evil.txt')).existsSync(), isFalse);
  });

  test('a cancelled download leaves nothing behind', () async {
    final cancel = CancelToken();
    server.cancelMidway = cancel;
    await expectLater(downloader.download(release(), cancel: cancel),
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)));
    expect(leftovers(), isEmpty);
  });

  test('a server error says the download did not finish', () async {
    server.status = 500;
    await expectLater(downloader.download(release()), throwsA(isA<UpdateDownloadException>()));
    expect(leftovers(), isEmpty);
  });

  group('AppFiles.parse', () {
    test('Windows lines, backslashes, blank lines', () {
      expect(AppFiles.parse('Gargosy.exe\r\n\r\ndata/flutter_assets/AssetManifest.bin\r\n'),
          ['Gargosy.exe', r'data\flutter_assets\AssetManifest.bin']);
    });

    for (final bad in [r'..\Gargosy.exe', r'C:\Windows\x.dll', r'\abs.dll', 'userdata\\settings.json', 'Roms\\a.iso', r'data\..\..\x', '']) {
      test('refuses "$bad"', () => expect(() => AppFiles.parse(bad), throwsFormatException));
    }
  });
}
