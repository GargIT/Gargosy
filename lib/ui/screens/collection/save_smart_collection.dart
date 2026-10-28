import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_library_api.dart';
import '../../../library/smart_criteria.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../widgets/toast.dart';
import 'collection_screen.dart';

/// Saves the gallery [query] as a smart collection on RomM (#188), then opens
/// it. What RomM can't run ([thisPc], the Downloaded order) is said first;
/// a gallery without a filter or a scope isn't saved. Returns the new
/// collection, or null when the player backed out or RomM refused (said).
Future<RommCollection?> saveAsSmartCollection(
  BuildContext context,
  WidgetRef ref,
  GalleryQuery query, {
  bool thisPc = false,
}) async {
  final edits = ref.read(collectionEditsProvider);
  if (edits == null || !canSaveAsSmart(query)) return null;
  final smart = smartCriteriaOf(query, thisPc: thisPc);
  if (!smart.picksSomething) {
    showToast(context, 'Pick a filter first: a smart collection of everything is the library.');
    return null;
  }
  if (smart.leftOut.isNotEmpty) {
    final ok = await showConfirm(
      context,
      title: "${_list(smart.leftOut)} can't be saved",
      body: "RomM can't run ${_list(smart.leftOut)}. The smart collection holds RomM's games that match the rest.",
      yes: 'Save the rest',
      no: 'Cancel',
    );
    if (!ok || !context.mounted) return null;
  }
  final name = (await showOnScreenKeyboard(context, title: 'New smart collection'))?.trim();
  if (name == null || name.isEmpty || !context.mounted) return null;
  final who = await showChoice(
    context,
    title: 'Who sees $name?',
    labels: const ['Only you', 'Every player on RomM (shared)'],
    current: 0,
  );
  if (who == null) return null;
  try {
    final made = await edits.createSmart(name, smart.criteria, shared: who == 1);
    ref.invalidate(smartCollectionsProvider);
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CollectionScreen(collection: made)));
    }
    return made;
  } on Object catch (e) {
    if (context.mounted) showToast(context, "Couldn't make $name: $e");
    return null;
  }
}

String _list(List<String> items) => items.length == 1 ? items.single : '${items.first} and ${items.last}';
