import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/emulators/game_settings.dart';
import 'package:gargosy/profiles/age_limit.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/screens/play/game_settings_dialog.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  final okami = Game.fromJson(gameJson(7, 'Okami'));

  Future<GameSettingsStore> open(
    WidgetTester tester,
    String emulatorId, {
    String? shaderDir,
    AgeLimit limit = AgeLimit.off,
  }) async {
    final store = GameSettingsStore(MemoryPrefs());
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showGameSettings(context, ref, game: okami, emulatorId: emulatorId, emulatorName: 'X'),
            child: const Text('open'),
          ),
        ),
        overrides: [
          gameSettingsStoreProvider.overrideWithValue(store),
          retroArchShaderDirProvider.overrideWithValue(shaderDir),
          ageLimitProvider.overrideWithValue(limit),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('PCSX2: widescreen picked with the controller is kept for this game; no shader row', (tester) async {
    final store = await open(tester, 'pcsx2');
    expect(find.byKey(const ValueKey('game-shader')), findsNothing);
    expect(find.text('As the emulator has it'), findsOneWidget);
    await press(tester, GameAction.confirm);
    await tester.tap(find.text('On').last);
    await tester.pumpAndSettle();
    expect(store.read('7', 'pcsx2').widescreen, Widescreen.on);
    expect(store.read('7', 'dolphin').isEmpty, isTrue);
    await press(tester, GameAction.back);
    expect(find.byKey(const ValueKey('game-widescreen')), findsNothing);
  });

  testWidgets("RetroArch: the shader from its folder; no widescreen row; reset clears the game's settings", (
    tester,
  ) async {
    final dir = (await tester.runAsync(() => io.Directory.systemTemp.createTemp('shaders')))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    io.File(p.join(dir.path, 'crt', 'crt-geom.slangp')).createSync(recursive: true);
    final store = await open(tester, 'retroarch', shaderDir: dir.path);
    expect(find.byKey(const ValueKey('game-widescreen')), findsNothing);
    // The presets are listed in another isolate: real time for it.
    await tester.tap(find.byKey(const ValueKey('game-shader')));
    for (var i = 0; i < 20 && find.text('crt').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    // The folder first, then the preset in it.
    await tester.tap(find.text('crt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('crt-geom'));
    await tester.pumpAndSettle();
    expect(store.read('7', 'retroarch').shader, 'crt/crt-geom.slangp');
    expect(find.text('crt-geom'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game-settings-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(store.read('7', 'retroarch').isEmpty, isTrue);
  });

  testWidgets('a profile with an age limit has no extra arguments', (tester) async {
    await open(tester, 'pcsx2', limit: const AgeLimit(maxAge: 12));
    expect(find.byKey(const ValueKey('game-widescreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('game-args')), findsNothing);
  });

  test('the play screen line says what a game has', () {
    expect(gameSettingsSummary(GameSettings.none), isNull);
    expect(
      gameSettingsSummary(const GameSettings(widescreen: Widescreen.on, shader: 'crt/a.slangp', args: '-x')),
      'widescreen · a · extra arguments',
    );
  });
}
