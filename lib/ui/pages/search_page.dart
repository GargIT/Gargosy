import 'package:flutter/material.dart';

import '../../core/romm/romm_library_api.dart';
import '../screens/gallery_view.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/on_screen_keyboard.dart';

/// Search the library (spec §2). A on the box opens the on-screen keyboard.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _term = '';

  Future<void> _edit() async {
    final v = await showOnScreenKeyboard(context, title: 'Search', initial: _term);
    if (v != null && mounted) setState(() => _term = v.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('page-Search'),
      padding: const EdgeInsets.only(top: GLayout.navHeight + GSpace.s6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad),
            child: GFocusable(
              autofocus: true,
              borderRadius: GRadius.pill,
              onActivate: _edit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s4),
                decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: GColors.fgMuted),
                    const SizedBox(width: GSpace.s3),
                    Text(
                      _term.isEmpty ? 'Search your library' : _term,
                      style: TextStyle(fontSize: GFont.xl, color: _term.isEmpty ? GColors.fgMuted : GColors.fg),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _term.isEmpty
                ? const Center(
                    child: Text('Type a name to find a game.', style: TextStyle(color: GColors.fgMuted)),
                  )
                : GalleryView(
                    key: ValueKey(_term),
                    query: GalleryQuery(search: _term),
                    emptyText: 'Nothing matches "$_term".',
                    autofocus: false,
                  ),
          ),
        ],
      ),
    );
  }
}
