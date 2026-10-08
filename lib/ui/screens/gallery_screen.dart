import 'package:flutter/material.dart';

import '../../core/input/gamepad_service.dart';
import '../../core/romm/romm_library_api.dart';
import '../shell/backdrop.dart';
import '../theme/tokens.dart';
import '../widgets/hint_bar.dart';
import 'gallery_view.dart';

/// A platform's, a collection's or the favourites' games (spec §2).
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key, required this.title, required this.query});

  final String title;
  final GalleryQuery query;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: Column(children: [
          const SizedBox(height: GSpace.s8),
          Expanded(child: GalleryView(title: title, query: query)),
          const HintBar(hints: [
            Hint(GameAction.confirm, 'Open'),
            Hint(GameAction.favorite, 'Favourite'),
            Hint(GameAction.detail, 'Sort & filter'),
            Hint(GameAction.back, 'Back'),
          ]),
        ]),
      ),
    );
  }
}
