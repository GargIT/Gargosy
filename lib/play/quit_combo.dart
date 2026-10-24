import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_preferences.dart';
import '../profiles/profile_providers.dart';

/// Quitting a game with the controller (#141): Select + Start held for
/// [hold] on one controller calls [onQuit], once. Listens to [held]
/// (`selectStartHeld`) until [cancel].
class QuitCombo {
  QuitCombo(Stream<bool> held, this.onQuit, {this.hold = holdTime}) {
    _sub = held.listen((on) {
      _timer?.cancel();
      _timer = on && !_fired ? Timer(hold, _fire) : null;
    });
  }

  static const holdTime = Duration(seconds: 2);

  /// This PC's setting (Settings → Controller), on by default.
  static const prefKey = 'controller.quitCombo';
  static bool enabledIn(AppPreferences prefs) => prefs.getBool(prefKey) ?? true;

  final Future<void> Function() onQuit;
  final Duration hold;
  late final StreamSubscription<bool> _sub;
  Timer? _timer;
  bool _fired = false;

  void _fire() {
    _fired = true;
    unawaited(onQuit());
  }

  void cancel() {
    _timer?.cancel();
    _sub.cancel();
  }
}

/// Whether Select + Start quits a game on this PC; read again after
/// Settings changes it.
final quitComboOnProvider = Provider<bool>((ref) => QuitCombo.enabledIn(ref.watch(appPreferencesProvider)));
