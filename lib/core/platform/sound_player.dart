import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'platform_info.dart';

/// Plays a short sound (#237), without waiting for it; a new one cuts off
/// the one playing.
abstract interface class SoundPlayer {
  void play(Uint8List wav);
}

/// [platform]'s way to play Gargosy's sounds: Windows' `PlaySound`;
/// nothing elsewhere yet.
SoundPlayer soundPlayerFor(PlatformInfo platform) => platform.isWindows ? WindowsSoundPlayer() : const SilentPlayer();

class SilentPlayer implements SoundPlayer {
  const SilentPlayer();

  @override
  void play(Uint8List wav) {}
}

/// `PlaySound` from memory, asynchronously. Windows reads the bytes while
/// the sound plays, so each sound's copy stays allocated, one per distinct
/// sound, for the process.
class WindowsSoundPlayer implements SoundPlayer {
  final _copies = Expando<Pointer<Uint8>>();

  @override
  void play(Uint8List wav) {
    final copy = _copies[wav] ??= _copy(wav);
    PlaySound(PCWSTR(copy.cast<Utf16>()), null, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
  }

  static Pointer<Uint8> _copy(Uint8List wav) {
    final p = malloc<Uint8>(wav.length);
    p.asTypedList(wav.length).setAll(0, wav);
    return p;
  }
}
