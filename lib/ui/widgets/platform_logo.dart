import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/romm_providers.dart';
import '../theme/tokens.dart';
import 'ico_png.dart';
import 'romm_images.dart';
import 'svg_styles.dart';

/// RomM's icon for a platform slug on the profile's server (what RomM's web
/// UI shows); null without a server.
final platformLogoUrlProvider = Provider<String? Function(String slug)>((ref) {
  final base = ref.watch(rommServiceProvider)?.config.baseUrl;
  if (base == null) return (_) => null;
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return (slug) => '$root/assets/platforms/$slug.svg';
});

/// Draws RomM's icon from the RomM image cache (the server's certificate
/// setting, kept on disk): the .svg, else the .ico RomM has for some
/// platforms (C64, DOS, …), as RomM's web UI does; [fallback] while it
/// loads and when RomM has neither.
final platformLogoBuilderProvider = Provider<Widget Function(String url, double size, Widget fallback)>(
  (ref) => (url, size, fallback) => _CachedLogo(url: url, size: size, fallback: fallback),
);

/// Icon files RomM doesn't have (a 404): not asked for again this session.
final _missingLogosProvider = Provider<Set<String>>((ref) => {});

/// A loaded icon: an SVG (styles inlined) or a PNG (from an .ico).
typedef _Logo = ({String? svg, Uint8List? png});

class _CachedLogo extends ConsumerStatefulWidget {
  const _CachedLogo({required this.url, required this.size, required this.fallback});
  final String url;
  final double size;
  final Widget fallback;

  @override
  ConsumerState<_CachedLogo> createState() => _CachedLogoState();
}

class _CachedLogoState extends ConsumerState<_CachedLogo> {
  Future<_Logo?>? _logo;

  /// [url]'s bytes from the cache; null when RomM hasn't got it.
  Future<Uint8List?> _fetch(String url) async {
    final missing = ref.read(_missingLogosProvider);
    if (missing.contains(url)) return null;
    try {
      return (await ref.read(rommImageCacheProvider).getSingleFile(url)).readAsBytesSync(); // a few KB
    } catch (_) {
      missing.add(url);
      return null;
    }
  }

  Future<_Logo?> _load() async {
    final svg = await _fetch(widget.url);
    // RomM's icons colour their shapes with CSS classes, which flutter_svg doesn't read.
    if (svg != null) return (svg: inlineSvgStyles(utf8.decode(svg, allowMalformed: true)), png: null);
    final ico = await _fetch(widget.url.replaceFirst(RegExp(r'\.svg$'), '.ico'));
    final png = ico == null ? null : pngFromIco(ico);
    return png == null ? null : (svg: null, png: png);
  }

  @override
  Widget build(BuildContext context) {
    _logo ??= _load();
    return FutureBuilder<_Logo?>(
      future: _logo,
      builder: (context, snap) {
        final logo = snap.data;
        if (logo?.svg case final svg?) {
          return SvgPicture.string(
            svg,
            width: widget.size,
            height: widget.size,
            placeholderBuilder: (_) => widget.fallback,
            errorBuilder: (_, _, _) => widget.fallback,
          );
        }
        if (logo?.png case final png?) {
          return Image.memory(
            png,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => widget.fallback,
          );
        }
        return widget.fallback;
      },
    );
  }
}

/// "PS2" for ps2: what the badge says when there's no icon.
String badgeLabel(String slug) {
  final s = slug.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return s.length <= 4 ? s : s.substring(0, 4);
}

/// The platform's logo; a badge when RomM has none.
class PlatformLogo extends ConsumerWidget {
  const PlatformLogo({super.key, required this.slug, this.size = 32});
  final String slug;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = PlatformBadge(slug: slug, size: size);
    final url = ref.watch(platformLogoUrlProvider)(slug);
    if (url == null) return fallback;
    return SizedBox(width: size, height: size, child: ref.watch(platformLogoBuilderProvider)(url, size, fallback));
  }
}

/// A rounded square with a short name, where an icon would be.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge({super.key, required this.slug, this.size = 32});
  final String slug;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('platform-badge'),
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: GColors.surfaceHover, borderRadius: BorderRadius.circular(size * 0.28)),
    child: FittedBox(
      child: Padding(
        padding: EdgeInsets.all(size * 0.15),
        child: Text(
          badgeLabel(slug),
          style: const TextStyle(fontWeight: FontWeight.w900, color: GColors.fgSecondary),
        ),
      ),
    ),
  );
}
