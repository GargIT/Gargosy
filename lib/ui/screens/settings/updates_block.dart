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
    final i = await showDropdown(context,
        field: _channelField, labels: [for (final c in UpdateChannel.values) c.label], current: current.index);
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

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SettingsHeading('Updates',
          note: 'Latest: releases only. Preview: the next version while it is being made.'),
      Padding(
        padding: const EdgeInsets.only(bottom: GSpace.s2),
        child: Row(children: [
          const Padding(
            padding: EdgeInsets.only(left: GSpace.s4),
            child: Text('Channel', style: TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w600)),
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
        ]),
      ),
      SettingsToggle(
        label: 'Check automatically',
        on: checker.autoCheck,
        onChanged: (on) => ref.read(updateStateProvider.notifier).setAutoCheck(on),
      ),
      SettingsRow(
        label: 'Check now',
        value: state.checking ? 'Checking…' : null,
        onActivate: state.checking ? null : () => ref.read(updateStateProvider.notifier).checkNow(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(GSpace.s4, GSpace.s1, GSpace.s4, GSpace.s3),
        child: Text(_status(state.result, installed.toString(), channel),
            key: const Key('update-status'), style: const TextStyle(color: GColors.fgSecondary)),
      ),
      if (available != null) ...[
        if (installer.canInstall)
          SettingsRow(
            key: const Key('update-now'),
            label: 'Update now',
            value: 'v${available.version}',
            onActivate: () => runUpdate(context, ref, available),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(GSpace.s4, 0, GSpace.s4, GSpace.s2),
            child: Text(installer.whyNot ?? '', style: const TextStyle(color: GColors.fgMuted)),
          ),
          SettingsRow(
            label: 'Open the release page',
            onActivate: () => ref.read(externalOpenerProvider)(available.htmlUrl),
          ),
        ],
        SettingsRow(label: "What's in ${available.version}", onActivate: () => openReleaseNotes(context, ref, available)),
      ],
    ]);
  }

  static String _status(UpdateCheck? result, String installed, UpdateChannel channel) => switch (result) {
        null => 'Not checked yet.',
        UpdateAvailable(:final release) => '${release.version} is available.',
        UpToDate(:final newest) when newest != null && newest.toString() != installed =>
          'You have $installed, newer than what ${channel.label} offers ($newest). '
              'Gargosy never goes back: ${channel.label} offers an update once one is newer.',
        UpToDate() => 'Gargosy is up to date.',
        CheckFailed(:final reason) => "Couldn't check: $reason",
      };
}

/// What the last update did, for About's header; null when nothing.
String? updateOutcomeLine(UpdateOutcome? outcome, String version) => switch (outcome) {
      UpdatedFrom(:final oldVersion) => 'Updated from v$oldVersion to v$version.',
      UpdateFailed(:final detail) => "The update couldn't be installed${detail == null ? '.' : ': $detail'}",
      null => null,
    };
