import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, setEquals, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:win32/win32.dart';

import 'held_combo.dart';

/// The quit combo's buttons on controllers that aren't XInput (#164): a
/// DualSense, a Switch Pro controller, an 8BitDo in D or S mode. Read
/// through Windows' HID API while a game runs, since GameInput sends nothing
/// while an emulator is in front. Each controller is a pad of its own
/// (`hid<n>`) on [held]. Which HID button is which comes from SDL's
/// controller database ([SdlButtons]); a controller missing there is left
/// out. XInput controllers are [XInputPads]'.
class HidPads implements BackgroundPads {
  HidPads(this.held, {this.every = const Duration(milliseconds: 50), Future<String> Function()? database})
    : _database = database ?? (() => rootBundle.loadString('thirdparty/gamecontrollerdb.txt'));

  final StreamController<HeldButtons> held;
  final Duration every;
  final Future<String> Function() _database;

  SdlButtons? _buttons;
  Timer? _timer;
  final _pads = <_HidPad>[];
  var _run = 0;

  @override
  void start() {
    if (_timer != null) return;
    final run = ++_run;
    _timer = Timer.periodic(every, (_) => _poll());
    unawaited(_open(run));
  }

  @override
  void stop() {
    _run++;
    _timer?.cancel();
    _timer = null;
    for (final pad in _pads) {
      pad.close();
    }
    _pads.clear();
  }

  Future<void> _open(int run) async {
    try {
      final buttons = _buttons ??= SdlButtons.parse(await _database());
      if (run != _run) return;
      var n = 0;
      for (final path in _hidPaths()) {
        final pad = _HidPad.open(path, 'hid${n++}', buttons);
        if (pad != null) _pads.add(pad);
      }
    } catch (e) {
      debugPrint('[Quit] HID controllers can not be read: $e');
    }
  }

  void _poll() {
    for (final pad in [..._pads]) {
      final changed = pad.poll();
      if (pad.gone) {
        pad.close();
        _pads.remove(pad);
      }
      if (changed == null) continue;
      debugPrint('[Quit] ${pad.id} holds ${changed.map((b) => b.name).join(' + ')}');
      if (!held.isClosed) held.add(HeldButtons(pad.id, changed));
    }
  }
}

/// Which HID button (counted from 0, as SDL's `b<n>`) is which [PadButton],
/// per USB vendor and product id, from SDL's `gamecontrollerdb.txt` (its
/// Windows lines).
class SdlButtons {
  SdlButtons._(this._byDevice);

  final Map<(int, int), Map<int, PadButton>> _byDevice;

  static const _names = {
    'back': PadButton.select,
    'start': PadButton.start,
    'leftshoulder': PadButton.l1,
    'rightshoulder': PadButton.r1,
    'leftstick': PadButton.l3,
    'rightstick': PadButton.r3,
  };

  static SdlButtons parse(String database) {
    final byDevice = <(int, int), Map<int, PadButton>>{};
    for (final line in database.split('\n')) {
      if (!line.contains('platform:Windows')) continue;
      final parts = line.split(',');
      final device = deviceOf(parts.first.trim());
      if (device == null || byDevice.containsKey(device)) continue;
      final buttons = <int, PadButton>{};
      for (final part in parts.skip(2)) {
        final pair = part.split(':');
        if (pair.length != 2) continue;
        final button = _names[pair[0].trim()];
        final ref = pair[1].trim();
        final index = ref.startsWith('b') ? int.tryParse(ref.substring(1)) : null;
        if (button != null && index != null) buttons[index] = button;
      }
      if (buttons.isNotEmpty) byDevice[device] = buttons;
    }
    return SdlButtons._(byDevice);
  }

  /// The vendor and product id in an SDL GUID (`03000000` + vendor, little
  /// endian + `0000` + product + …).
  @visibleForTesting
  static (int, int)? deviceOf(String guid) {
    if (guid.length != 32) return null;
    final vendor = int.tryParse(guid.substring(10, 12) + guid.substring(8, 10), radix: 16);
    final product = int.tryParse(guid.substring(18, 20) + guid.substring(16, 18), radix: 16);
    return vendor == null || product == null ? null : (vendor, product);
  }

  /// [vendor]'s [product]'s buttons; null when SDL doesn't know it.
  Map<int, PadButton>? of(int vendor, int product) => _byDevice[(vendor, product)];
}

