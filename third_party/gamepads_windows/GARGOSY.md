# gamepads_windows, patched for Gargosy

This is gamepads_windows 0.3.2 from pub.dev (MIT, © 2023 Blue Fire,
https://github.com/flame-engine/gamepads), used through `dependency_overrides`
in Gargosy's `pubspec.yaml`. The changes are marked `Gargosy:` in the code:

- `windows/gamepad.h`, `windows/gamepad.cpp`: the device callback token is a
  value `RegisterDeviceCallback` fills in. Upstream kept an uninitialized
  `GameInputCallbackToken*`, and `Gamepads::stop()` read through it, so
  Gargosy crashed (access violation, `gamepads_windows_plugin.dll`) every time
  it closed on a PC with GameInput.
- `Gamepads::stop()` unregisters the callback, stops the reader threads, then
  releases GameInput. Upstream released it while the threads still read.
- `Gamepads::read_gamepad()`: the reading starts as null, a failed
  `GetCurrentReading` leaves it null, and it is released whether or not it
  held a gamepad state.
- `pubspec.yaml`: no `resolution: workspace` and no dev dependencies, so it
  resolves as a path dependency. `analysis_options.yaml` removed.

Drop this copy and the override once a gamepads_windows release fixes the
token.
