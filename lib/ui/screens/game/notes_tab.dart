import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/format.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// Your notes on the game, kept on RomM (new ones are private).
class NotesTab extends ConsumerWidget {
  const NotesTab({super.key, required this.game});

  final Game game;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = await showOnScreenKeyboard(context, title: tr('Note title'));
    if (title == null || title.trim().isEmpty || !context.mounted) return;
    final content = await showOnScreenKeyboard(context, title: tr('Note'));
    if (content == null) return;
    try {
      await ref.read(libraryApiProvider)?.addNote(game.id, title.trim(), content);
    } on Object catch (e) {
      if (context.mounted) showToast(context, tr('Couldn\'t save the note: {0}', [e]));
      return;
    }
    ref.invalidate(romNotesProvider(game.id));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, RomNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Delete "{0}"?', [note.title])),
        content: Text(tr('The note is deleted from RomM.')),
        actions: [
          GFocusable(
            autofocus: true,
            borderRadius: GRadius.pill,
            onActivate: () => Navigator.of(c).pop(false),
            child: Padding(padding: const EdgeInsets.all(GSpace.s3), child: Text(tr('Keep'))),
          ),
          GFocusable(
            borderRadius: GRadius.pill,
            onActivate: () => Navigator.of(c).pop(true),
            child: Padding(
              padding: const EdgeInsets.all(GSpace.s3),
              child: Text(tr('Delete'), style: const TextStyle(color: GColors.danger)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(libraryApiProvider)?.deleteNote(game.id, note.id);
    } on Object catch (e) {
      if (context.mounted) showToast(context, tr('Couldn\'t delete the note: {0}', [e]));
      return;
    }
    ref.invalidate(romNotesProvider(game.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(romNotesProvider(game.id));
    return ListView(
      padding: const EdgeInsets.only(bottom: GSpace.s14),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: GFocusable(
            borderRadius: GRadius.pill,
            onActivate: () => _add(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
              decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 18),
                  const SizedBox(width: GSpace.s2),
                  Text(tr('Add a note'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: GSpace.s4),
        ...notes.when(
          loading: () => [const LinearProgressIndicator()],
          error: (e, _) => [
            SizedBox(
              height: 180,
              child: ErrorRetry(
                message: describeLoadError(e),
                onRetry: () => ref.invalidate(romNotesProvider(game.id)),
              ),
            ),
          ],
          data: (list) => list.isEmpty
              ? [Text(tr('No notes yet.'), style: const TextStyle(color: GColors.fgMuted))]
              : [
                  for (final n in list)
                    GFocusable(
                      borderRadius: GRadius.md,
                      onDetail: () => _delete(context, ref, n),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: GSpace.s2),
                        padding: const EdgeInsets.all(GSpace.s3),
                        decoration: BoxDecoration(
                          color: GColors.surface,
                          borderRadius: BorderRadius.circular(GRadius.md),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title,
                              style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: GSpace.s1),
                            Text(n.content, style: const TextStyle(color: GColors.fgSecondary)),
                            if (n.updatedAt ?? n.createdAt case final d?)
                              Text(
                                formatDate(d),
                                style: const TextStyle(fontSize: GFont.xs, color: GColors.fgFaint),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
        ),
      ],
    );
  }
}