final _hid = DynamicLibrary.open('hid.dll');
final _getHidGuid = _hid.lookupFunction<Void Function(Pointer<GUID>), void Function(Pointer<GUID>)>('HidD_GetHidGuid');
final _getAttributes = _hid.lookupFunction<Uint8 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>(
  'HidD_GetAttributes',
);
final _getPreparsed = _hid.lookupFunction<Uint8 Function(IntPtr, Pointer<IntPtr>), int Function(int, Pointer<IntPtr>)>(
  'HidD_GetPreparsedData',
);
final _freePreparsed = _hid.lookupFunction<Uint8 Function(IntPtr), int Function(int)>('HidD_FreePreparsedData');
final _getProduct = _hid
    .lookupFunction<Uint8 Function(IntPtr, Pointer<Uint16>, Uint32), int Function(int, Pointer<Uint16>, int)>(
      'HidD_GetProductString',
    );
final _getCaps = _hid.lookupFunction<Int32 Function(IntPtr, Pointer<Uint16>), int Function(int, Pointer<Uint16>)>(
  'HidP_GetCaps',
);
final _getUsages = _hid
    .lookupFunction<
      Int32 Function(Int32, Uint16, Uint16, Pointer<Uint16>, Pointer<Uint32>, IntPtr, Pointer<Uint8>, Uint32),
      int Function(int, int, int, Pointer<Uint16>, Pointer<Uint32>, int, Pointer<Uint8>, int)
    >('HidP_GetUsages');

const _hidpStatusSuccess = 0x00110000;
const _hidpInput = 0;
const _buttonPage = 0x09;
const _statusPending = 0x103;
const _errorIoPending = 997;
const _maxUsages = 128;

