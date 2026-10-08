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
Update this section as files are created. Milestone A (log in) is in; B (browse) and C (play and sync) add to it.

### Entry points
- `lib/main.dart` — finds the root (`AppRoot.fromArgs`; `--root=<dir>` for `flutter run`), checks it can be written (else `StartupErrorApp`), points `path_provider` and `shared_preferences` into `userdata\`, starts the window, runs `GargosyApp`.
- `lib/app.dart` — `GargosyApp`: theme, `InputRouter`, F11; the profile picker when no profile is active, else `AppShell`. A profile switch pops every pushed page.

### Core (copied from Freegosy unless marked new)
- `core/platform/platform_info.dart`, `window_service.dart` — platform abstraction; fullscreen (`launch_fullscreen` pref, `--fullscreen`).
- `core/storage/app_preferences.dart` + `shared_preferences_app_preferences.dart` — prefs interface; `logger_service.dart`, `ini_file.dart`, `safe_fs.dart`.
- `core/storage/json_file_preferences_store.dart` (adapted) — `SharedPreferences` in `userdata\settings.json`, atomic writes, damaged file kept aside.
- `core/storage/gargosy_path_provider.dart` (adapted) — `path_provider` folders in `userdata\app\`.
- `core/security/dpapi.dart` (adapted) — `DataProtector`, DPAPI, `readMachineGuid()`.
- `core/romm/romm_models.dart`, `save_target_layout.dart`, `core/retroachievements/retroachievements_game_models.dart` — RomM models.
- `core/romm/romm_auth_client.dart` (new) — `RommAuth`: device pairing (`/api/auth/device/init|token`), password → never-expiring client token (Basic auth, `/api/client-tokens`), `/api/users/me`, avatar. `gargosyScopes`. Never follows redirects.
- `core/input/` — `gamepad_service.dart` (moves focus with the D-pad, sets gamepad mode), `input_action_bus.dart`, mappings, SDL DB, deadzone. `providers/ui_provider.dart` (trimmed): `InputMode`, `inputModeProvider`, `navigationLockedProvider`.

### Profiles (new)
- `profiles/app_root.dart` — the layout on disk; `ensureLayout()` throws when the folder can't be written.
- `profiles/path_guard.dart` — `PathGuard.check/join/forProfile`: the only writable places.
- `profiles/json_file.dart` — `readJsonObject(Sync)`, `writeJsonObject`, `writeBytesAtomic` (tmp + rename, through the guard).
- `profiles/pbkdf2.dart`, `pin.dart` — `PinHash` (PBKDF2-SHA256, 60 000 rounds, verify in an isolate), `PinGate` (5 tries, then 30 s).
- `profiles/profile.dart`, `profile_paths.dart`, `profile_store.dart` — a profile, its paths, create (copies `templates\`) / list (sync reads) / save / delete / last used.
- `profiles/pc_identity.dart`, `login_store.dart` — `login.<PC>-<user>-<id8>.dpapi` per profile; `ProfileLogin { token, kind: device|client-token, deviceId }`.
- `profiles/device_login.dart` — `DeviceLoginFlow`: polls at the server's interval, +5 s on `slow_down`, keeps going through network errors, stops at expiry.
- `profiles/profile_providers.dart` — root/prefs/protector/PC/auth-factory providers (overridable in tests), `profilesProvider`, `activeProfileProvider` (`ProfileContext`), `pinGatesProvider`.

### UI (new)
- `ui/theme/tokens.dart` (RomM v2 values: `GColors`, `GSpace`, `GRadius`, `GFont`, `GMotion`, `GFocusRing`, `GLayout`), `gargosy_theme.dart`.
- `ui/input/gargosy_intents.dart`, `input_router.dart` — controller actions → intents on the focused widget (A, hold A, B, X, Y, LB/RB, Start); Escape/PgUp/PgDn/F11; mouse/keyboard mode. An unhandled `BackIntent` pops the route.
- `ui/widgets/g_focusable.dart` (focus ring for pad/keyboard, hover for mouse), `hint_bar.dart`, `profile_badge.dart`, `on_screen_keyboard.dart` (+ `showOnScreenKeyboard`), `pin_pad.dart` (+ `showPinEntry`).
- `ui/shell/app_shell.dart` (tabs Home/Platforms/Collections/Search, LB/RB, Start), `top_bar.dart` (v2 top bar; glass once scrolled), `user_menu.dart`, `destination_page.dart`, `backdrop.dart`.
- `ui/screens/profile_picker_screen.dart` ("Who is playing?": PIN, re-login, X = options/delete), `add_profile_screen.dart` (server → login → name/colour → PIN), `login_step.dart` (pairing QR or password; refuses another RomM user on re-login), `profile_options_dialog.dart`, `startup_error_app.dart`.

## Branding
- The app logo is the "G" with three face buttons: `assets/branding/gargosy_logo.svg`. It's the source for `gargosy_logo.png` (1024 px) and `gargosy_logo.ico` (16–256 px).
- To change it, edit the SVG and render again.
- `assets/branding/drafts/` keeps the other drafts for later use (A1/A2 controller, B2 G with a D-pad, C1 controller with player badges).
- The logo uses v2's purple with Gargosy's own gold `#F2C14E` and teal `#3DD6C4`, in a rounded square.
- Never use RomM's circle, its diagonal split or its logo.

## Testing
- `flutter_test` + `mockito` (`@GenerateMocks` + `build_runner`) + `fake_async`. HTTP is faked with `test/helpers/fake_dio_adapter.dart`.
- `test/helpers/app_harness.dart` builds the whole app with fakes (protector, PC identity, RomM auth); its `settle()` lets file IO and timers finish (one round per sequential async step).
- `test/unit/` holds logic; `test/widgets/` holds widgets, including focus and controller navigation.
- Required tests:
  - profiles never share a path;
  - `PathGuard` rejects anything outside the allowed folders;
  - each emulator's `ProfileLaunchConfig` arguments or written keys;
  - device pairing states.
- Gate: `flutter analyze && flutter test` (also what CI runs, on `windows-latest`).

## Release
A zip that unpacks to `Gargosy\` with empty `roms\`, `emulators\`, `bios\` and `userdata\`. There is no installer. An update replaces only the app files.
