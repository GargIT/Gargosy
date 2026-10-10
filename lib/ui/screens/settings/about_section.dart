import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/about_providers.dart';
import 'settings_rows.dart';

const gargosyRepoUrl = 'https://github.com/GargIT/Gargosy';

/// About: versions, links and licences. Shared by Settings → About and the
/// user menu's About page.
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key, this.autofocus = false});

  /// Focus the first link when shown: the About page has no other focus.
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.read(externalOpenerProvider);
    final root = ref.watch(appRootProvider);
    final romm = ref.watch(rommServerVersionProvider);
    final version = AppConstants.version;

    Widget link(String label, String url, {bool focus = false}) => SettingsRow(
        label: label, value: url.replaceFirst('https://', ''), onActivate: () => open(url), autofocus: focus);
    Widget file(String label, String name) =>
        SettingsRow(label: label, onActivate: () => open(p.join(root.root, name)));

    return ListView(children: [
      const SettingsHeading('About'),
      SettingsRow(label: 'Gargosy', value: 'v$version'),
      SettingsRow(
        label: 'RomM server',
        value: romm.when(data: (v) => v == null ? 'Not reachable' : 'v$v', loading: () => '…', error: (_, _) => 'Not reachable'),
      ),
      const SettingsHeading('Links'),
      link('Repository', gargosyRepoUrl, focus: autofocus),
      link('Releases', '$gargosyRepoUrl/releases'),
      link('Report a bug', '$gargosyRepoUrl/issues'),
      link('Security policy', '$gargosyRepoUrl/blob/main/SECURITY.md'),
      const SettingsHeading('What\'s new'),
      link('Changelog', '$gargosyRepoUrl/blob/main/CHANGELOG.md'),
      const SettingsHeading('Licences', note: 'Gargosy is MIT licensed.'),
      file('Gargosy licence (MIT)', 'LICENSE'),
      file('NOTICE.md', 'NOTICE.md'),
      file('Licences folder (LICENSES)', 'LICENSES'),
      SettingsRow(
        label: 'Dart and Flutter packages',
        onActivate: () => showLicensePage(context: context, applicationName: 'Gargosy', applicationVersion: 'v$version'),
      ),
    ]);
  }
}
