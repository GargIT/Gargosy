import 'dart:async';

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

/// Reads every HID controller's held buttons as numbers for
/// [TeachQuitButtons] while it's open; tests replace it.
final hidTeachReaderProvider = Provider<BackgroundPads Function(void Function(HidDevice, Set<int>) onRaw)>(
  (ref) =>
      (onRaw) => HidPads(StreamController<HeldButtons>.broadcast(), onRaw: onRaw),
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
  static const names = {
    PadButton.select: 'Select (Back, View, Share, Create or −)',
    PadButton.start: 'Start (Menu, Options or +)',
    PadButton.l1: 'LB (L1, L)',
    PadButton.r1: 'RB (R1, R)',
    PadButton.l3: 'L3 (the left stick pressed in)',
    PadButton.r3: 'R3 (the right stick pressed in)',
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

  bool get _done => _step >= _steps.length;

  @override
  void initState() {
    super.initState();
    _lock = ref.read(navigationLockedProvider.notifier);
    // The D-pad mustn't move focus out from under the dialog while it's taught.
    Future.microtask(() => _lock.state = true);
    _reader = ref.read(hidTeachReaderProvider)(_onRaw)..start();
  }

  @override
  void dispose() {
    _reader.stop();
    final lock = _lock;
    Future.microtask(() => lock.state = false);
    _focus.dispose();
    super.dispose();
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
      setState(() => _note = 'That button is already ${TeachQuitButtons.names[other]}.');
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
                      const Text(
                        'Teach quit buttons',
                        style: TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: GSpace.s3),
                      Text(
                        device == null
                            ? 'For a controller that is not an Xbox one, if holding the quit buttons does nothing. '
                                  'Press each button once on that controller.'
                            : 'Teaching ${device.name} (${hidDeviceKey(device.vendor, device.product)}).',
                        style: const TextStyle(color: GColors.fgSecondary),
                      ),
                      const SizedBox(height: GSpace.s5),
                      if (!_done) ...[
                        Text(
                          'Step ${_step + 1} of ${_steps.length}',
                          style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                        ),
                        const SizedBox(height: GSpace.s1),
                        Text(
                          'Press ${TeachQuitButtons.names[_steps[_step]]}',
                          style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w600),
                        ),
                      ] else
                        Text(
                          saved
                              ? 'Saved for ${device.name}: ${_taught.length} of ${_steps.length} buttons. '
                                    'Holding the quit buttons on it closes a game from the next one on.'
                              : 'Nothing was taught.',
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
                            _button('Skip', _skip),
                            const SizedBox(width: GSpace.s2),
                            _button('Cancel', _close),
                          ] else
                            _button('OK', _close, primary: true),
                        ],
                      ),
                      const SizedBox(height: GSpace.s3),
                      Text(
                        _done ? 'Enter or Escape closes.' : 'Enter or Space skips a button, Escape cancels.',
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
