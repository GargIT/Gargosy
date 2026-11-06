import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/tr.dart';
import '../../../library/remote_installs.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/remote_install_providers.dart';
import 'settings_rows.dart';

/// Settings → Profile's Install from RomM (#288): games sent to this PC from
/// RomM's web page download here. Its note says why it can't when it can't.
class RemoteInstallToggle extends ConsumerWidget {
  const RemoteInstallToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(remoteInstallOnProvider);
    final paired = ref.watch(activeProfileProvider.select((c) => c?.login.kind == 'device'));
    final state = ref.watch(remoteInstallStateProvider);
    final note = switch ((paired, state)) {
      (false, _) => tr('Only a profile signed in by pairing can take them: sign in again and pair this PC.'),
      (_, RemoteInstallState.off) => tr('RomM has installs to devices turned off, or is older than 5.4.'),
      (_, RemoteInstallState.notPaired) => tr('RomM didn\'t let this login take them: sign in again and pair this PC.'),
      _ => tr('Games you send to this PC from RomM\'s web page download here.'),
    };
    return SettingsToggle(
      key: const ValueKey('remote-install'),
      label: tr('Install from RomM'),
      note: note,
      on: on,
      onChanged: (v) => ref.read(remoteInstallOnProvider.notifier).set(v),
    );
  }
}
