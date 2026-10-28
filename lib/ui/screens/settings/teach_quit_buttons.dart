import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/held_combo.dart';
import '../../../core/input/hid_buttons.dart';
import '../../../core/input/hid_pads.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/ui_provider.dart';
import '../../input/gargosy_intents.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';
import '../../../l10n/tr.dart';

/// What [TeachQuitButtons] hears: each HID controller's held buttons as
/// numbers, and which controllers there are.
typedef HidTeachReader = BackgroundPads Function(
  void Function(HidDevice device, Set<int> buttons) onRaw,
  void Function(List<HidDevice> devices, bool xinput) onDevices,
);

/// Reads every HID controller for [TeachQuitButtons] while it's open; tests
/// replace it.
final hidTeachReaderProvider = Provider<HidTeachReader>(
  (ref) =>
      (onRaw, onDevices) => HidPads(StreamController<HeldButtons>.broadcast(), onRaw: onRaw, onDevices: onDevices),
);

/// Teaches Gargosy which HID button is which on a controller that isn't
/// Xbox (#171): each quit button pressed once, kept for that controller
/// (vendor and product) for every profile on this PC. True when saved.
Future<bool> showTeachQuitButtons(BuildContext context) async =>
    await showDialog<bool>(context: context, builder: (_) => const TeachQuitButtons()) ?? false;

/// The steps of [showTeachQuitButtons]: a button at a time.
class TeachQuitButtons extends ConsumerStatefulWidget {
  const TeachQuitButtons({super.key});

  /// What each button is called on the common controllers.
  static Map<PadButton, String> get names => {
    PadButton.select: tr('Select (Back, View, Share, Create or −)'),
    PadButton.start: tr('Start (Menu, Options or +)'),
    PadButton.l1: 'LB (L1, L)',
    PadButton.r1: 'RB (R1, R)',
    PadButton.l3: tr('L3 (the left stick pressed in)'),
    PadButton.r3: tr('R3 (the right stick pressed in)'),
  };

  @override
  ConsumerState<TeachQuitButtons> createState() => _TeachQuitButtonsState();
}

class _TeachIntent extends Intent {
  const _TeachIntent(this.cancel);
  final bool cancel;
}

class _TeachQuitButtonsState extends ConsumerState<TeachQuitButtons> {
  static const _steps = [PadButton.select, PadButton.start, PadButton.l1, PadButton.r1, PadButton.l3, PadButton.r3];

  late final BackgroundPads _reader;
  late final StateController<bool> _lock;
  final _focus = FocusNode(debugLabel: 'teach');
  final _was = <HidDevice, Set<int>>{};
  final _taught = <int, PadButton>{};
  HidDevice? _device;
  var _step = 0;
  String? _note;

  /// The controllers heard, null before the first listing; and whether an
  /// XInput one is there.
  List<HidDevice>? _devices;
  var _xinput = false;

  bool get _done => _step >= _steps.length;

  @override
  void initState() {
    super.initState();
    _lock = ref.read(navigationLockedProvider.notifier);
    // The D-pad mustn't move focus out from under the dialog while it's taught.
    Future.microtask(() => _lock.state = true);
    _reader = ref.read(hidTeachReaderProvider)(_onRaw, _onDevices)..start();
  }

  @override
  void dispose() {
    _reader.stop();
    final lock = _lock;
    Future.microtask(() {
      if (lock.mounted) lock.state = false;
    });
    _focus.dispose();
    super.dispose();
  }

  void _onDevices(List<HidDevice> devices, bool xinput) {
    if (!mounted) return;
    final names = [for (final d in devices) d.name];
    if (_devices == null || !listEquals(names, [for (final d in _devices!) d.name]) || xinput != _xinput) {
      debugPrint(
        '[Quit] teaching hears ${names.isEmpty ? 'no controller' : names.join(', ')}${xinput ? ' (and XInput)' : ''}',
      );
    }
    setState(() {
      _devices = devices;
      _xinput = xinput;
    });
  }

  /// What the dialog hears, before a button is pressed.
  String get _heard {
    final devices = _devices;
    if (devices == null) return tr('Looking for controllers…');
    if (devices.isNotEmpty) return tr('Hears {0}.', [devices.map((d) => d.name).join(', ')]);
    return _xinput
        ? tr(
            'Only Xbox (XInput) controllers are connected, and they need no teaching. An 8BitDo in X mode is one: switch it to D mode to teach it.',
          )
        : tr('No controller found. Connect one: it is found within 2 seconds.');
  }

