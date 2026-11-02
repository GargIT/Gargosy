import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/audio/ui_sound_service.dart';
import 'package:gargosy/core/audio/ui_sounds.dart';
import 'package:gargosy/core/platform/sound_player.dart';

class _Heard implements SoundPlayer {
  final played = <Uint8List>[];

  @override
  void play(Uint8List wav) => played.add(wav);
}

int _peak(Uint8List wav) {
  final b = ByteData.sublistView(wav);
  var peak = 0;
  for (var i = 44; i < wav.length; i += 2) {
    final v = b.getInt16(i, Endian.little).abs();
    if (v > peak) peak = v;
  }
  return peak;
}

void main() {
  test('each sound is a short 16-bit mono WAV that starts and ends in silence', () {
    for (final s in UiSound.values) {
      final wav = uiSoundWav(s, 1);
      final b = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF', reason: '$s');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(b.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(b.getUint16(34, Endian.little), 16, reason: '16-bit');
      expect(b.getUint32(40, Endian.little), wav.length - 44);
      final seconds = (wav.length - 44) / 2 / b.getUint32(24, Endian.little);
      expect(seconds, lessThan(0.35), reason: '$s is short');
      expect(b.getInt16(44, Endian.little), 0);
      expect(b.getInt16(wav.length - 2, Endian.little), 0);
    }
  });

  test('the volume scales the samples, and full volume stays soft', () {
    final full = _peak(uiSoundWav(UiSound.open, 1));
    final quarter = _peak(uiSoundWav(UiSound.open, 0.25));
    expect(full, lessThan(32767 ~/ 3));
    expect(quarter, closeTo(full / 4, full * 0.02));
  });

  group('UiSoundService', () {
    late _Heard heard;
    late DateTime now;
    var running = false;

    UiSoundService service({bool on = true}) =>
        UiSoundService(heard, on: on, volume: 50, gameRunning: () => running, now: () => now);

    setUp(() {
      heard = _Heard();
      now = DateTime(2026, 11, 2, 20);
      running = false;
    });

    test('off: nothing plays', () {
      service(on: false).play(UiSound.open);
      expect(heard.played, isEmpty);
    });

    test('never while a game runs', () {
      running = true;
      service().play(UiSound.done);
      expect(heard.played, isEmpty);
    });

    test('a move right after another sound is the page\'s own focus, not heard; moves after moves are', () {
      final s = service();
      s.play(UiSound.open);
      now = now.add(const Duration(milliseconds: 40));
      s.play(UiSound.move);
      expect(heard.played, hasLength(1));
      now = now.add(UiSoundService.moveQuietAfter);
      s.play(UiSound.move);
      now = now.add(const Duration(milliseconds: 40));
      s.play(UiSound.move);
      expect(heard.played, hasLength(3));
    });

    test('each sound is made once', () {
      final s = service();
      s.play(UiSound.tab);
      s.play(UiSound.tab);
      expect(identical(heard.played[0], heard.played[1]), isTrue);
    });
  });
}
