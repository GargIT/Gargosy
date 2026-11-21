import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'romm_images.dart';

/// How a cover URL becomes a picture: through the RomM image cache (the
/// server's certificate setting, kept on disk); tests swap in a plain box.
final coverImageBuilderProvider = Provider<Widget Function(String url)>((ref) {
  final cache = ref.watch(rommImageCacheProvider);
  return (url) => CachedNetworkImage(
    imageUrl: url,
    cacheManager: cache,
    fit: BoxFit.cover,
    fadeInDuration: GMotion.fast,
    fadeOutDuration: GMotion.fast,
    placeholder: (context, url) => const CoverArt(),
    errorWidget: (context, url, error) => const CoverArt(),
  );
});

/// A cover, or v2's placeholder art with the title when there is none.
class CoverImage extends ConsumerWidget {
  const CoverImage({super.key, this.url, this.title, this.width, this.height, this.radius = GRadius.card});

  final String? url;
  final String? title;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Under a loaded cover the gradient was never seen, and drawing it under every
            // cover cost a Collections frame about 25 ms (#315): the builder shows it while
            // the cover loads or when it doesn't.
            if (url == null) const CoverArt(),
            if (url == null && title != null)
              Padding(
                padding: const EdgeInsets.all(GSpace.s3),
                child: Center(
                  child: Text(
                    title!,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            if (url != null) ref.watch(coverImageBuilderProvider)(url!),
          ],
        ),
      ),
    );
  }
}

/// v2's placeholder art: what shows where a cover isn't (yet).
class CoverArt extends StatelessWidget {
  const CoverArt({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [GColors.coverArtBase, GColors.coverArtShade],
      ),
    ),
  );
}
