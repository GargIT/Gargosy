import 'package:flutter/foundation.dart';

import '../platform/sound_player.dart';
import '../storage/app_preferences.dart';
import 'ui_sounds.dart';

export 'ui_sounds.dart' show UiSound;

/// Settings → Display → Sounds (#237): app-wide, off by default, and a
/// volume in steps.
class SoundSettings {
  static const onKey = 'ui.sounds';
  static const volumeKey = 'ui.soundVolume';
  static const volumes = [25, 50, 75, 100];
  static const fallbackVolume = 50;

  static bool on(AppPreferences prefs) => prefs.getBool(onKey) ?? false;

  static int volume(AppPreferences prefs) {
    final n = int.tryParse(prefs.getString(volumeKey) ?? '');
    return n != null && volumes.contains(n) ? n : fallbackVolume;
  }
}

/// Plays Gargosy's sounds when they're on and no game runs (the emulator
/// is in front then; a download finishing mustn't be heard over it). A
/// sound that can't play is logged, never thrown: nothing waits on one.
class UiSoundService {
  UiSoundService(
    this._player, {
    required this.on,
    required this.volume,
    required this.gameRunning,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SoundPlayer _player;
  final bool on;

  /// 25–100.
  final int volume;
  final bool Function() gameRunning;
  final DateTime Function() _now;

  /// A move right after another sound is the focus a new page or dialog
  /// gives itself: not one the player made.
  static const moveQuietAfter = Duration(milliseconds: 150);

  /// When a sound other than a move last played.
  DateTime? _lastOther;

  void play(UiSound sound) {
    if (!on || gameRunning()) return;
    final now = _now();
    final last = _lastOther;
    if (sound == UiSound.move) {
      if (last != null && now.difference(last) < moveQuietAfter) return;
    } else {
      _lastOther = now;
    }
    try {
      _player.play(uiSoundWav(sound, volume / 100));
    } on Object catch (e) {
      debugPrint('[Sound] $sound: $e');
    }
  }
}
