import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/ui/widgets/cover_image.dart';
import 'package:gargosy/ui/widgets/platform_logo.dart';
import 'package:gargosy/ui/widgets/romm_images.dart';
import 'package:path/path.dart' as p;

RomMConfig _config({bool trust = true}) =>
    RomMConfig(baseUrl: 'https://romm.home:8443/', username: 'u', password: 'p', trustSelfSigned: trust);

/// Hands out [byUrl]'s file for a URL, else [file], else fails like a 404;
/// records what was asked.
class _FakeCache extends Fake implements BaseCacheManager {
  _FakeCache([this.file, this.byUrl = const {}]);
  final io.File? file;
  final Map<String, io.File> byUrl;
  final asked = <String>[];

  @override
  Future<fs.File> getSingleFile(String url, {String? key, Map<String, String>? headers}) async {
    asked.add(url);
    final f = byUrl.isNotEmpty ? byUrl[url] : file;
    if (f == null) throw HttpExceptionWithStatus(404, 'Not found', uri: Uri.parse(url));
    return const LocalFileSystem().file(f.path);
  }
}

/// A one-colour PNG, wrapped in an .ico as RomM serves some icons.
Future<Uint8List> _redIco(WidgetTester tester) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = const Color(0xFFFF0000));
  final image = await recorder.endRecording().toImage(16, 16);
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  final dir = ByteData(16)
    ..setUint8(0, 16)
    ..setUint8(1, 16)
    ..setUint16(6, 32, Endian.little)
    ..setUint32(8, png.length, Endian.little)
    ..setUint32(12, 22, Endian.little);
  return Uint8List.fromList([0, 0, 1, 0, 1, 0, ...dir.buffer.asUint8List(), ...png]);
}))!;

void main() {
  test("a self-signed certificate is trusted only from the profile's own server, and only when it says so", () {
    expect(trustCertificate(_config(), 'romm.home'), isTrue);
    expect(trustCertificate(_config(), 'images.igdb.com'), isFalse);
    expect(trustCertificate(_config(trust: false), 'romm.home'), isFalse);
    expect(trustCertificate(null, 'romm.home'), isFalse);
  });

  test('covers load through the RomM image cache (the server\'s certificate setting, kept on disk)', () {
    final cache = _FakeCache();
    final c = ProviderContainer(overrides: [rommImageCacheProvider.overrideWithValue(cache)]);
    addTearDown(c.dispose);
    final cover = c.read(coverImageBuilderProvider)('https://romm.home:8443/assets/romm/resources/1/cover.png');
    expect(cover, isA<CachedNetworkImage>());
    expect(identical((cover as CachedNetworkImage).cacheManager, cache), isTrue);
  });

  group('logos', () {
    late io.Directory tmp;
    setUp(() => tmp = io.Directory.systemTemp.createTempSync('gargosy-logo-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> pumpLogo(WidgetTester tester, ProviderContainer c, String slug) async {
      final fallback = PlatformBadge(slug: slug);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Center(
              child: Consumer(
                builder: (context, ref, _) => ref.watch(platformLogoBuilderProvider)(
                  'https://romm.home/assets/platforms/$slug.svg',
                  32,
                  fallback,
                ),
              ),
            ),
          ),
        ),
      );
      // Real file reads: a few rounds of real time and frames.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    testWidgets('come from the RomM image cache and are drawn from the file', (tester) async {
      final svg = io.File(p.join(tmp.path, 'ps2.svg'))
        ..writeAsStringSync(
          '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8"/></svg>',
        );
      final cache = _FakeCache(svg);
      final c = ProviderContainer(overrides: [rommImageCacheProvider.overrideWithValue(cache)]);
      addTearDown(c.dispose);
      await pumpLogo(tester, c, 'ps2');
      expect(cache.asked, ['https://romm.home/assets/platforms/ps2.svg']);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets("RomM's icons are drawn in their colours (set by CSS classes), not black", (tester) async {
      final svg = io.File(p.join(tmp.path, 'red.svg'))
        ..writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><defs><style>.cls-1 { fill: #ff0000; }'
            '</style></defs><rect class="cls-1" width="8" height="8"/></svg>');
      final c = ProviderContainer(overrides: [rommImageCacheProvider.overrideWithValue(_FakeCache(svg))]);
      addTearDown(c.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: Consumer(
                builder: (context, ref, _) => ref.watch(platformLogoBuilderProvider)(
                    'https://romm.home/assets/platforms/red.svg', 32, const PlatformBadge(slug: 'red')),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(find.byType(SvgPicture), findsOneWidget);
      final pixel = (await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final at = (16 * image.width + 16) * 4;
        return [bytes.getUint8(at), bytes.getUint8(at + 1), bytes.getUint8(at + 2)];
      }))!;
      expect(pixel[0], greaterThan(200), reason: 'red, got $pixel');
      expect(pixel[1], lessThan(60), reason: 'red, got $pixel');
    });

    testWidgets("RomM has only an .ico (C64, DOS, …): that one's picture, in its colours", (tester) async {
      final ico = io.File(p.join(tmp.path, 'c64.ico'))..writeAsBytesSync(await _redIco(tester));
      final c = ProviderContainer(overrides: [
        rommImageCacheProvider.overrideWithValue(_FakeCache(null, {'https://romm.home/assets/platforms/c64.ico': ico})),
      ]);
      addTearDown(c.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: Consumer(
                builder: (context, ref, _) => ref.watch(platformLogoBuilderProvider)(
                    'https://romm.home/assets/platforms/c64.svg', 32, const PlatformBadge(slug: 'c64')),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('platform-badge')), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      final pixel = (await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final at = (16 * image.width + 16) * 4;
        return [bytes.getUint8(at), bytes.getUint8(at + 1), bytes.getUint8(at + 2)];
      }))!;
      expect(pixel[0], greaterThan(200), reason: 'red, got $pixel');
    });

    testWidgets("one RomM doesn't have shows the badge and isn't asked for again this session", (tester) async {
      final cache = _FakeCache();
      final c = ProviderContainer(overrides: [rommImageCacheProvider.overrideWithValue(cache)]);
      addTearDown(c.dispose);
      await pumpLogo(tester, c, 'my-homebrew');
      expect(find.byKey(const ValueKey('platform-badge')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pumpLogo(tester, c, 'my-homebrew');
      expect(cache.asked, ['https://romm.home/assets/platforms/my-homebrew.svg', 'https://romm.home/assets/platforms/my-homebrew.ico']);
      expect(find.byKey(const ValueKey('platform-badge')), findsOneWidget);
    });
  });
}
