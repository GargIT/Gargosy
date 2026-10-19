import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_auth_client.dart';
import '../../profiles/json_file.dart';
import '../../profiles/login_store.dart';
import '../../profiles/pin.dart';
import '../../profiles/profile_paths.dart';
import '../../profiles/profile_store.dart';
import '../../profiles/profile_providers.dart';
import '../input/gargosy_intents.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/on_screen_keyboard.dart';
import '../widgets/pin_pad.dart';
import 'login_step.dart';

enum _Step { server, login, details, pin }

/// Adding a profile: server → login → name and colour → optional PIN (spec §5).
class AddProfileScreen extends ConsumerStatefulWidget {
  const AddProfileScreen({super.key, this.suggestedServer = ''});

  final String suggestedServer;

  @override
  ConsumerState<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends ConsumerState<AddProfileScreen> {
  _Step _step = _Step.server;
  late String _server = widget.suggestedServer;
  bool _trustSelfSigned = false;
  String? _serverError;
  ProfileLogin? _login;
  RommUser? _me;
  String _name = '';
  int _color = 0;
  bool _creating = false;
  String? _createError;

  String get _deviceName => 'Gargosy on ${ref.read(pcIdentityProvider).machineName}';

  Future<void> _checkServer() async {
    if (_server.trim().isEmpty) {
      setState(() => _serverError = 'Enter the address of your RomM server.');
      return;
    }
    // Reaching the server is checked by LoginStep's first call; an unreachable
    // server comes back here with its error.
    setState(() {
      _server = RommAuthClient.normalizeBaseUrl(_server);
      _serverError = null;
      _step = _Step.login;
    });
  }

  Future<void> _create(PinHash? pin) async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _createError = null;
    });
    final store = ref.read(profileStoreProvider);
    String? createdId;
    try {
      await _createProfile(store, pin, (id) => createdId = id);
    } on Object catch (e) {
      // Nothing half-made stays behind: a profile without its login is removed.
      if (createdId != null) {
        try {
          await store.delete(createdId!);
        } on Object catch (_) {}
      }
      if (mounted) {
        setState(() {
          _creating = false;
          _createError = 'The profile could not be saved ($e). Try again.';
        });
      }
    }
  }

  Future<void> _createProfile(ProfileStore store, PinHash? pin, void Function(String id) created) async {
    final me = _me!;
    final profile = await store.create(
      name: _name.trim().isEmpty ? me.username : _name.trim(),
      colorIndex: _color,
      serverUrl: _server,
      rommUserId: me.id,
      rommUsername: me.username,
      pin: pin,
      trustSelfSigned: _trustSelfSigned,
    );
    created(profile.id);
    final login = _login!;
    final paths = ProfilePaths(ref.read(appRootProvider), profile.id);
    await loginStoreForWidget(ref, profile).write(paths.guard, login);
    var saved = profile;
    final Uint8List? avatar = await ref
        .read(rommAuthFactoryProvider)(_server, _trustSelfSigned)
        .fetchAvatar(login.token, me.id);
    if (avatar != null) {
      await writeBytesAtomic(paths.guard, paths.avatarFile, avatar);
      saved = profile.copyWith(hasAvatar: true);
      await store.save(saved);
    }
    _login = null;
    ref.invalidate(profilesProvider);
    // GargosyApp pops this page when a profile becomes active.
    await ref.read(activeProfileProvider.notifier).activate(saved, login);
  }

  /// Stop after logging in: the login is dropped and no profile is made.
  Future<void> _cancel() async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stop adding this profile?'),
        content: const Text('You are logged in, but nothing has been saved yet. Stopping adds no profile.'),
        actions: [
          GFocusable(
            autofocus: true,
            borderRadius: GRadius.pill,
            onActivate: () => Navigator.of(c).pop(false),
            child: const Padding(padding: EdgeInsets.all(GSpace.s3), child: Text('Keep going')),
          ),
          GFocusable(
            borderRadius: GRadius.pill,
            onActivate: () => Navigator.of(c).pop(true),
            child: const Padding(padding: EdgeInsets.all(GSpace.s3), child: Text('Stop')),
          ),
        ],
      ),
    );
    if (stop != true || !mounted) return;
    _login = null;
    Navigator.of(context).pop();
  }

  Future<void> _askPin() async {
    final first = await showPinEntry(context, title: 'Choose a PIN', check: (_) async => null);
    if (first == null || !mounted) return;
    final second = await showPinEntry(
      context,
      title: 'Enter the PIN again',
      check: (pin) async => pin == first ? null : "The PINs don't match",
    );
    if (second == null) return;
    await _create(await Isolate.run(() => PinHash.create(second)));
  }

  Widget _button(String label, VoidCallback onPress, {bool autofocus = false}) => GFocusable(
    autofocus: autofocus,
    borderRadius: GRadius.pill,
    onActivate: onPress,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s6, vertical: GSpace.s3),
      decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
      child: Text(
        label,
        style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w600),
      ),
    ),
  );

  Widget _serverStep() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Your RomM server',
        style: TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: GSpace.s5),
      GFocusable(
        key: const Key('server-url'),
        autofocus: true,
        borderRadius: GRadius.lg,
        onActivate: () async {
          final v = await showOnScreenKeyboard(context, title: 'Server address', initial: _server);
          if (v != null) setState(() => _server = v);
        },
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(GSpace.s4),
          decoration: BoxDecoration(
            color: GColors.bgElevated,
            borderRadius: BorderRadius.circular(GRadius.lg),
            border: Border.all(color: GColors.borderStrong),
          ),
          child: Text(
            _server.isEmpty ? 'romm.example.com' : _server,
            style: TextStyle(fontSize: GFont.lg, color: _server.isEmpty ? GColors.fgMuted : GColors.fg),
          ),
        ),
      ),
      const SizedBox(height: GSpace.s3),
      _button(
        _trustSelfSigned ? 'Self-signed certificate: allowed' : 'Self-signed certificate: not allowed',
        () => setState(() => _trustSelfSigned = !_trustSelfSigned),
      ),
      if (_serverError != null) ...[
        const SizedBox(height: GSpace.s3),
        Text(
          _serverError!,
          style: const TextStyle(color: GColors.danger, fontSize: GFont.lg),
        ),
      ],
      const SizedBox(height: GSpace.s5),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button('Cancel', () => Navigator.of(context).pop()),
          const SizedBox(width: GSpace.s3),
          _button('Continue', _checkServer),
        ],
      ),
    ],
  );

  Widget _detailsStep() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Your profile',
        style: TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: GSpace.s5),
      GFocusable(
        autofocus: true,
        borderRadius: GRadius.lg,
        onActivate: () async {
          final v = await showOnScreenKeyboard(context, title: 'Name', initial: _name);
          if (v != null) setState(() => _name = v);
        },
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(GSpace.s4),
          decoration: BoxDecoration(
            color: GColors.bgElevated,
            borderRadius: BorderRadius.circular(GRadius.lg),
            border: Border.all(color: GColors.borderStrong),
          ),
          child: Text(_name, style: const TextStyle(fontSize: GFont.lg)),
        ),
      ),
      const SizedBox(height: GSpace.s4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < GColors.profileColors.length; i++)
            Padding(
              padding: const EdgeInsets.all(GSpace.s2),
              child: GFocusable(
                borderRadius: GRadius.pill,
                onActivate: () => setState(() => _color = i),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: GColors.profileColors[i],
                    shape: BoxShape.circle,
                    border: i == _color ? Border.all(color: GColors.fg, width: 3) : null,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: GSpace.s5),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button('Cancel', _cancel),
          const SizedBox(width: GSpace.s3),
          _button('Continue', () => setState(() => _step = _Step.pin)),
        ],
      ),
    ],
  );

  Widget _pinStep() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Protect it with a PIN?',
        style: TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: GSpace.s2),
      const Text(
        'A PIN keeps others on this PC from playing as you by mistake. It is a lock, not security.',
        style: TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary),
      ),
      const SizedBox(height: GSpace.s5),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button('No PIN', () => _create(null), autofocus: true),
          const SizedBox(width: GSpace.s3),
          _button('Set a PIN', _askPin),
          const SizedBox(width: GSpace.s3),
          _button('Cancel', _cancel),
        ],
      ),
      if (_createError != null) ...[
        const SizedBox(height: GSpace.s4),
        Text(
          _createError!,
          style: const TextStyle(color: GColors.danger, fontSize: GFont.lg),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_step) {
      _Step.server => _serverStep(),
      _Step.login => LoginStep(
        serverUrl: _server,
        trustSelfSigned: _trustSelfSigned,
        deviceName: _deviceName,
        onBack: () => setState(() => _step = _Step.server),
        onServerError: (message) => setState(() {
          _serverError = message;
          _step = _Step.server;
        }),
        onLoggedIn: (login, me) async => setState(() {
          _login = login;
          _me = me;
          _name = me.username;
          _step = _Step.details;
        }),
      ),
      _Step.details => _detailsStep(),
      _Step.pin => _pinStep(),
    };
    return Actions(
      actions: {
        BackIntent: CallbackAction<BackIntent>(
          onInvoke: (_) {
            switch (_step) {
              case _Step.server:
                Navigator.of(context).pop();
              case _Step.login:
                setState(() => _step = _Step.server);
              case _Step.details:
                _cancel(); // logged in: going back means stopping, after asking
              case _Step.pin:
                setState(() => _step = _Step.details);
            }
            return null;
          },
        ),
      },
      child: Scaffold(
        body: Center(child: SingleChildScrollView(child: body)),
      ),
    );
  }
}
