import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../profiles/profile_providers.dart';
import '../../providers/library_providers.dart';
import '../input/wrap_grid_policy.dart';
import '../screens/gallery_screen.dart';
import '../theme/tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/error_retry.dart';
import '../widgets/g_focusable.dart';

/// Your favourites and RomM's collections (yours and the public ones).
class CollectionsPage extends ConsumerWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    final userId = ref.watch(activeProfileProvider.select((c) => c?.profile.rommUserId));
    return Padding(
      key: const Key('page-Collections'),
      padding: const EdgeInsets.only(top: GLayout.navHeight + GSpace.s6),
      child: collections.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(message: describeLoadError(e), onRetry: () => ref.invalidate(collectionsProvider)),
        data: (all) {
          bool ownFav(RommCollection c) => c.isFavorite && (userId == null || c.userId == userId);
          final list = [
            ...all.where(ownFav),
            ...(all.where((c) => !c.isFavorite).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))),
          ];
          if (list.isEmpty) {
            return const Center(child: Text('No collections yet.', style: TextStyle(color: GColors.fgMuted)));
          }
          return FocusTraversalGroup(
            policy: WrapGridTraversalPolicy(),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s14),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 220,
                mainAxisSpacing: GSpace.s4,
                crossAxisSpacing: GSpace.s4,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final c = list[i];
                final name = c.isFavorite ? 'Favourites' : c.name;
                return GFocusable(
                  autofocus: i == 0,
                  onActivate: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GalleryScreen(
                      title: name,
                      query: c.isFavorite ? const GalleryQuery(favourites: true) : GalleryQuery(collectionId: c.id),
                    ),
                  )),
                  child: Container(
                    decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.card)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: c.isFavorite
                            ? const Center(child: Icon(Icons.favorite, size: 56, color: GColors.fav))
                            : CoverImage(url: assetUrl(ref, c.coverPath), title: c.name),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(GSpace.s3),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name,
                              key: const ValueKey('collection-name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700)),
                          Text('${c.romCount} games', style: const TextStyle(color: GColors.fgMuted)),
                        ]),
                      ),
                    ]),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
