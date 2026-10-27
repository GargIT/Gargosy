import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, setEquals;
import 'package:flutter/services.dart' show rootBundle;
import 'package:win32/win32.dart';

import 'held_combo.dart';
import 'hid_buttons.dart';

/// The quit combo's buttons on controllers that aren't XInput (#164): a
/// DualSense, a Switch Pro controller, an 8BitDo in D or S mode. Read
/// through Windows' HID API while a game runs, since GameInput sends nothing
/// while an emulator is in front. Each controller is a pad of its own
/// (`hid<n>`) on [held]. Which HID button is which: taught in Settings
/// (#171, [learned]), else SDL's controller database ([SdlButtons]; not
/// read with [ignoreSdl]), else [guessedHidButtons]. XInput controllers are
/// [XInputPads]'. The devices are listed again every [rescanEvery] (#172):
/// one connected or woken during the game is read from then on, one that
/// went is closed. [onRaw] hears every controller's held HID buttons as
/// numbers (teaching).
class HidPads implements BackgroundPads {
  HidPads(
    this.held, {
    this.every = const Duration(milliseconds: 50),
    this.rescanEvery = const Duration(seconds: 2),
    this.ignoreSdl = false,
    this.onRaw,
    Map<String, Map<int, PadButton>> Function()? learned,
    Future<String> Function()? database,
    List<String> Function()? paths,
    HidDevice? Function(String path)? open,
  }) : _learned = learned ?? (() => const {}),
       _database = database ?? (() => rootBundle.loadString('thirdparty/gamecontrollerdb.txt')),
       _paths = paths ?? _hidPaths,
       _openDevice = open ?? _HidPad.open;

  final StreamController<HeldButtons> held;
  final Duration every;
  final Duration rescanEvery;
  final bool ignoreSdl;
  final void Function(HidDevice device, Set<int> buttons)? onRaw;
  final Map<String, Map<int, PadButton>> Function() _learned;
  final Future<String> Function() _database;
  final List<String> Function() _paths;
  final HidDevice? Function(String path) _openDevice;

  SdlButtons? _sdl;
  Map<String, Map<int, PadButton>> _taught = const {};
  var _ready = false;
  Timer? _timer;
  Timer? _rescan;

  /// The controllers read now, by device path.
  final _pads = <String, _Pad>{};

  /// Paths that aren't a controller to read (or whose reads failed), not
  /// opened again until they're gone from the list.
  final _skipped = <String>{};
  var _next = 0;
  var _run = 0;
  var _listFailed = false;

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
    _rescan?.cancel();
    _rescan = null;
    for (final pad in _pads.values) {
      pad.device.close();
    }
    _pads.clear();
    _skipped.clear();
    _next = 0;
    _ready = false;
    _listFailed = false;
  }

  Future<void> _open(int run) async {
    try {
      if (!ignoreSdl) _sdl ??= SdlButtons.parse(await _database());
      _taught = _learned();
    } catch (e) {
      debugPrint('[Quit] HID controllers can not be read: $e');
      return;
    }
    if (run != _run) return;
    _ready = true;
    _scan();
    _rescan = Timer.periodic(rescanEvery, (_) => _scan());
  }

  /// Opens the controllers that came, closes the ones that went.
  void _scan() {
    if (!_ready) return;
    final List<String> paths;
    try {
      paths = _paths();
      _listFailed = false;
    } catch (e) {
      if (!_listFailed) debugPrint('[Quit] HID controllers can not be listed: $e');
      _listFailed = true;
      return;
    }
    final present = paths.toSet();
    for (final path in [..._pads.keys]) {
      if (present.contains(path)) continue;
      final pad = _pads.remove(path)!;
      debugPrint('[Quit] ${pad.id} disconnected');
      _drop(pad);
    }
    _skipped.retainAll(present);
    for (final path in paths) {
      if (_pads.containsKey(path) || _skipped.contains(path)) continue;
      final device = _openDevice(path);
      if (device == null) {
        _skipped.add(path);
        continue;
      }
      final id = 'hid${_next++}';
      final map = hidButtonsFor(device.vendor, device.product, sdl: ignoreSdl ? null : _sdl, learned: _taught);
      debugPrint(
        '[Quit] $id is ${device.name} (${hidDeviceKey(device.vendor, device.product)}), '
        'buttons from ${map.source.label}',
      );
      _pads[path] = _Pad(id, device, map.buttons);
    }
  }

  void _poll() {
    for (final path in [..._pads.keys]) {
      final pad = _pads[path]!;
      final raw = pad.device.poll();
      if (pad.device.gone) {
        _pads.remove(path);
        _skipped.add(path);
        _drop(pad);
        continue;
      }
      if (raw == null) continue;
      onRaw?.call(pad.device, raw);
      final buttons = {for (final b in raw) ?pad.buttons[b]};
      if (setEquals(buttons, pad.held)) continue;
      pad.held = buttons;
      debugPrint('[Quit] ${pad.id} holds ${buttons.map((b) => b.name).join(' + ')}');
      if (!held.isClosed) held.add(HeldButtons(pad.id, buttons));
    }
  }

  /// Closes [pad]; whatever it held is let go.
  void _drop(_Pad pad) {
    pad.device.close();
    if (pad.held.isNotEmpty && !held.isClosed) held.add(HeldButtons(pad.id, const {}));
  }
}

