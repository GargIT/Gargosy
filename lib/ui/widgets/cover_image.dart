import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';

/// How a cover URL becomes a picture. Cached on disk (in `userdata\app\cache`
/// through Gargosy's path provider); tests swap in a plain box.
final coverImageBuilderProvider = Provider<Widget Function(String url)>((ref) => (url) => CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: GMotion.fast,
      errorWidget: (context, url, error) => const SizedBox.shrink(),
    ));

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
        child: Stack(fit: StackFit.expand, children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [GColors.coverArtBase, GColors.coverArtShade],
              ),
            ),
          ),
          if (url == null && title != null)
            Padding(
              padding: const EdgeInsets.all(GSpace.s3),
              child: Center(
                child: Text(title!,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700)),
              ),
            ),
          if (url != null) ref.watch(coverImageBuilderProvider)(url!),
        ]),
      ),
    );
  }
}
