import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../../l10n/tr.dart';

enum ProfileOption { delete }

/// X on a badge: what you can do with a profile. Milestone A: delete.
Future<ProfileOption?> showProfileOptions(BuildContext context, {required String name}) => showDialog<ProfileOption>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(name),
    content: GFocusable(
      autofocus: true,
      borderRadius: GRadius.md,
      onActivate: () => Navigator.of(c).pop(ProfileOption.delete),
      child: Padding(
        padding: const EdgeInsets.all(GSpace.s3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, color: GColors.danger),
            const SizedBox(width: GSpace.s3),
            Text(tr('Delete profile'), style: const TextStyle(fontSize: GFont.lg)),
          ],
        ),
      ),
    ),
  ),
);

/// The last question before deleting. Says that nothing on RomM is touched.
Future<bool> confirmDeleteProfile(BuildContext context, {required String name}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Delete {0}?', [name])),
      content: Text(
        tr(
          'This removes the profile and its saves, states and emulator settings from this PC. Nothing on the RomM server is deleted.',
        ),
      ),
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
  return ok ?? false;
}
