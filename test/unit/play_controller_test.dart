import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/play/play_engine.dart';

import '../helpers/game_fixtures.dart';

class _Strategy extends Fake implements EmulatorStrategy {
  @override
  String get emulatorId => 'pcsx2';
  @override
  String get name => 'PCSX2';
}

class FakeEngine implements PlayEngine {
  bool installed = true;
  bool downloaded = true;
  final steps = <String>[];
  Completer<PlayResult>? running;

  @override
  Future<EmulatorStrategy?> emulatorFor(Game game) async => _Strategy();
  @override
  Future<bool> isInstalled(EmulatorStrategy s) async => installed;
  @override
  Future<String?> romPathFor(Game game) async {
    await Future<void>.delayed(Duration.zero); // lists a folder
    return downloaded ? r'D:\G\roms\ps2\g.chd' : null;
  }

  String? problem;
  @override
  Future<void> pullSave(Game game, String romPath, EmulatorStrategy s, {void Function(String)? onProblem}) async {
    steps.add('pull');
    if (problem != null) onProblem?.call(problem!);
  }
  @override
  Future<PlaySession> launch(Game game, String romPath, EmulatorStrategy s) async {
    steps.add('launch');
    running = Completer<PlayResult>();
    return PlaySession(running!.future);
  }
}

void main() {
  late FakeEngine engine;
  late ProviderContainer c;
  setUp(() {
    engine = FakeEngine();
    c = ProviderContainer(overrides: [playEngineProvider.overrideWithValue(engine)]);
  });
  tearDown(() => c.dispose());

  test('pulls the save, then launches; while it runs the game is marked running', () async {
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), isNull);
    expect(engine.steps, ['pull', 'launch']);
    expect(c.read(playControllerProvider).runningGameId, '1');
    engine.running!.complete(const PlayResult('Save synced'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playControllerProvider).runningGameId, isNull);
    expect(c.read(playControllerProvider).message, 'Save synced');
  });

  test('a second Play while a game runs is refused', () async {
    await c.read(playControllerProvider.notifier).play(game(1, 'G'));
    expect(await c.read(playControllerProvider.notifier).play(game(2, 'H')), contains('already running'));
    expect(engine.steps, ['pull', 'launch']);
  });

  test('a game that isn\'t downloaded, or an emulator that isn\'t installed, is explained', () async {
    engine.downloaded = false;
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), contains('Download'));
    engine
      ..downloaded = true
      ..installed = false;
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), contains('PCSX2'));
    expect(engine.steps, isEmpty);
  });

  test('a quick second press while the first is still starting is refused', () async {
    final first = c.read(playControllerProvider.notifier).play(game(1, 'G'));
    final second = c.read(playControllerProvider.notifier).play(game(2, 'H'));
    expect(await first, isNull);
    expect(await second, contains('already running'));
    expect(engine.steps, ['pull', 'launch']);
  });

  test("a refusal clears the starting state, so the next Play isn't blocked", () async {
    engine.downloaded = false;
    await c.read(playControllerProvider.notifier).play(game(1, 'G'));
    expect(c.read(playControllerProvider).runningGameId, isNull);
  });

  test("the pull's problem is told, and the game still starts", () async {
    engine.problem = 'card full';
    final told = <String>[];
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G'), onNotice: told.add), isNull);
    expect(told, ['card full']);
    expect(engine.steps, ['pull', 'launch']);
  });
}
