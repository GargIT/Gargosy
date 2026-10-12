import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/input/gamepad_service.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/about_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/hint_bar.dart';
import '../doc_reader_screen.dart';
import 'settings_rows.dart';

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
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AboutSection(autofocus: true),
                HintBar(hints: [Hint(GameAction.confirm, 'Open'), Hint(GameAction.back, 'Close')]),
              ]),
            ),
          ),
        ),
      ),
    );

/// About: Gargosy's and RomM's versions, then the documents in the Gargosy
/// folder (opened in the reader), the Flutter package licences, the log
/// folder (for bug reports) and GitHub.
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
    final rommText =
        romm.when(data: (v) => v == null ? 'not reachable' : 'v$v', loading: () => '…', error: (_, _) => 'not reachable');

    Widget doc(String label, String name, {bool focus = false}) => SettingsRow(
          label: label,
          value: name,
          autofocus: focus,
          onActivate: () => openDoc(context, p.join(root.root, name)),
        );

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: GSpace.s4),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(GRadius.md),
            child: Image.asset('assets/branding/gargosy_logo.png',
                width: 56, height: 56, errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56)),
          ),
          const SizedBox(width: GSpace.s4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Gargosy v$version', style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
              const SizedBox(height: GSpace.s1),
              Text('RomM $rommText', style: const TextStyle(color: GColors.fgSecondary)),
            ]),
          ),
        ]),
      ),
      doc("What's new", 'CHANGELOG.md', focus: autofocus),
      doc('Read me', 'README.md'),
      doc('Licences', 'NOTICE.md'),
      doc('Security policy', 'SECURITY.md'),
      SettingsRow(
        label: 'Dart and Flutter packages',
        onActivate: () => showLicensePage(context: context, applicationName: 'Gargosy', applicationVersion: 'v$version'),
      ),
      SettingsRow(
        label: 'Open log folder',
        value: r'userdata\app\logs',
        onActivate: () => ref.read(externalOpenerProvider)(root.logs),
      ),
      SettingsRow(
        label: 'GitHub',
        value: gargosyRepoUrl.replaceFirst('https://', ''),
        onActivate: () => ref.read(externalOpenerProvider)(gargosyRepoUrl),
      ),
    ]);
  }
}
