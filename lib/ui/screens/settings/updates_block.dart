import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/about_providers.dart';
import '../../../providers/update_providers.dart';
import '../../../update/update_checker.dart';
import '../../../update/update_installer.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_dropdown.dart';
import '../../widgets/update_flow.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// About's Updates block (issue #16): the channel, Check automatically,
/// Check now, and what the check found, with Update now.
class UpdatesBlock extends ConsumerStatefulWidget {
  const UpdatesBlock({super.key});

  @override
  ConsumerState<UpdatesBlock> createState() => _UpdatesBlockState();
}

class _UpdatesBlockState extends ConsumerState<UpdatesBlock> {
  final _channelField = GlobalKey();

  Future<void> _pickChannel(UpdateChannel current) async {
    final i = await showDropdown(
      context,
      field: _channelField,
      labels: [for (final c in UpdateChannel.values) c.label],
      current: current.index,
    );
    if (i == null || !mounted) return;
    await ref.read(updateStateProvider.notifier).setChannel(UpdateChannel.values[i]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateStateProvider);
    final checker = ref.watch(updateCheckerProvider);
    final installed = ref.watch(installedVersionProvider);
    final channel = checker.channel;
    final available = state.available?.release;
    final installer = ref.watch(updateInstallerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(GSpace.s2, GSpace.s4, GSpace.s2, GSpace.s1),
          child: Text(
            tr('UPDATES'),
            style: const TextStyle(
              fontSize: GFont.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: GColors.fgSecondary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GSpace.s2, 0, GSpace.s2, GSpace.s2),
          child: Text(
            tr('Latest: releases only. Preview: the next version while it is being made.'),
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: GSpace.s2),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: GSpace.s2),
                child: Text(
                  tr('Channel'),
                  style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              SizedBox(
                key: _channelField,
                child: GDropdownField(
                  icon: Icons.alt_route,
                  text: channel.label,
                  compact: true,
                  onPress: () => _pickChannel(channel),
                ),
              ),
            ],
          ),
        ),
        SettingsToggle(
          label: tr('Check automatically'),
          on: checker.autoCheck,
          onChanged: (on) => ref.read(updateStateProvider.notifier).setAutoCheck(on),
        ),
        SettingsLinkRow(
          icon: Icons.refresh,
          label: tr('Check now'),
          value: state.checking ? tr('Checking…') : null,
          onActivate: () {
            if (!state.checking) ref.read(updateStateProvider.notifier).checkNow();
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(GSpace.s2, GSpace.s1, GSpace.s2, GSpace.s3),
          child: Text(
            _status(state.result, installed.toString(), channel),
            key: const Key('update-status'),
            style: const TextStyle(color: GColors.fgSecondary),
          ),
        ),
        if (available != null) ...[
          if (installer.canInstall)
            SettingsLinkRow(
              key: const Key('update-now'),
              icon: Icons.system_update_alt,
              label: tr('Update now'),
              value: 'v${available.version}',
              onActivate: () => runUpdate(context, ref, available),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(GSpace.s2, 0, GSpace.s2, GSpace.s2),
              child: Text(installer.whyNot ?? '', style: const TextStyle(color: GColors.fgMuted)),
            ),
            SettingsLinkRow(
              icon: Icons.open_in_new,
              label: tr('Open the release page'),
              onActivate: () => ref.read(externalOpenerProvider)(available.htmlUrl),
            ),
          ],
          SettingsLinkRow(
            icon: Icons.notes,
            label: tr('What\'s in {0}', [available.version]),
            onActivate: () => openReleaseNotes(context, ref, available),
          ),
        ],
      ],
    );
  }

  static String _status(UpdateCheck? result, String installed, UpdateChannel channel) => switch (result) {
    null => tr('Not checked yet.'),
    UpdateAvailable(:final release) => tr('{0} is available.', [release.version]),
    UpToDate(:final newest) when newest != null && newest.toString() != installed => tr(
      'You have {0}, newer than what {1} offers ({2}). Gargosy never goes back: {3} offers an update once one is newer.',
      [installed, channel.label, newest, channel.label],
    ),
    UpToDate() => tr('Gargosy is up to date.'),
    CheckFailed(:final reason) => tr('Couldn\'t check: {0}', [reason]),
  };
}

/// What the last update did, for About's header; null when nothing.
String? updateOutcomeLine(UpdateOutcome? outcome, String version) => switch (outcome) {
  UpdatedFrom(:final oldVersion) => tr('Updated from v{0} to v{1}.', [oldVersion, version]),
  UpdateFailed(:final detail) => tr('The update couldn\'t be installed{0}', [detail == null ? '.' : ': $detail']),
  null => null,
};
