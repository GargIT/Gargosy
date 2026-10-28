import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/romm/romm_auth_client.dart';
import '../../profiles/device_login.dart';
import '../../profiles/login_store.dart';
import '../../profiles/profile_providers.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/on_screen_keyboard.dart';
import '../../l10n/tr.dart';

/// Logging in to one RomM server (spec §5): device pairing with a QR code
/// where the server has it, otherwise (or on request) username and password.
/// With [expectedUserId], only that RomM user is accepted.
class LoginStep extends ConsumerStatefulWidget {
  const LoginStep({
    super.key,
    required this.serverUrl,
    required this.trustSelfSigned,
    required this.deviceName,
    required this.onLoggedIn,
    required this.onBack,
    this.expectedUserId,
    this.expectedUsername,
    this.onServerError,
  });

  final String serverUrl;
  final bool trustSelfSigned;
  final String deviceName;

  /// Saves the login; an error it throws is shown here and the step stays.
  final Future<void> Function(ProfileLogin login, RommUser me) onLoggedIn;
  final VoidCallback onBack;
  final int? expectedUserId;
  final String? expectedUsername;

  /// When set, a server that can't be reached is handed back (the add-profile
  /// flow returns to its server step) instead of shown here.
  final ValueChanged<String>? onServerError;

  @override
  ConsumerState<LoginStep> createState() => _LoginStepState();
}

