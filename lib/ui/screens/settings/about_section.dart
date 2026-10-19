import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/input/gamepad_service.dart';
import '../../../profiles/path_guard.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/about_providers.dart';
import '../../../providers/update_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/hint_bar.dart';
import '../doc_reader_screen.dart';
import 'settings_rows.dart';
import 'updates_block.dart';

const gargosyRepoUrl = 'https://github.com/GargIT/Gargosy';

/// About, from the user menu: a small dialog over the current page.
Future<void> showAboutGargosy(BuildContext context) => showDialog<void>(
  context: context,
  builder: (c) => Center(
    child: Material(
      color: GColors.panel,
      borderRadius: BorderRadius.circular(GRadius.lg),
      child: const SizedBox(
        width: 460,
        child: Padding(
          padding: EdgeInsets.all(GSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(child: SingleChildScrollView(child: AboutSection(autofocus: true))),
              HintBar(hints: [Hint(GameAction.confirm, 'Open'), Hint(GameAction.back, 'Close')]),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// About: Gargosy's and RomM's versions, then the documents in the Gargosy
/// folder (opened in the reader), the Flutter package licences, the log
/// folder (for bug reports), GitHub and Updates (issue #16).
/// The About dialog and Settings → About.
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key, this.autofocus = false});

  /// Focus the first document when shown: the dialog has no other focus.
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = ref.watch(appRootProvider);
    final romm = ref.watch(rommServerVersionProvider);
    final version = AppConstants.version;
    final outcome = updateOutcomeLine(ref.watch(updateOutcomeProvider), version);
    final rommText = romm.when(
      data: (v) => v == null ? 'not reachable' : 'v$v',
      loading: () => '…',
      error: (_, _) => 'not reachable',
    );

    Widget doc(IconData icon, String label, String name, {bool focus = false}) => SettingsLinkRow(
      icon: icon,
      label: label,
      value: name,
      autofocus: focus,
      onActivate: () => openDoc(context, p.join(root.root, name)),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: GSpace.s4),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(GRadius.md),
                child: Image.asset(
                  'assets/branding/gargosy_logo.png',
                  width: 56,
                  height: 56,
                  errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56),
                ),
              ),
              const SizedBox(width: GSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gargosy v$version',
                      style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: GSpace.s1),
                    Text('RomM $rommText', style: const TextStyle(color: GColors.fgSecondary)),
                    if (outcome != null) ...[
                      const SizedBox(height: GSpace.s1),
                      Text(
                        outcome,
                        key: const Key('update-outcome'),
                        style: const TextStyle(color: GColors.primary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        doc(Icons.history, "What's new", 'CHANGELOG.md', focus: autofocus),
        doc(Icons.description_outlined, 'Read me', 'README.md'),
        doc(Icons.verified_outlined, 'Licences', 'NOTICE.md'),
        doc(Icons.lock_outline, 'Security policy', 'SECURITY.md'),
        SettingsLinkRow(
          icon: Icons.inventory_2_outlined,
          label: 'Dart and Flutter packages',
          onActivate: () =>
              showLicensePage(context: context, applicationName: 'Gargosy', applicationVersion: 'v$version'),
        ),
        SettingsLinkRow(
          icon: Icons.folder_open_outlined,
          label: 'Open log folder',
          value: r'userdata\app\logs',
          onActivate: () {
            // Made when missing (a start that couldn't write it), so Explorer opens the folder.
            try {
              io.Directory(PathGuard(root).check(root.logs)).createSync(recursive: true);
            } on Object catch (e) {
              debugPrint('[About] log folder: $e');
            }
            ref.read(externalOpenerProvider)(root.logs);
          },
        ),
        SettingsLinkRow(
          icon: Icons.open_in_new,
          label: 'GitHub',
          value: gargosyRepoUrl.replaceFirst('https://', ''),
          onActivate: () => ref.read(externalOpenerProvider)(gargosyRepoUrl),
        ),
        const UpdatesBlock(),
      ],
    );
  }
}
