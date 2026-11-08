import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/storage/ini_file.dart';
import 'package:gargosy/emulators/pad_layout.dart';

import '../helpers/profile_test_env.dart';

void main() {
  test("the profile's layout: Standard where nothing is set up unless it chose another", () async {
    final prefs = MemoryPrefs();
    expect(PadLayout.read(prefs), PadLayout.fillIn);
    await PadLayout.write(prefs, PadLayout.nintendo);
    expect(PadLayout.read(prefs), PadLayout.nintendo);
    prefs.values[PadLayout.prefKey] = 'something newer';
    expect(PadLayout.read(prefs), PadLayout.fillIn);
  });

  group('PCSX2', () {
    test('an unmapped player 1 (keyboard only, or none) gets Standard; a controller mapping stays', () {
      final fresh = IniFile('[Pad1]\nType = DualShock2\nCross = Keyboard/Keypad2\n');
      expect(applyPcsx2Layout(fresh, PadLayout.fillIn), isTrue);
      expect(fresh.get('Pad1', 'Cross'), 'SDL-0/FaceSouth');
      expect(fresh.get('Pad1', 'Circle'), 'SDL-0/FaceEast');
      expect(fresh.get('Pad1', 'L2'), 'SDL-0/+LeftTrigger');
      expect(fresh.get('Pad1', 'LUp'), 'SDL-0/-LeftY');
      expect(fresh.get('Pad1', 'Type'), 'DualShock2');

      final none = IniFile('');
      expect(applyPcsx2Layout(none, PadLayout.fillIn), isTrue);
      expect(none.get('Pad1', 'Type'), 'DualShock2');

      final mine = IniFile('[Pad1]\nCross = SDL-0/FaceEast\nCircle = SDL-0/FaceSouth\n');
      expect(applyPcsx2Layout(mine, PadLayout.fillIn), isFalse);
      expect(mine.get('Pad1', 'Cross'), 'SDL-0/FaceEast');
    });

    test('Standard and Nintendo-style are written over any mapping; own writes nothing', () {
      final ini = IniFile('[Pad1]\nCross = SDL-1/FaceNorth\n');
      expect(applyPcsx2Layout(ini, PadLayout.nintendo), isTrue);
      expect(
        [
          for (final k in ['Cross', 'Circle', 'Square', 'Triangle']) ini.get('Pad1', k),
        ],
        ['SDL-0/FaceEast', 'SDL-0/FaceSouth', 'SDL-0/FaceNorth', 'SDL-0/FaceWest'],
      );
      expect(applyPcsx2Layout(ini, PadLayout.standard), isTrue);
      expect(ini.get('Pad1', 'Cross'), 'SDL-0/FaceSouth');
      expect(applyPcsx2Layout(IniFile(''), PadLayout.own), isFalse);
    });
  });

  group('DuckStation', () {
    test("SDL's names; a mapped pad stays under fill-in; Nintendo-style swaps", () {
      final fresh = IniFile('[Pad1]\nType = AnalogController\n');
      expect(applyDuckstationLayout(fresh, PadLayout.fillIn), isTrue);
      expect(fresh.get('Pad1', 'Cross'), 'SDL-0/A');
      expect(fresh.get('Pad1', 'Triangle'), 'SDL-0/Y');
      expect(fresh.get('Pad1', 'Select'), 'SDL-0/Back');
      expect(fresh.get('Pad1', 'Type'), 'AnalogController', reason: "the pad's type stays DuckStation's");

      final mine = IniFile('[Pad1]\nCross = SDL-0/B\n');
      expect(applyDuckstationLayout(mine, PadLayout.fillIn), isFalse);

      expect(applyDuckstationLayout(mine, PadLayout.nintendo), isTrue);
      expect(
        [
          for (final k in ['Cross', 'Circle', 'Square', 'Triangle']) mine.get('Pad1', k),
        ],
        ['SDL-0/B', 'SDL-0/A', 'SDL-0/Y', 'SDL-0/X'],
      );
    });
  });

  group('Dolphin', () {
    test("the keyboard (Dolphin's default) counts as unmapped; the first XInput pad is written", () {
      final fresh = IniFile('[GCPad1]\nDevice = DInput/0/Keyboard Mouse\nButtons/A = `X`\n');
      expect(applyDolphinLayout(fresh, PadLayout.fillIn), isTrue);
      expect(fresh.get('GCPad1', 'Device'), 'XInput/0/Gamepad');
      expect(fresh.get('GCPad1', 'Buttons/A'), '`Button A`');
      expect(fresh.get('GCPad1', 'Buttons/Z'), '`Shoulder R`');
      expect(fresh.get('GCPad1', 'Main Stick/Up'), '`Left Y+`');

      expect(applyDolphinLayout(IniFile(''), PadLayout.fillIn), isTrue);

      final mine = IniFile('[GCPad1]\nDevice = SDL/0/Xbox One S Controller\nButtons/A = `Button B`\n');
      expect(applyDolphinLayout(mine, PadLayout.fillIn), isFalse);
      expect(applyDolphinLayout(mine, PadLayout.nintendo), isTrue);
      expect(
        [
          for (final k in ['Buttons/A', 'Buttons/B', 'Buttons/X', 'Buttons/Y']) mine.get('GCPad1', k),
        ],
        ['`Button B`', '`Button A`', '`Button Y`', '`Button X`'],
      );
      expect(mine.get('GCPad1', 'Device'), 'XInput/0/Gamepad');
    });
  });

  group('RetroArch', () {
    test("its controller profiles stay under fill-in and own; Nintendo-style swaps the face buttons over them", () {
      const cfg = 'video_driver = "gl"\n';
      expect(applyRetroArchLayout(cfg, PadLayout.fillIn), isNull);
      expect(applyRetroArchLayout(cfg, PadLayout.own), isNull);
      final swapped = applyRetroArchLayout(cfg, PadLayout.nintendo)!;
      expect(swapped, contains('input_player1_b_btn = "1"'));
      expect(swapped, contains('input_player1_a_btn = "0"'));
      expect(swapped, contains('input_player1_y_btn = "3"'));
      expect(swapped, contains('input_player1_x_btn = "2"'));
      final standard = applyRetroArchLayout(swapped, PadLayout.standard)!;
      expect(standard, contains('input_player1_b_btn = "nul"'));
      expect(standard, contains('video_driver = "gl"'));
    });
  });
}
