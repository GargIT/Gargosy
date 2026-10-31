import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/held_combo.dart';
import 'package:gargosy/core/input/hid_buttons.dart';
import 'package:gargosy/core/input/hid_pads.dart';

import '../helpers/profile_test_env.dart';

void main() {
  test("Windows' own HID listing and opening run (win32 6's typed handles, #261)", () async {
    final held = StreamController<HeldButtons>.broadcast();
    final listed = <int>[];
    final pads = HidPads(held, database: () async => '', onDevices: (devices, _) => listed.add(devices.length));
    pads.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    pads.stop();
    await held.close();
    expect(listed, isNotEmpty, reason: 'it listed the HID devices at least once');
  }, testOn: 'windows');

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
    final pads = HidPads(held, database: () async => '', paths: () => const []);
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
      open: (path) {
        opened.add(path);
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
        expect(opened, ['kbd']);

        final pad = devices['pad'] = _FakeDevice();
        paths = ['kbd', 'pad'];
        async.elapse(const Duration(seconds: 2));
        expect(opened, ['kbd', 'pad'], reason: 'the keyboard is not tried again');

        pad.next = {6, 4};
        async.elapse(const Duration(milliseconds: 50));
        expect(sent.single.pad, 'hid0', reason: 'ids count opened pads');
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
        a.next = {7};
        async.elapse(const Duration(milliseconds: 50));

        paths = ['b'];
        async.elapse(const Duration(seconds: 2));
        expect(a.closed, isTrue);
        expect(b.closed, isFalse);
        expect(sent.last.pad, 'hid0');
        expect(sent.last.buttons, isEmpty);

        // Back again: a new id, read as before.
        devices['a'] = _FakeDevice();
        paths = ['a', 'b'];
        async.elapse(const Duration(seconds: 2));
        devices['a']!.next = {7};
        async.elapse(const Duration(milliseconds: 50));
        expect(sent.last.pad, 'hid2');
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
        expect(opened, ['a']);
        expect(a.closed, isTrue);

        paths = [];
        async.elapse(const Duration(seconds: 2));
        devices['a'] = _FakeDevice();
        paths = ['a'];
        async.elapse(const Duration(seconds: 2));
        expect(opened, ['a', 'a']);
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
          open: (path) => devices[path],
        )..start();
        async.elapse(const Duration(milliseconds: 100));
        fail = true;
        async.elapse(const Duration(seconds: 4));
        expect(a.closed, isFalse);
        hid.stop();
      });
    });
  });

  group('which buttons a controller has (#171)', () {
    final sdl = SdlButtons.parse(db);

    test('taught first, then SDL, then the guess', () {
      final taught = {
        '2dc8:6003': {1: PadButton.select},
      };
      final eightBitDo = hidButtonsFor(0x2dc8, 0x6003, sdl: sdl, learned: taught);
      expect(eightBitDo.source, HidButtonSource.learned);
      expect(eightBitDo.buttons, {1: PadButton.select});
      expect(hidButtonsFor(0x054c, 0x0ce6, sdl: sdl, learned: taught).source, HidButtonSource.sdl);
      final unknown = hidButtonsFor(0x1234, 0x5678, sdl: sdl, learned: taught);
      expect(unknown.source, HidButtonSource.guess);
      expect(unknown.buttons, guessedHidButtons);
    });

    test('without SDL (--hid-ignore-sdl) a known controller gets the guess', () {
      expect(hidButtonsFor(0x2dc8, 0x6003, sdl: null, learned: const {}).source, HidButtonSource.guess);
    });

    test('taught buttons are kept per controller in the app-wide prefs', () async {
      final prefs = MemoryPrefs();
      expect(LearnedHidButtons.read(prefs), isEmpty);
      await LearnedHidButtons.save(prefs, '2dc8:6006', {10: PadButton.select, 6: PadButton.l1});
      await LearnedHidButtons.save(prefs, '054c:0ce6', {8: PadButton.select});
      await LearnedHidButtons.save(prefs, '2dc8:6006', {11: PadButton.start});
      expect(LearnedHidButtons.read(prefs), {
        '2dc8:6006': {11: PadButton.start},
        '054c:0ce6': {8: PadButton.select},
      });
      prefs.values[LearnedHidButtons.prefKey] = '{not json';
      expect(LearnedHidButtons.read(prefs), isEmpty);
      await LearnedHidButtons.forgetAll(prefs);
      expect(prefs.getString(LearnedHidButtons.prefKey), isNull);
    });

    test('a pad reads with its taught buttons, and onRaw hears the numbers', () {
      fakeAsync((async) {
        final held = StreamController<HeldButtons>.broadcast(sync: true);
        final sent = <HeldButtons>[];
        held.stream.listen(sent.add);
        final raw = <Set<int>>[];
        final pad = _FakeDevice(vendor: 0x2dc8, product: 0x6003);
        final hid = HidPads(
          held,
          database: () async => db,
          learned: () => {
            '2dc8:6003': {2: PadButton.select, 3: PadButton.start},
          },
          paths: () => ['p'],
          open: (_) => pad,
          onRaw: (device, buttons) => raw.add(buttons),
        )..start();
        async.elapse(const Duration(milliseconds: 100));
        pad.next = {2, 3, 10};
        async.elapse(const Duration(milliseconds: 50));
        expect(sent.single.buttons, {PadButton.select, PadButton.start}, reason: "SDL's b10 is not used");
        expect(raw.single, {2, 3, 10});
        hid.stop();
      });
    });
  });
}

class _FakeDevice implements HidDevice {
  _FakeDevice({this.vendor = 0x1234, this.product = 0x5678});

  @override
  final int vendor;
  @override
  final int product;
  @override
  String get name => 'Fake pad';
  Set<int>? next;
  var closed = false;
  @override
  var gone = false;

  @override
  Set<int>? poll() {
    final changed = next;
    next = null;
    return changed;
  }

  @override
  void close() => closed = true;
}
