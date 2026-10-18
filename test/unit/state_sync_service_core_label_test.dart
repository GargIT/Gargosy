// A state uploaded from a RetroArch core is labelled on RomM with that core.
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/state_sync_service.dart';
import 'package:gargosy/core/save/strategies/pcsx2_save_strategy.dart';

import '../helpers/state_sync_test_env.dart';

/// PCSX2's states, labelled as a core-running strategy labels them.
class _Labelled extends Pcsx2SaveStrategy {
  _Labelled(StateSyncTestEnv env)
      : super(env.pcsx2.directoryService, env.pcsx2.prefs, platform: const PlatformInfo('windows', environment: {}));
  String? label = 'PCSX ReARMed';
  @override
  String? stateLabelFor(Game game) => label;
  @override
  Set<String> get stateLabels => const {'PCSX ReARMed', 'Beetle PSX HW'};
}

void main() {
  late StateSyncTestEnv env;
  late _Labelled strategy;
  late StateSyncService service;
  setUp(() async {
    env = await StateSyncTestEnv.create();
    strategy = _Labelled(env);
    service = StateSyncService(env.api, env.pcsx2.prefs, (game, {emulatorId, coreOverride}) => strategy);
  });
  tearDown(() => env.dispose());

  test('a new state gets the core as a label', () async {
    await env.writeState(stateFileA, stateBytes(1));
    expect((await service.pushStates(env.game, env.romPath)).uploaded, 1);
    expect(env.api.labelsOf(1), ['PCSX ReARMed']);
  });

  test("an update from another core: that core's label, the player's own labels kept", () async {
    await env.writeState(stateFileA, stateBytes(1));
    await service.pushStates(env.game, env.romPath);
    env.api.label(1, ['PCSX ReARMed', 'Before the boss']);
    strategy.label = 'Beetle PSX HW';
    await env.writeState(stateFileA, stateBytes(2));
    await service.pushStates(env.game, env.romPath);
    expect(env.api.calls, contains('PUT 1'));
    expect(env.api.labelsOf(1), ['Before the boss', 'Beetle PSX HW']);
  });

  test('the same core again: no label call', () async {
    await env.writeState(stateFileA, stateBytes(1));
    await service.pushStates(env.game, env.romPath);
    await env.writeState(stateFileA, stateBytes(2));
    await service.pushStates(env.game, env.romPath);
    expect(env.api.calls.where((c) => c.startsWith('LABEL')), ['LABEL 1']);
  });

  test("a RomM that can't label: the upload still counts", () async {
    env.api.failLabels = true;
    await env.writeState(stateFileA, stateBytes(1));
    final result = await service.pushStates(env.game, env.romPath);
    expect(result.uploaded, 1);
    expect(env.api.labelsOf(1), isEmpty);
  });

  test('an emulator without cores labels nothing', () async {
    await env.writeState(stateFileA, stateBytes(1));
    await env.service.pushStates(env.game, env.romPath);
    expect(env.api.calls.where((c) => c.startsWith('LABEL')), isEmpty);
  });
}
