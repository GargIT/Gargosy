import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/ui_sound_service.dart';
import '../core/platform/platform_info.dart';
import '../core/platform/sound_player.dart';
import '../play/play_controller.dart';
import '../profiles/profile_providers.dart';

/// How sounds are played; tests replace it.
final soundPlayerProvider = Provider<SoundPlayer>((ref) => soundPlayerFor(PlatformInfo.current));

final soundsOnProvider = Provider<bool>((ref) {
  final prefs = watchAppPreferencesOrNull(ref);
  return prefs != null && SoundSettings.on(prefs);
});

final soundVolumeProvider = Provider<int>((ref) => SoundSettings.volume(ref.watch(appPreferencesProvider)));

/// Gargosy's sounds (#237), as Settings → Display has them. Nothing else is
/// read while they're off.
final uiSoundsProvider = Provider<UiSoundService>((ref) {
  final on = ref.watch(soundsOnProvider);
  return UiSoundService(
    ref.watch(soundPlayerProvider),
    on: on,
    volume: on ? ref.watch(soundVolumeProvider) : SoundSettings.fallbackVolume,
    gameRunning: () => ref.read(playControllerProvider).runningGameId != null,
  );
});
