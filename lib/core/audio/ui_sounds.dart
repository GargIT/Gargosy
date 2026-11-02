import 'dart:math';
import 'dart:typed_data';

/// Gargosy's own sounds (#237): made here, as samples, so there are no
/// files and no one else's licence. Short and soft: they're heard over and
/// over on a TV.
enum UiSound {
  /// Focus moved with the D-pad or the keys.
  move,

  /// A: something opened or chosen.
  open,

  /// B: back.
  back,

  /// LB/RB: another tab.
  tab,

  /// Something failed or was refused.
  error,

  /// A download finished.
  done,
}

const _rate = 22050;

/// One tone of a sound: [hz] gliding to [toHz] over [ms], at [level] of
/// full scale.
typedef _Tone = ({double hz, double toHz, int ms, double level});

_Tone _t(double hz, int ms, {double? to, double level = 1}) => (hz: hz, toHz: to ?? hz, ms: ms, level: level);

const _quiet = 0.22;

final Map<UiSound, List<_Tone>> _tones = {
  UiSound.move: [_t(1320, 22, level: 0.45)],
  UiSound.open: [_t(660, 45, to: 990)],
  UiSound.back: [_t(990, 45, to: 660)],
  UiSound.tab: [_t(880, 30, level: 0.7), _t(1175, 30, level: 0.7)],
  UiSound.error: [_t(220, 90), _t(185, 120)],
  UiSound.done: [_t(523, 70), _t(659, 70), _t(784, 140)],
};

/// [sound] as a 16-bit mono WAV at [volume] (0–1): each tone a sine with a
/// soft start and end, so nothing clicks. Made once per sound and volume,
/// and the same bytes given back after (the player keeps one copy of each).
Uint8List uiSoundWav(UiSound sound, double volume) =>
    _made.putIfAbsent((sound, volume.clamp(0.0, 1.0)), () => _make(sound, volume.clamp(0.0, 1.0)));

final _made = <(UiSound, double), Uint8List>{};

Uint8List _make(UiSound sound, double volume) {
  final tones = _tones[sound]!;
  final samples = <int>[];
  final peak = 32767 * _quiet * volume;
  for (final tone in tones) {
    final n = _rate * tone.ms ~/ 1000;
    final fade = min(n ~/ 4, _rate * 6 ~/ 1000);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final hz = tone.hz + (tone.toHz - tone.hz) * i / n;
      phase += 2 * pi * hz / _rate;
      final edge = min(1.0, min(i, n - 1 - i) / max(1, fade));
      samples.add((sin(phase) * peak * tone.level * edge).round());
    }
  }
  return _wav(samples);
}

Uint8List _wav(List<int> samples) {
  final data = samples.length * 2;
  final b = ByteData(44 + data);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, _rate, Endian.little);
  b.setUint32(28, _rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}