class _LoginStepState extends ConsumerState<LoginStep> {
  late final RommAuth _auth = ref.read(rommAuthFactoryProvider)(widget.serverUrl, widget.trustSelfSigned);
  DeviceAuthStart? _start;
  DeviceLoginFlow? _flow;
  bool _loading = true;
  bool _passwordMode = false;
  String _username = '';
  String _password = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _username = widget.expectedUsername ?? '';
    _startPairing();
  }

  @override
  void dispose() {
    _flow?.cancel();
    super.dispose();
  }

  Future<void> _startPairing() async {
    try {
      final start = await _auth.startDeviceAuth(deviceIdentifier: const Uuid().v4(), deviceName: widget.deviceName);
      if (!mounted) return;
      if (start == null) {
        setState(() {
          _loading = false;
          _passwordMode = true;
        });
        return;
      }
      setState(() {
        _start = start;
        _loading = false;
      });
      _flow = DeviceLoginFlow(_auth, start);
      final result = await _flow!.run();
      if (!mounted) return;
      switch (result) {
        case DeviceApproved(:final token, :final deviceId):
          await _finish(ProfileLogin(token: token, kind: 'device', deviceId: deviceId));
        case DeviceDenied():
          setState(() => _error = tr('The login was refused in RomM.'));
        case DeviceExpired():
          setState(() => _error = tr('The code expired. Go back and try again.'));
        default:
          break;
      }
    } on RommAuthException catch (e) {
      if (!mounted) return;
      final wrongAddress = e.failure == RommAuthFailure.network || e.failure == RommAuthFailure.notRomm;
      if (wrongAddress && widget.onServerError != null) {
        widget.onServerError!(_describe(e));
        return;
      }
      // Pairing didn't start: offer the password instead of a spinner.
      setState(() {
        _loading = false;
        _passwordMode = true;
        _error = _describe(e);
      });
    }
  }

  String _describe(RommAuthException e) => switch (e.failure) {
    RommAuthFailure.network => tr('Can\'t reach {0}. Check the address and your network.', [widget.serverUrl]),
    RommAuthFailure.badCredentials => tr('Wrong username or password'),
    RommAuthFailure.serverTooOld => tr('This RomM server is too old for Gargosy (it has no client API tokens).'),
    RommAuthFailure.insufficientScope => tr('This RomM user may not log in apps. Ask the RomM admin.'),
    RommAuthFailure.server => tr('{0}. RomM may be restarting; try again in a moment.', [e.message]),
    RommAuthFailure.notRomm => tr('{0} does not look like a RomM server. Check the address.', [widget.serverUrl]),
    RommAuthFailure.wrongUser => tr('This is a different RomM user ({0}). Log in as {1}.', [
      e.message,
      widget.expectedUsername,
    ]),
    RommAuthFailure.other => e.message,
  };

  Future<void> _finish(ProfileLogin login) async {
    try {
      final me = await _auth.fetchMe(login.token);
      if (!mounted) return;
      if (widget.expectedUserId != null && me.id != widget.expectedUserId) {
        // A paired device is already approved for that user in RomM; say so.
        final device = login.kind == 'device'
            ? tr(' Gargosy was approved for {0} in RomM; you can remove that device there.', [me.username])
            : '';
        setState(
          () => _error = tr('This is a different RomM user ({0}). Log in as {1}.{2}', [
            me.username,
            widget.expectedUsername,
            device,
          ]),
        );
        return;
      }
      await widget.onLoggedIn(login, me);
    } on RommAuthException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } on Object catch (e) {
      if (mounted) setState(() => _error = tr('The login could not be saved on this PC ({0}).', [e]));
    }
  }

  Future<void> _passwordLogin() async {
    setState(() => _error = null);
    try {
      final token = await _auth.loginWithPassword(
        username: _username,
        password: _password,
        tokenName: widget.deviceName,
        expectedUserId: widget.expectedUserId,
      );
      _password = '';
      await _finish(ProfileLogin(token: token, kind: 'client-token'));
    } on RommAuthException catch (e) {
      _password = '';
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  Widget _button(String label, VoidCallback onPress, {bool autofocus = false, Key? key}) => GFocusable(
    key: key,
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

  Widget _field(Key key, String label, String value, VoidCallback onPress, {bool autofocus = false}) => GFocusable(
    key: key,
    autofocus: autofocus,
    borderRadius: GRadius.lg,
    onActivate: onPress,
    child: Container(
      width: 420,
      padding: const EdgeInsets.all(GSpace.s4),
      decoration: BoxDecoration(
        color: GColors.bgElevated,
        borderRadius: BorderRadius.circular(GRadius.lg),
        border: Border.all(color: GColors.borderStrong),
      ),
      child: Text(
        value.isEmpty ? label : value,
        style: TextStyle(fontSize: GFont.lg, color: value.isEmpty ? GColors.fgMuted : GColors.fg),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Text(
        tr('Log in to {0}', [widget.serverUrl]),
        style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: GSpace.s5),
    ];
    if (_loading) {
      children.add(const CircularProgressIndicator());
    } else if (!_passwordMode && _start != null) {
      children.addAll([
        Text(
          tr('On your phone or PC, open this in RomM and approve Gargosy:'),
          style: const TextStyle(fontSize: GFont.lg),
        ),
        const SizedBox(height: GSpace.s4),
        Container(
          key: const Key('pair-qr'),
          color: Colors.white,
          padding: const EdgeInsets.all(GSpace.s3),
          child: QrImageView(data: _start!.verificationUrl, size: 220),
        ),
        const SizedBox(height: GSpace.s3),
        Text(
          _start!.userCode,
          style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800, letterSpacing: 4),
        ),
        const SizedBox(height: GSpace.s5),
        _button(tr('Use password instead'), () {
          _flow?.cancel();
          setState(() => _passwordMode = true);
        }, autofocus: true),
      ]);
    } else {
      children.addAll([
        _field(const Key('login-username'), tr('Username'), _username, () async {
          final v = await showOnScreenKeyboard(context, title: tr('Username'), initial: _username);
          if (v != null) setState(() => _username = v);
        }, autofocus: true),
        const SizedBox(height: GSpace.s3),
        _field(const Key('login-password'), tr('Password'), '•' * _password.length, () async {
          final v = await showOnScreenKeyboard(context, title: tr('Password'), obscure: true);
          if (v != null) setState(() => _password = v);
        }),
        const SizedBox(height: GSpace.s5),
        _button(tr('Log in'), _passwordLogin),
      ]);
    }
    if (_error != null) {
      children.addAll([
        const SizedBox(height: GSpace.s4),
        Text(
          _error!,
          style: const TextStyle(color: GColors.danger, fontSize: GFont.lg),
        ),
      ]);
    }
    children.addAll([const SizedBox(height: GSpace.s6), _button(tr('Back'), widget.onBack)]);
    return Center(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
