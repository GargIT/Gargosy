import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/romm/romm_models.dart';
import '../../../emulators/game_settings.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/engine_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/on_screen_keyboard.dart';
import '../../../l10n/tr.dart';

/// The shader folder of the RetroArch under `emulators\retroarch\` (beside
/// its exe, which may sit a folder down), looked for again each time the
/// dialog opens (an install or the Online Updater may add it); tests
/// replace it.
final retroArchShaderDirProvider = Provider.autoDispose<String?>((ref) {
  final root = ref.watch(appRootProvider);
  return findRetroArchShaderDir(p.join(root.emulators, 'retroarch'));
});

/// The active profile's game settings; tests give their own.
final gameSettingsStoreProvider = Provider<GameSettingsStore?>((ref) {
  final prefs = ref.watch(profilePrefsProvider);
  return prefs == null ? null : GameSettingsStore(prefs);
});

/// The play screen's settings for [game] in [emulatorId] (#234), saved as
/// they change: widescreen where the emulator has a switch Gargosy sets,
/// RetroArch's shader, extra arguments, and a reset of the game's settings
/// in every emulator. Gives whether anything changed.
Future<bool> showGameSettings(
  BuildContext context,
  WidgetRef ref, {
  required Game game,
  required String emulatorId,
  required String emulatorName,
}) async {
  final store = ref.read(gameSettingsStoreProvider);
  if (store == null) return false;
  final shaderDir = GameSettingsSupport.of(emulatorId).shaders ? ref.read(retroArchShaderDirProvider) : null;
  // A child's profile can't reach past its limits through the command line.
  final argsAllowed = !ref.read(ageLimitProvider).isOn;
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _GameSettingsDialog(
      game: game,
      emulatorId: emulatorId,
      emulatorName: emulatorName,
      store: store,
      shaderDir: shaderDir,
      argsAllowed: argsAllowed,
    ),
  );
  return changed ?? false;
}