/// Every HID device's path.
List<String> _hidPaths() {
  final paths = <String>[];
  final guid = calloc<GUID>();
  final data = calloc<SP_DEVICE_INTERFACE_DATA>()..ref.cbSize = sizeOf<SP_DEVICE_INTERFACE_DATA>();
  final need = calloc<Uint32>();
  try {
    _getHidGuid(guid);
    final set = SetupDiGetClassDevs(guid, nullptr, 0, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (set == INVALID_HANDLE_VALUE) return paths;
    try {
      for (var i = 0; SetupDiEnumDeviceInterfaces(set, nullptr, guid, i, data) != 0; i++) {
        SetupDiGetDeviceInterfaceDetail(set, data, nullptr, 0, need, nullptr);
        if (need.value < 8) continue;
        final detail = calloc<Uint8>(need.value);
        try {
          // SP_DEVICE_INTERFACE_DETAIL_DATA's cbSize on x64; the path follows it.
          detail.cast<Uint32>().value = 8;
          if (SetupDiGetDeviceInterfaceDetail(set, data, detail.cast(), need.value, nullptr, nullptr) != 0) {
            paths.add(Pointer<Utf16>.fromAddress(detail.address + 4).toDartString());
          }
        } finally {
          calloc.free(detail);
        }
      }
    } finally {
      SetupDiDestroyDeviceInfoList(set);
    }
  } finally {
    calloc.free(guid);
    calloc.free(data);
    calloc.free(need);
  }
  return paths;
}

/// One HID game controller, read with overlapped reads polled by [poll].
class _HidPad {
  _HidPad._(this.id, this._handle, this._preparsed, this._length, this._buttons)
    : _report = calloc<Uint8>(_length),
      _read = calloc<Uint32>(),
      _overlapped = calloc<OVERLAPPED>(),
      _usages = calloc<Uint16>(_maxUsages),
      _count = calloc<Uint32>();

  final String id;
  final int _handle;
  final int _preparsed;
  final int _length;
  final Map<int, PadButton> _buttons;
  final Pointer<Uint8> _report;
  final Pointer<Uint32> _read;
  final Pointer<OVERLAPPED> _overlapped;
  final Pointer<Uint16> _usages;
  final Pointer<Uint32> _count;
  var _pending = false;
  var _held = <PadButton>{};
  var gone = false;

  /// A game controller at [path] SDL knows; null for anything else (XInput
  /// controllers, keyboards, mice, headsets).
  static _HidPad? open(String path, String id, SdlButtons sdl) {
    // XInput's (`IG_` in the path) are read by XInputPads.
    if (path.toLowerCase().contains('ig_')) return null;
    final name = path.toNativeUtf16();
    final handle = CreateFile(
      name,
      GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr,
      OPEN_EXISTING,
      FILE_FLAG_OVERLAPPED,
      0,
    );
    calloc.free(name);
    // Keyboards and mice Windows keeps to itself.
    if (handle == INVALID_HANDLE_VALUE) return null;
    final attributes = calloc<Uint8>(12);
    final preparsed = calloc<IntPtr>();
    final caps = calloc<Uint16>(32);
    final product = calloc<Uint16>(128);
    try {
      attributes.cast<Uint32>().value = 12;
      if (_getPreparsed(handle, preparsed) == 0) {
        CloseHandle(handle);
        return null;
      }
      final (usage, page, length) = _getCaps(preparsed.value, caps) == _hidpStatusSuccess
          ? (caps[0], caps[1], caps[2])
          : (0, 0, 0);
      // Generic desktop: a joystick or a gamepad.
      final isPad = page == 0x01 && (usage == 0x04 || usage == 0x05) && length > 0;
      final ids = _getAttributes(handle, attributes) != 0
          ? (attributes.cast<Uint16>()[2], attributes.cast<Uint16>()[3])
          : null;
      final buttons = ids == null ? null : sdl.of(ids.$1, ids.$2);
      if (isPad) {
        final label = _getProduct(handle, product, 256) != 0 ? product.cast<Utf16>().toDartString() : 'controller';
        final hex = ids == null
            ? '?'
            : '${ids.$1.toRadixString(16).padLeft(4, '0')}:${ids.$2.toRadixString(16).padLeft(4, '0')}';
        debugPrint(
          buttons == null
              ? '[Quit] $label ($hex) is not in SDL\'s controller list: not read in the background'
              : '[Quit] $id is $label ($hex)',
        );
      }
      if (!isPad || buttons == null) {
        _freePreparsed(preparsed.value);
        CloseHandle(handle);
        return null;
      }
      return _HidPad._(id, handle, preparsed.value, length, buttons);
    } finally {
      calloc.free(attributes);
      calloc.free(preparsed);
      calloc.free(caps);
      calloc.free(product);
    }
  }

  /// Reads what came since the last poll; the held buttons when they
  /// changed, else null.
  Set<PadButton>? poll() {
    if (gone) return null;
    final was = _held;
    // A few reports at most between polls; the last one counts.
    for (var n = 0; n < 64; n++) {
      if (_pending) {
        if (_overlapped.ref.Internal == _statusPending) break;
        _pending = false;
        if (GetOverlappedResult(_handle, _overlapped, _read, FALSE) == 0) {
          _lost(GetLastError());
          break;
        }
        _parse();
      }
      _overlapped.ref
        ..Internal = 0
        ..InternalHigh = 0
        ..hEvent = 0;
      if (ReadFile(_handle, _report, _length, _read, _overlapped) != 0) {
        _parse();
        continue;
      }
      final error = GetLastError();
      if (error != _errorIoPending) {
        _lost(error);
        break;
      }
      _pending = true;
    }
    return setEquals(was, _held) ? null : _held;
  }

  void _parse() {
    _count.value = _maxUsages;
    // Another report (a different id) leaves the buttons as they were.
    if (_getUsages(_hidpInput, _buttonPage, 0, _usages, _count, _preparsed, _report, _length) != _hidpStatusSuccess) {
      return;
    }
    _held = {for (var i = 0; i < _count.value; i++) ?_buttons[_usages[i] - 1]};
  }

  void _lost(int error) {
    if (error != ERROR_DEVICE_NOT_CONNECTED && error != ERROR_OPERATION_ABORTED) {
      debugPrint('[Quit] $id read: $error');
    }
    gone = true;
    _held = {};
  }

  void close() {
    if (_pending) {
      CancelIoEx(_handle, _overlapped);
      GetOverlappedResult(_handle, _overlapped, _read, TRUE);
    }
    _freePreparsed(_preparsed);
    CloseHandle(_handle);
    calloc.free(_report);
    calloc.free(_read);
    calloc.free(_overlapped);
    calloc.free(_usages);
    calloc.free(_count);
  }
}
