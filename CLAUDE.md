# Gargosy — Agent Map
> Source of truth for LLM agents working on this codebase. Read it before touching any file, and update it when you create, split or move a file.

## Project Overview
Gargosy is a Flutter app for Windows that browses a RomM library, downloads ROMs, launches emulators that Gargosy installs itself, and syncs saves and states with RomM. It looks and feels like RomM's v2 web UI, is controller-first, is always portable, and supports several profiles (one RomM user each) on one PC. State management is Riverpod.

It is built on code copied from Freegosy (MIT, © 2026 abduznik). There is no shared history; upstream fixes are copied by hand when needed.

## Rules (MANDATORY)
- **Portable only.** Every path comes from the app root (the folder of `Gargosy.exe`): `roms\`, `emulators\`, `bios\`, `userdata\`. Never AppData, never `path_provider` application dirs.
- **ROM folders hold only ROMs.** Never write saves, zips, backups or metadata into `roms\`.
- **Every write goes through `PathGuard`** (`lib/profiles/path_guard.dart`). It allows only the active profile's folder, `userdata\templates\`, `userdata\settings.json`, `roms\`, `emulators\` and `bios\`. Paths from the server (file names, save targets) are checked the same way.
- **The active profile is the only source of paths and of the RomM session.** Services take a `ProfileContext` through Riverpod; no global "current user", no static paths.
- **One emulator process at a time.** Never launch while a game runs, and never switch profiles during a game or an unfinished sync.
- **An emulator is pointed at the profile's data folder** by a command-line argument or by writing its folder settings just before launch (`ProfileLaunchConfig`). Never swap saves in and out of a shared folder. An emulator that can't be pointed is not supported. `docs/emulator-profiles.md` records how each one is done.
- **Credentials:** RomM tokens are DPAPI-encrypted, one file per PC (`login.<PC>.dpapi`). Never store a password. A PIN is a salted hash, and it's a family lock, not security.
- **Look and feel = RomM v2, dark only.** Theme values live in `lib/ui/theme/tokens.dart`. Copy token *values* only: no RomM code, CSS, icons or logo (RomM is AGPL-3.0).
- **Controller-first.** Every screen must work with a controller alone: spatial focus, B goes back, LB/RB switch tabs, and focus is remembered per screen. Mouse and keyboard must work too.
- **Copied code is marked.** A file copied from Freegosy starts with `// Adapted from Freegosy (MIT, © 2026 abduznik).`, and its tests come along with it.
- Aim for files under 600 lines. When a file is over it, or a change would push it over, move self-contained parts (a class, a parser, a group of pure functions, a dialog or sub-widget) to a helper file when the result is clearer. A cohesive unit (e.g. a data table) may stay whole.
- All RomM API calls go through `romm_service.dart` only. Never call the API from UI or providers.
- All emulator logic goes through the strategy pattern; never hardcode emulator behaviour in the UI.
  - A new emulator is a new file in `core/emulator/strategies/`, registered in `strategy_registry.dart` only.
  - A new save strategy is a new file in `core/save/strategies/`, registered in `save_sync_service.dart` only.
- Providers are thin: they call services and hold no business logic.
- New screen = new file in `ui/screens/`; new reusable widget = new file in `ui/widgets/`.
- Never use `Platform.environment` or `Platform.isWindows` directly. Use `PlatformInfo` (`core/platform/platform_info.dart`) passed in as a constructor parameter.
- ROM name sanitization includes `!` in the regex, the same in every service that builds a ROM folder name.
- Windows games are folder-based: `findMainRomInFolder()` returns the folder for `windows`/`pc`/`win`.
- A save strategy that needs a game id (serial, title id) takes RomM's `Game.titleId`/`saveTarget` through `GameIdResolver` before reading the ROM itself; with RomM's id it never opens the disc.
- Write files with LF line endings (`.gitattributes` normalizes). From Python, use `open(..., 'w', newline='\n')`.

## Layout on disk
```
Gargosy\
  Gargosy.exe, *.dll, data\…     app (data\ is Flutter's); replaced on update
  roms\<platform>\               ROMs only, shared
  emulators\<emu>\               emulator binaries, shared
  bios\                          firmware, shared
  userdata\
    settings.json
    templates\<emu>\             starting emulator data for new profiles
    profiles\<id>\               profile.json, login.<PC>.dpapi, emulators\<emu>\, backups\, cache\
```

## File Map
Update this section as files are created.

- `lib/core/` — copied from Freegosy, trimmed:
  - RomM API and models;
  - save sync, formats and catalog;
  - save and emulator strategies;
  - CHD/serial reading, downloads, extraction;
  - controller input.
- `lib/profiles/` — `Profile`, `ProfileStore`, `ProfileContext`, `ProfilePaths`, `PathGuard`, PIN, login flows (device pairing, password fallback).
- `lib/emulators/` — `EmulatorInstaller`, templates, per-emulator `ProfileLaunchConfig`.
- `lib/ui/` — `theme/` (v2 tokens → `ThemeData`), shell (v2-style top bar with tab pill, user menu, background art), focus system and input mode, screens, widgets, on-screen keyboard.

## Branding
- The app logo is the "G" with three face buttons: `assets/branding/gargosy_logo.svg`. It's the source for `gargosy_logo.png` (1024 px) and `gargosy_logo.ico` (16–256 px).
- To change it, edit the SVG and render again.
- `assets/branding/drafts/` keeps the other drafts for later use (A1/A2 controller, B2 G with a D-pad, C1 controller with player badges).
- The logo uses v2's purple with Gargosy's own gold `#F2C14E` and teal `#3DD6C4`, in a rounded square.
- Never use RomM's circle, its diagonal split or its logo.

## Testing
- `flutter_test` + `mockito` (`@GenerateMocks` + `build_runner`) + `http_mock_adapter` + `fake_async`.
- `test/unit/` holds logic; `test/widgets/` holds widgets, including focus and controller navigation.
- Required tests:
  - profiles never share a path;
  - `PathGuard` rejects anything outside the allowed folders;
  - each emulator's `ProfileLaunchConfig` arguments or written keys;
  - device pairing states.
- Gate: `flutter analyze && flutter test` (also what CI runs, on `windows-latest`).

## Release
A zip that unpacks to `Gargosy\` with empty `roms\`, `emulators\`, `bios\` and `userdata\`. There is no installer. An update replaces only the app files.
