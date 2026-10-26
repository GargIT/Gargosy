import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

  group('devices come and go during a game (#172)', () {
    late StreamController<HeldButtons> held;
    late List<HeldButtons> sent;
    late List<String> paths;
    late Map<String, _FakeDevice> devices;
    late List<String> opened;

    HidPads pads() => HidPads(
      held,
      database: () async => '',
      paths: () => paths,
      open: (path, id, _) {
        opened.add('$path=$id');
        return devices[path];
      },
    );

    setUp(() {
      held = StreamController<HeldButtons>.broadcast(sync: true);
      sent = [];
      held.stream.listen(sent.add);
      paths = [];
      devices = {};
      opened = [];
    });

    test('a controller connected mid-game is read from the next scan', () {
      fakeAsync((async) {
        paths = ['kbd'];
        final hid = pads()..start();
        async.elapse(const Duration(milliseconds: 100));
        expect(opened, ['kbd=hid0']);

        final pad = devices['pad'] = _FakeDevice();
        paths = ['kbd', 'pad'];
        async.elapse(const Duration(seconds: 2));
        expect(opened.last, 'pad=hid0', reason: 'the keyboard is not tried again; ids count opened pads');

        pad.next = {PadButton.select, PadButton.l1};
        async.elapse(const Duration(milliseconds: 50));
        expect(sent.single.pad, 'hid0');
        expect(sent.single.buttons, {PadButton.select, PadButton.l1});
        hid.stop();
        expect(pad.closed, isTrue);
      });
    });

    test('a controller that went is closed and lets go of its buttons', () {
      fakeAsync((async) {
        final a = devices['a'] = _FakeDevice();
        final b = devices['b'] = _FakeDevice();
        paths = ['a', 'b'];
        final hid = pads()..start();
        async.elapse(const Duration(milliseconds: 100));
        a.next = {PadButton.start};
        async.elapse(const Duration(milliseconds: 50));

        paths = ['b'];
        async.elapse(const Duration(seconds: 2));
        expect(a.closed, isTrue);
        expect(b.closed, isFalse);
        expect(sent.last.pad, 'hid0');
        expect(sent.last.buttons, isEmpty);

        // Back again: a new id, read as before.
        paths = ['a', 'b'];
        async.elapse(const Duration(seconds: 2));
        expect(opened.last, 'a=hid2');
        hid.stop();
      });
    });

    test('a device whose reads fail is not opened again until it leaves the list', () {
      fakeAsync((async) {
        final a = devices['a'] = _FakeDevice();
        paths = ['a'];
        final hid = pads()..start();
        async.elapse(const Duration(milliseconds: 100));
        a.gone = true;
        async.elapse(const Duration(seconds: 6));
        expect(opened, ['a=hid0']);
        expect(a.closed, isTrue);

        paths = [];
        async.elapse(const Duration(seconds: 2));
        devices['a'] = _FakeDevice();
        paths = ['a'];
        async.elapse(const Duration(seconds: 2));
        expect(opened, ['a=hid0', 'a=hid1']);
        hid.stop();
      });
    });

    test('a list that fails leaves the pads read as they are', () {
      fakeAsync((async) {
        final a = devices['a'] = _FakeDevice();
        paths = ['a'];
        var fail = false;
        final hid = HidPads(
          held,
          database: () async => '',
          paths: () => fail ? throw StateError('SetupDi') : paths,
          open: (path, id, _) => devices[path],
        )..start();
        async.elapse(const Duration(milliseconds: 100));
        fail = true;
        async.elapse(const Duration(seconds: 4));
        expect(a.closed, isFalse);
        hid.stop();
      });
    });
  });
}

class _FakeDevice implements HidDevice {
  Set<PadButton>? next;
  var closed = false;
  @override
  var gone = false;

  @override
  Set<PadButton>? poll() {
    final changed = next;
    next = null;
    return changed;
  }

  @override
  void close() => closed = true;
}
