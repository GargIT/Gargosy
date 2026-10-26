import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/held_combo.dart';
import 'package:gargosy/core/input/hid_pads.dart';

void main() {
  const db = '''
# Windows
03000000c82d00000360000000000000,8BitDo Pro 2,a:b1,b:b0,back:b10,dpdown:h0.4,guide:b12,leftshoulder:b6,leftstick:b13,lefttrigger:b8,leftx:a0,rightshoulder:b7,rightstick:b14,righttrigger:b9,start:b11,x:b4,y:b3,platform:Windows,
030000004c050000e60c000000000000,DualSense,a:b1,b:b2,back:b8,leftshoulder:b4,leftstick:b10,rightshoulder:b5,rightstick:b11,start:b9,x:b0,y:b3,platform:Windows,
030000004c050000e60c000000000000,DualSense (newer line),back:b0,platform:Windows,
050000004c050000e60c000000810000,DualSense,back:b4,start:b6,platform:Linux,
xinput,XInput Controller,a:b0,platform:Windows,
''';

  test("SDL's Windows lines give each controller's HID buttons by vendor and product", () {
    final sdl = SdlButtons.parse(db);
    expect(sdl.of(0x2dc8, 0x6003), {
      10: PadButton.select,
      11: PadButton.start,
      6: PadButton.l1,
      7: PadButton.r1,
      13: PadButton.l3,
      14: PadButton.r3,
    });
    expect(sdl.of(0x054c, 0x0ce6)?[8], PadButton.select, reason: 'the first Windows line counts');
    expect(sdl.of(0x054c, 0x0ce6)?[9], PadButton.start);
    expect(sdl.of(0x1234, 0x5678), isNull);
  });

  test('the vendor and product in an SDL GUID', () {
    expect(SdlButtons.deviceOf('03000000c82d00000360000000000000'), (0x2dc8, 0x6003));
    expect(SdlButtons.deviceOf('xinput'), isNull);
  });

  test('starts and stops without a controller SDL knows', () async {
    final held = StreamController<HeldButtons>.broadcast();
    final pads = HidPads(held, database: () async => '');
    pads.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    pads.stop();
    pads.stop();
    await held.close();
  });
}