  void _onRaw(HidDevice device, Set<int> buttons) {
    final was = _was[device] ?? const {};
    _was[device] = buttons;
    if (_done || !mounted) return;
    final pressed = buttons.difference(was);
    if (pressed.isEmpty) return;
    if (_device != null && _device != device) return;
    final index = pressed.reduce((a, b) => a < b ? a : b);
    final other = _taught[index];
    if (other != null) {
      setState(() => _note = tr('That button is already {0}.', [TeachQuitButtons.names[other]]));
      return;
    }
    setState(() {
      _device = device;
      _taught[index] = _steps[_step];
      _note = null;
      _step++;
    });
    if (_done) unawaited(_save());
  }

  void _skip() {
    if (_done) return;
    setState(() {
      _note = null;
      _step++;
    });
    if (_done) unawaited(_save());
  }

  Future<void> _save() async {
    final device = _device;
    if (device == null || _taught.isEmpty) return;
    await LearnedHidButtons.save(
      ref.read(appPreferencesProvider),
      hidDeviceKey(device.vendor, device.product),
      Map.of(_taught),
    );
  }

  void _close() => Navigator.of(context).pop(_done && _taught.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final saved = _done && _taught.isNotEmpty && device != null;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _TeachIntent(true),
        SingleActivator(LogicalKeyboardKey.enter): _TeachIntent(false),
        SingleActivator(LogicalKeyboardKey.space): _TeachIntent(false),
      },
      child: Actions(
        actions: {
          _TeachIntent: CallbackAction<_TeachIntent>(onInvoke: (i) => i.cancel || _done ? _close() : _skip()),
          // The controller's buttons are what's being taught: none of them
          // is an action here, not even B.
          for (final type in const [
            ActivateIntent,
            BackIntent,
            LongActivateIntent,
            DetailIntent,
            FavoriteIntent,
            PrevTabIntent,
            NextTabIntent,
            MenuIntent,
          ])
            type: DoNothingAction(consumesKey: true),
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Center(
            child: Material(
              color: GColors.panel,
              borderRadius: BorderRadius.circular(GRadius.lg),
              child: SizedBox(
                width: 480,
                child: Padding(
                  padding: const EdgeInsets.all(GSpace.s5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr('Teach quit buttons'),
                        style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: GSpace.s3),
                      Text(
                        device == null
                            ? tr(
                                'For a controller that is not an Xbox one, if holding the quit buttons does nothing. Press each button once on that controller. {0}',
                                [_heard],
                              )
                            : tr('Teaching {0} ({1}).', [device.name, hidDeviceKey(device.vendor, device.product)]),
                        style: const TextStyle(color: GColors.fgSecondary),
                      ),
                      const SizedBox(height: GSpace.s5),
                      if (!_done) ...[
                        Text(
                          tr('Step {0} of {1}', [_step + 1, _steps.length]),
                          style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                        ),
                        const SizedBox(height: GSpace.s1),
                        Text(
                          tr('Press {0}', [TeachQuitButtons.names[_steps[_step]]]),
                          style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w600),
                        ),
                      ] else
                        Text(
                          saved
                              ? tr(
                                  'Saved for {0}: {1} of {2} buttons. Holding the quit buttons on it closes a game from the next one on.',
                                  [device.name, _taught.length, _steps.length],
                                )
                              : tr('Nothing was taught.'),
                          style: const TextStyle(fontSize: GFont.lg),
                        ),
                      if (_note != null) ...[
                        const SizedBox(height: GSpace.s2),
                        Text(_note!, style: const TextStyle(color: GColors.warning)),
                      ],
                      const SizedBox(height: GSpace.s5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!_done) ...[
                            _button(tr('Skip'), _skip),
                            const SizedBox(width: GSpace.s2),
                            _button(tr('Cancel'), _close),
                          ] else
                            _button('OK', _close, primary: true),
                        ],
                      ),
                      const SizedBox(height: GSpace.s3),
                      Text(
                        _done ? tr('Enter or Escape closes.') : tr('Enter or Space skips a button, Escape cancels.'),
                        style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A button for the mouse; the controller's presses are taught instead.
  Widget _button(String label, VoidCallback onPress, {bool primary = false}) => ExcludeFocus(
    child: GFocusable(
      borderRadius: GRadius.pill,
      onActivate: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
        decoration: BoxDecoration(
          color: primary ? GColors.primary : GColors.surface,
          borderRadius: BorderRadius.circular(GRadius.pill),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ),
  );
}