class _Pad {
  _Pad(this.id, this.device, this.buttons);
  final String id;
  final HidDevice device;
  final Map<int, PadButton> buttons;
  var held = <PadButton>{};
}

/// One HID game controller [HidPads] reads (a seam for tests).
abstract interface class HidDevice {
  int get vendor;
  int get product;

  /// The controller's product name, or `controller`.
  String get name;

  /// What came since the last poll: the held HID buttons (counted from 0)
  /// when they changed, else null.
  Set<int>? poll();

  /// The device can't be read any more.
  bool get gone;

  void close();
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
const _statusSuccess = 0;
const _statusPending = 0x103;
const _statusDeviceNotConnected = 0xC000009D;
const _statusCancelled = 0xC0000120;

/// What a read's status is until Windows takes it.
const _notStarted = 0xFFFFFFFF;
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
class _HidPad implements HidDevice {
  _HidPad._(this._handle, this._preparsed, this._length, this.vendor, this.product, this.name)
    : _report = calloc<Uint8>(_length),
      _read = calloc<Uint32>(),
      _overlapped = calloc<OVERLAPPED>(),
      _usages = calloc<Uint16>(_maxUsages),
      _count = calloc<Uint32>();

  final int _handle;
  final int _preparsed;
  final int _length;
  @override
  final int vendor;
  @override
  final int product;
  @override
  final String name;
  final Pointer<Uint8> _report;
  final Pointer<Uint32> _read;
  final Pointer<OVERLAPPED> _overlapped;
  final Pointer<Uint16> _usages;
  final Pointer<Uint32> _count;
  var _pending = false;
  var _held = <int>{};
  @override
  var gone = false;

  /// The game controller at [path]; null for anything else (XInput
  /// controllers, keyboards, mice, headsets).
  static _HidPad? open(String path) {
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
      if (!isPad || ids == null) {
        _freePreparsed(preparsed.value);
        CloseHandle(handle);
        return null;
      }
      final label = _getProduct(handle, product, 256) != 0 ? product.cast<Utf16>().toDartString() : '';
      return _HidPad._(handle, preparsed.value, length, ids.$1, ids.$2, label.isEmpty ? 'controller' : label);
    } finally {
      calloc.free(attributes);
      calloc.free(preparsed);
      calloc.free(caps);
      calloc.free(product);
    }
  }

  @override
  Set<int>? poll() {
    if (gone) return null;
    final was = _held;
    // A few reports at most between polls; the last one counts. A read's
    // outcome is its OVERLAPPED's status (NTSTATUS): GetLastError isn't
    // kept between Dart's native calls, so it can't tell a pending read.
    for (var n = 0; n < 64; n++) {
      if (_pending) {
        final status = _status;
        if (status == _statusPending) break;
        _pending = false;
        if (status != _statusSuccess) {
          _lost(status);
          break;
        }
        _parse();
      }
      _overlapped.ref
        ..Internal = _notStarted
        ..InternalHigh = 0
        ..hEvent = 0;
      if (ReadFile(_handle, _report, _length, nullptr, _overlapped) != 0) {
        _parse();
        continue;
      }
      final status = _status;
      if (status == _statusPending) {
        _pending = true;
        break;
      }
      _lost(status);
      break;
    }
    return setEquals(was, _held) ? null : _held;
  }

  /// The read's NTSTATUS (32 bits, sign-extended in the pointer-sized field).
  int get _status => _overlapped.ref.Internal & 0xFFFFFFFF;

  void _parse() {
    _count.value = _maxUsages;
    // Another report (a different id) leaves the buttons as they were.
    if (_getUsages(_hidpInput, _buttonPage, 0, _usages, _count, _preparsed, _report, _length) != _hidpStatusSuccess) {
      return;
    }
    _held = {for (var i = 0; i < _count.value; i++) _usages[i] - 1};
  }

  void _lost(int status) {
    if (status != _statusDeviceNotConnected && status != _statusCancelled) {
      final why = status == _notStarted ? 'could not start' : '0x${status.toRadixString(16)}';
      debugPrint('[Quit] $name read: $why');
    }
    gone = true;
    _held = {};
  }

  @override
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