/// What a game's settings say in one line on the play screen; null when
/// there are none.
String? gameSettingsSummary(GameSettings s) {
  final parts = [
    if (s.widescreen == Widescreen.on) tr('widescreen'),
    if (s.widescreen == Widescreen.off) tr('no widescreen'),
    if (s.shader case final shader?) p.basenameWithoutExtension(shader),
    if (s.args.trim().isNotEmpty) tr('extra arguments'),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

class _GameSettingsDialog extends StatefulWidget {
  const _GameSettingsDialog({
    required this.game,
    required this.emulatorId,
    required this.emulatorName,
    required this.store,
    required this.shaderDir,
    required this.argsAllowed,
  });

  final Game game;
  final String emulatorId;
  final String emulatorName;
  final GameSettingsStore store;
  final String? shaderDir;
  final bool argsAllowed;

  @override
  State<_GameSettingsDialog> createState() => _GameSettingsDialogState();
}

class _GameSettingsDialogState extends State<_GameSettingsDialog> {
  late GameSettings _s = widget.store.read(widget.game.id, widget.emulatorId);
  var _changed = false;

  Future<void> _save(GameSettings s) async {
    await widget.store.write(widget.game.id, widget.emulatorId, s);
    if (mounted) {
      setState(() {
        _s = s;
        _changed = true;
      });
    }
  }

  static String _widescreenLabel(Widescreen w) => switch (w) {
    Widescreen.emulator => tr('As the emulator has it'),
    Widescreen.on => tr('On'),
    Widescreen.off => tr('Off'),
  };

  Future<void> _pickWidescreen() async {
    final i = await showChoice(
      context,
      title: tr('Widescreen'),
      labels: [for (final w in Widescreen.values) _widescreenLabel(w)],
      current: _s.widescreen.index,
    );
    if (i != null) await _save(_s.copyWith(widescreen: Widescreen.values[i]));
  }

  /// The folder first (RetroArch has hundreds of presets), then the preset.
  Future<void> _pickShader() async {
    final shaders = await retroArchShaders(widget.shaderDir!);
    if (!mounted) return;
    final groups = <String, List<String>>{};
    for (final s in shaders) {
      groups.putIfAbsent(p.posix.dirname(s), () => []).add(s);
    }
    final names = groups.keys.toList();
    final current = _s.shader == null ? null : p.posix.dirname(_s.shader!);
    final g = await showChoice(
      context,
      title: tr('Shader'),
      labels: [tr('None'), for (final n in names) n == '.' ? tr('(top)') : n],
      current: current == null ? 0 : names.indexOf(current) + 1,
    );
    if (g == null || !mounted) return;
    if (g == 0) {
      await _save(_s.copyWith(shader: () => null));
      return;
    }
    final presets = groups[names[g - 1]]!;
    final i = await showChoice(
      context,
      title: names[g - 1],
      labels: [for (final s in presets) p.posix.basenameWithoutExtension(s)],
      current: _s.shader == null ? null : presets.indexOf(_s.shader!),
    );
    if (i != null && i >= 0) await _save(_s.copyWith(shader: () => presets[i]));
  }

  /// The shader's name, said missing when the preset isn't there any more
  /// (it isn't passed to RetroArch then).
  String _shaderLabel() {
    final shader = _s.shader;
    if (shader == null) return tr('None');
    final name = p.posix.basenameWithoutExtension(shader.replaceAll(r'\', '/'));
    final there = io.File(p.joinAll([widget.shaderDir!, ...shader.split(RegExp(r'[\\/]'))])).existsSync();
    return there ? name : tr('{0} (missing)', [name]);
  }

  Future<void> _editArgs() async {
    final text = await showOnScreenKeyboard(context, title: tr('Extra arguments'), initial: _s.args);
    if (text != null) await _save(_s.copyWith(args: text.trim()));
  }

  Future<void> _reset() async {
    final ok = await showConfirm(
      context,
      title: tr('Reset {0}\'s settings?', [widget.game.displayName]),
      body: tr('Its extra arguments, shader and widescreen go back to the emulator\'s, in every emulator.'),
      yes: tr('Reset'),
      no: tr('Keep'),
      focusYes: false,
    );
    if (!ok) return;
    await widget.store.reset(widget.game.id);
    if (mounted) {
      setState(() {
        _s = GameSettings.none;
        _changed = true;
      });
    }
  }

  Widget _row(String key, IconData icon, String label, String value, VoidCallback onPress, {bool autofocus = false}) =>
      GFocusable(
        key: ValueKey(key),
        autofocus: autofocus,
        borderRadius: GRadius.md,
        onActivate: onPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
          child: Row(
            children: [
              Icon(icon, size: 20, color: GColors.fgSecondary),
              const SizedBox(width: GSpace.s3),
              Text(label, style: const TextStyle(fontSize: GFont.lg)),
              const SizedBox(width: GSpace.s4),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: GColors.fgSecondary),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final widescreen = GameSettingsSupport.of(widget.emulatorId).widescreen;
    final shaders = widget.shaderDir != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Center(
        child: Material(
          color: GColors.panel,
          borderRadius: BorderRadius.circular(GRadius.lg),
          child: SizedBox(
            width: 520,
            child: Padding(
              padding: const EdgeInsets.all(GSpace.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(GSpace.s4, GSpace.s2, GSpace.s4, GSpace.s4),
                    child: Text(
                      tr('{0} in {1}', [widget.game.displayName, widget.emulatorName]),
                      style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (widescreen)
                    _row(
                      'game-widescreen',
                      Icons.aspect_ratio,
                      tr('Widescreen'),
                      _widescreenLabel(_s.widescreen),
                      _pickWidescreen,
                      autofocus: true,
                    ),
                  if (shaders)
                    _row(
                      'game-shader',
                      Icons.blur_on,
                      tr('Shader'),
                      _shaderLabel(),
                      _pickShader,
                      autofocus: !widescreen,
                    ),
                  if (widget.argsAllowed)
                    _row(
                      'game-args',
                      Icons.terminal,
                      tr('Extra arguments'),
                      _s.args.trim().isEmpty ? tr('None') : _s.args,
                      _editArgs,
                      autofocus: !widescreen && !shaders,
                    ),
                  const Divider(color: GColors.borderStrong, height: GSpace.s4),
                  GFocusable(
                    key: const ValueKey('game-settings-reset'),
                    borderRadius: GRadius.md,
                    onActivate: _reset,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
                      child: Text(
                        tr('Reset this game\'s settings…'),
                        style: const TextStyle(fontSize: GFont.lg, color: GColors.danger),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(GSpace.s4, GSpace.s3, GSpace.s4, GSpace.s2),
                    child: Text(
                      tr('For this game and profile only. B closes.'),
                      style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
