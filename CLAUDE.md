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
- RomM calls from UI go through the providers in `lib/providers/` (which use `RommService` / `LibraryApi`).
- Downloads stage in `userdata\app\temp`; `roms\` only ever receives complete ROMs.
- Write files with LF line endings (`.gitattributes` normalizes). From Python, use `open(..., 'w', newline='\n')`.
- Commit messages, PR titles and PR descriptions never contain a link to the session that made them (no `claude.ai/code/session_…` line).

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
- `lib/main.dart` — finds the root (`AppRoot.fromArgs`; `--root=<dir>` for `flutter run`), checks it can be written (else `StartupErrorApp`), points `path_provider`, `shared_preferences` and TMP/TEMP (`profiles/portable_temp.dart`) into `userdata\`, starts the window, runs `GargosyApp`.
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
- `ui/widgets/g_focusable.dart` (focus ring for pad/keyboard, hover for mouse), `hint_bar.dart`, `profile_badge.dart` (+ `ProfileAvatar`, the circle alone, not focusable), `on_screen_keyboard.dart` (+ `showOnScreenKeyboard`), `pin_pad.dart` (+ `showPinEntry`).
- `ui/shell/app_shell.dart` (tabs Home/Platforms/Collections/Search, LB/RB, Start), `top_bar.dart` (v2 top bar; glass once scrolled; `index` null lights no tab), `page_top_bar.dart` (the bar on the game page and the gallery: a tab closes them and shows that tab), `shell_menu.dart` (`shellTabs`, `shellTabProvider`, `openUserMenu` shared by the shell and pages: a settings item opens `SettingsScreen(initial:)`, Changelog the reader), `user_menu.dart` (RomM v2's menu: avatar, name + version, one item per `SettingsPage` in its group, Fullscreen, About · Changelog, Switch profile last in red; focus on Profile; scrolls when short), `destination_page.dart`, `backdrop.dart`.
- `ui/screens/profile_picker_screen.dart` ("Who is playing?": PIN, re-login, X = options/delete), `add_profile_screen.dart` (server → login → name/colour → PIN), `login_step.dart` (pairing QR or password; refuses another RomM user on re-login), `profile_options_dialog.dart`, `startup_error_app.dart`.

### Library (milestone B)
- `core/romm/romm_service.dart` (adapted copy, ~1060 lines: one cohesive client, kept close to Freegosy) — every RomM call; token only, no password code. `dio` / `authOptions` getters for the library API.
- `core/romm/romm_state.dart` (copied) — save states on RomM; `core/constants/app_constants.dart` (copied) — app version.
- `core/romm/romm_library_api.dart` — `LibraryApi` / `RommLibraryApi`: gallery pages (`GalleryQuery`: platform / collection / favourites / search, `GallerySort`, genre and region filters, `FilterValues`), collections (`RommCollection`), favourites (the user's own `is_favorite` collection, created once when missing).
- `providers/romm_providers.dart` — `rommServiceProvider` and `libraryApiProvider`, built from the active profile's server and token.
- `providers/library_providers.dart` — platforms, collections, favourite ids, Home shelves, a game, its saves, states and notes, RA progress; `coverUrlFor`, `assetUrl`, `toggleFavourite`.
- `library/rom_files.dart` — a game's ROM at `roms\<platform>\<fs_name>` (file or folder), names made safe; downloaded?; delete. A `.zip` game unpacked for an emulator sits in `<name without .zip>\` (`unpackedDirFor`), and `pathFor` finds it there.
- `library/rom_preparer.dart` — `RomPreparer.ready` (via `PlayEngine.readyRom`, before launch; progress in `PlayState.preparing`): a zip the emulator can't open (`zipReaders`; never on arcade platforms) is unpacked once with Windows' `tar.exe` into the game's folder, and the zip goes; for xemu an original Xbox disc becomes an XISO. `library/xbox_disc.dart` — `detectXboxDisc`, `XisoWriter` (streams out of `tar -xO`, drops a Redump image's video partition at 0x18300000), `redumpToXiso`.
- `library/download_service.dart` — download staged in `userdata\app\temp`, then moved into `roms\`; multi-file zips unpacked through `PathGuard.join` (no zip-slip); a single file is never unpacked.
- `providers/download_providers.dart` — `downloadsProvider` (progress, cancel, delete), `watchDownloaded`.
- `ui/input/wrap_grid_policy.dart` — grid focus wraps row to row.
- `ui/widgets/cover_image.dart` (`coverImageBuilderProvider`, cached covers), `game_card.dart`, `shelf.dart`, `cover_grid.dart` (paging, wrapping focus), `error_retry.dart`, `format.dart`.
- `ui/pages/home_page.dart`, `platforms_page.dart`, `collections_page.dart`, `search_page.dart` — the shell's tabs.
- `ui/pages/platforms_page.dart` — the Platforms tab: heading with counts, the Covers setting (`GDropdownField`), responsive grid (max 300 px → 6 / 4 / 3 per row). `platform_card.dart`: a fan of up to five covers, logo, name, "maker · year · N games"; the logo large when there are no covers.
- `ui/widgets/platform_logo.dart` — RomM's `/assets/platforms/<slug>.svg` (`flutter_svg`, drawn from the image cache; a 404 isn't asked again this session), `PlatformBadge` fallback; tests get the badge (`widget_env.dart`).
- `ui/widgets/romm_images.dart` — `rommImageCacheProvider`: covers and logos downloaded with the profile's self-signed setting (`trustCertificate`: only the RomM host, only when trusted) and kept on disk under `userdata\app\`.
- `library/platform_facts.dart` — maker and year for the common systems; `platformLine`. `library/platform_covers.dart` — the Covers choices — top rated, random, recently added, last played, logo only (`coversFor`, `PlatformCoversChoice`, profile pref `platforms.covers`, `PlatformCoversKey`); providers in `library_providers.dart`.
- `ui/screens/gallery_view.dart` (paged grid; X = sort and filters), `gallery_screen.dart`, `filter_sheet.dart`.
- `ui/screens/game/` — `game_screen.dart` (the page after Freegosy's: art, cover column, pills, tabs with badges; LB/RB tabs, Y resumes the newest state, the top bar), `game_cover_column.dart` (cover 240 × 324, Play/Download/progress, ♥, the ⋯ menu; `folderOpenerProvider`), `game_personal_pills.dart` (status with Backlog/Now playing, rating, completion → RomM; goes back if refused), `game_tabs.dart`, `saves_tab.dart` (manage mode: X puts a save on this PC, hold A deletes, Upload, Back up now, Saves | States), `overview_tab.dart` (last played), `achievements_tab.dart`, `notes_tab.dart` (new notes private), `details_tab.dart`, `open_game.dart`.

### Play and save sync (milestone C1)
- `core/` also holds Freegosy's save and launch engine, copied unchanged apart from the lines below: `core/save/` (sync, formats, catalog, backups, state sync, strategies), `core/emulator/` (strategies, registry, `game_launch_service.dart`, downloads), `core/extraction/`, `core/windows/`. Gargosy's patches: `backup_repository.dart` / `backup_service.dart` take the profile's box and folder; `mgba_save_strategy.dart` uses the profile's `saves\` when the folder service is `ProfileRootedDirectories`; `secure_storage_service.dart` keeps DPAPI blobs in prefs. PCSX2, DuckStation and RetroArch's PS2 core read disc serials through `RomGameIds` (sigil) instead of Freegosy's serial service.
- `sigil/` — argosy-sigil (C, MPL-2.0; submodule `third_party/argosy-sigil`, pinned to v1.0.0), the only place that uses `dart:ffi` for it. `sigil_library.dart` (finds `sigil.dll` beside `Gargosy.exe`; tests point `SigilLibrary.path` at a build in `test/flutter_test_config.dart`), `sigil_bindings.dart` (hand-written; layouts pinned to MSVC x64 in `sigil_bindings_test.dart`; the measured layouts of the sync structs are in the stage 1 plan), `sigil_engine.dart` (`SigilEngine.identify`, each call in `Isolate.run`), `sigil_platforms.dart` (RomM slug → sigil's), `rom_game_ids.dart` (`RomGameIds.discSerial`: remembered serial, else sigil, else the serial in the file name). Save sync (stage 2): `sigil_sync.dart` (`SigilSyncCall`, `runSigilSync`: the save root listed, open/write/remove callbacks confined to it by `sigilRootPath`), `SigilEngine.collect`/`restore`, `sigil_save_strategy.dart` (`SigilSaveStrategy` wraps an emulator's old strategy for the platforms sigil syncs there — PCSX2 PS2, DuckStation PS1, Dolphin GameCube, PPSSPP, Flycast Dreamcast (new), mGBA GB/GBC; units go to RomM's `autosave` slot; states stay with the old strategy), `sigil_state_store.dart` (`profiles\<id>\sigil\<emulator>\<rom id>.state`, written after an upload), `sigil_profile.dart` (`sigilSavesFor(paths)` → `SaveSyncService(wrapSaves:)`). `SaveStrategy` gained `uploadSlotFor(game)`, `afterUpload`, `restoresUnitsItselfFor(game)`. `windows/CMakeLists.txt` builds `sigil.dll` beside `Gargosy.exe` (once, then incrementally); on a fresh checkout run `powershell -File tool/build_sigil.ps1` before `flutter test` (CI does). Both builds include `windows/sigil.cmake` (sigil's options and `add_subdirectory`; under MSVC `card_ps2.c` unoptimized, its PS2 card check is miscompiled otherwise); `tool/sigil/CMakeLists.txt` is the script's wrapper.
- `profiles/profile_preferences.dart` — `ProfilePreferences`: the profile's own `prefs.json` (emulator choices, sync records); the engine never reads app-wide prefs.
- `profiles/portable_temp.dart` — `usePortableTemp()`: TMP/TEMP into `userdata\app\temp` (the save code's working copies stay in the Gargosy folder).
- `emulators/emulator_layout.dart` — per emulator: the folder its save strategy treats as the install (`saveView`), app-support name, `seed` folders made before the first pull.
- `emulators/profile_directories.dart` — `sandboxedPlatform()` (APPDATA/LOCALAPPDATA/USERPROFILE inside the profile), `ProfileSaveDirectories` (what save strategies see), `ProfileLaunchDirectories` (finds the real exe under `emulators\<id>`, launches with the profile's `ProfileLaunchConfig`, `repoint()` before a pull). `core/storage/profile_rooted.dart` is the marker interface.
- `emulators/profile_launch_config.dart` — per emulator, how it's pointed at `profiles\<id>\emulators\<emu>`: arguments (Dolphin, PCSX2, MAME, Xenia, ares, xemu), RetroArch's profile cfg (own `system\` with the BIOS copied in), PPSSPP `installed.txt`, or settings files swapped in for the session (DuckStation, mGBA, Flycast; `.gargosy-swap` marker, put back to the owner after a crash). `repoint()` rewrites stored folder paths. `config_files.dart`: `setRetroArchKeys`, `setTomlKeys`.
- `emulators/fullscreen.dart` — `Fullscreen`: the play screen's Full screen switch per emulator and profile (on by default), and each emulator's flag; `ProfileLaunchDirectories` puts it first on the command line (RetroArch off goes in its cfg).
- `emulators/emulator_library.dart` — `EmulatorLibrary` (list, import from a folder, remove), `emulatorsProvider`. Settings → Emulators (`ui/screens/settings/emulator_install_section.dart`): Import / Download / Update / Remove, BIOS from RomM.
- `providers/engine_providers.dart` — the engine for the active profile: prefs, both directory views, `StrategyRegistry`, `SaveSyncService`, backups (Hive box in the profile folder), `GameLaunchService`.
- `play/play_engine.dart` — `PlayEngine` (the seam tests fake) and `GargosyPlayEngine`: repoint, back up + pull (`pre_launch_pull.dart`: `SaveRestoreGuard`, 20 s wait for shared cards, never refuses the launch), launch, sync after exit → `PlayResult` message.
- `play/play_controller.dart` — `PlayController.play`: one game at a time (claimed before the first await), reasons it can't start, the session's end message; the shell refuses a profile switch while a game runs.

### Play screen, states, offline, settings (milestone C2)
- `play/play_menu.dart` — `PlayMenu` (installed emulators for the game, remembered/default one, `SaveCatalog`) and `EmulatorOption`; built by `PlayEngine.menuFor`.
- `play/play_engine.dart` also: `StatePull`, `statesFor`, `pullStates` (when state sync is on and RomM reachable; conflicts keep this PC's copy), `checkResume`, launch with `loadStatePath`. `play/pre_launch_pull.dart` also has `placeChosenSave` (the play screen's choice put in place, a RomM save marked synced).
- `play/play_controller.dart` also: `resume(game, ResumeEntry)`, `playMenuProvider` / `playStatesProvider` (`PlayMenuKey`).
- `core/save/catalog/play_request.dart` (copied), `ui/play/emulator_choices.dart` (copied), `ui/widgets/save_list/save_labels.dart` (copied: sizes and times as RomM shows them), `ui/widgets/controller_dialogs.dart` (`showConfirm`, `showChoice`).
- `ui/screens/play/play_screen.dart` (three panels: cover + Play/Resume + what A does; Saves | States; ⚙ Plays in — one row above the list below 1100 px. LB/RB Saves/States, Y emulator, X folds; prompts for an older save or state and for a state from another build), `play_settings_panel.dart` (emulator and RetroArch core as dropdowns, Full screen, Always, hidden + Show all). The game page's Play opens it.
- `ui/widgets/g_dropdown.dart` — RomM-style select: `GDropdownField` (outlined, icon, chevron) and `showDropdown` (the list under the field, ✓ on the current).
- `ui/widgets/outlined_back_button.dart` — the outlined Back at the bottom of the cover column (game page, play screen).
- `ui/widgets/game_transition.dart` — what the game page and play screen share for a smooth switch: `GameArtBackdrop` (blurred art), `fadeRoute`, `coverHero`/`titleHero`.
- `ui/widgets/save_list/` — `save_list.dart` (`SaveList`: This PC with backups folded, On RomM by slot with older versions folded; choose / manage mode; two columns from 1100 px), `save_row.dart` (tags: emulator, on RomM, converted; greyed with why), `state_list.dart`, `save_labels.dart`.
- `play/save_actions.dart` — `SaveActions`: restore, delete, upload, back up, sync states for the game page; refused while a game runs; the list read again after a change. `PlayEngine` has the matching `restore`/`deleteSave`/`upload`/`backUpNow`/`syncStatesNow`/`setRommUser`; `EmulatorOption.cores` holds RetroArch's cores for the platform.
- `providers/engine_providers.dart` also: `stateSyncServiceProvider`, `resumeServiceProvider`, `syncActivityProvider` (what the save lock is busy with), `backupsBoxName`.
- `library/library_snapshot.dart` — `LibrarySnapshot` (`profiles\<id>\cache\library.json`: the profile's downloaded games as RomM described them), `gamesOnThisPcProvider`. `gameProvider` falls back to it offline.
- `library/upload_queue.dart` — `UploadQueue`: sessions RomM didn't take, retried through the normal push (newest per game, oldest game first, stops at a failure); runs when the profile opens and when RomM is back. `uploadsWaitingProvider` feeds the Save Data tab.
- `providers/romm_providers.dart` also: `rommOfflineProvider` (starts RomM's 5 s heartbeat; `rommHeartbeatEnabledProvider` turns it off in tests). The shell shows a banner while offline; Home shows "On this PC".
- `ui/screens/settings/about_section.dart` — `showAboutGargosy` (the user menu's About dialog) and `AboutSection` (also Settings → About): versions, the documents in the Gargosy folder, `showLicensePage`, GitHub. `providers/about_providers.dart` — `externalOpenerProvider` (web links and folders; tests replace it), `rommServerVersionProvider`.
- `ui/screens/doc_reader_screen.dart` — `DocReaderScreen` / `openDoc`: a file from the Gargosy folder, Markdown (`flutter_markdown_plus`, `docStyleSheet`) or plain text; D-pad/arrows scroll, LB/RB a page, X the links (`markdownLinks`); a file link opens in the reader, a web link or folder outside.
- `ui/screens/settings/` — RomM v2's profile page. `settings_pages.dart` (`SettingsPage`/`SettingsGroup`: the sections and their groups, shared 1:1 by the sidebar and the user menu), `settings_screen.dart` (`PageTopBar`; the grouped sidebar PROFILE / LIBRARY / THIS PC / GARGOSY, headings never focused; `SettingsScreen(initial:)`; LB/RB), `profile_section.dart` (avatar header; Profile, PIN, Delete cards; delete names waiting uploads), `device_sections.dart` (Controller: deadzone − bar +; Display: fullscreen), `emulator_install_section.dart` (Emulators: install, update, remove, BIOS), `emulators_section.dart` (Emulator settings: emulator per platform, state sync per emulator until the plan's S0.4), `ra_section.dart` ("Connected as" badge), `settings_rows.dart` (`SettingsCard`, `SettingsField`, `SettingsBadge`, `SettingsButton`, `SettingsToggle`, `SettingsLinkRow`). Mockups: issue #6.
- `retroachievements/ra_account.dart` — `RaAccount`: the profile's RA login (password exchanged once for the Connect token via the copied `core/retroachievements/retroachievements_service.dart`; never stored). RetroArch signs in with it at launch.
- `emulators/emulator_installer.dart` — `EmulatorInstaller` (`latestUrl`, `install`), `InstallProgress`; `EmulatorLibrary.recordInstall` notes the source in `emulators\<id>\.gargosy-install.json`, `EmulatorInfo.version` is the exe's file version. Update installs only when the newest download differs.
- `profiles/profile_providers.dart` also: `ActiveProfileNotifier.update` (rename, PIN).
- `emulators/bios_sync.dart` — `BiosSync`: RomM's firmware into the shared `bios\` through the copied `FirmwareService` (patched: in a profile PCSX2/DuckStation files go in `bios\` itself, and a server file name never leaves the folder); runs after an emulator installs and from Settings → Emulators.
- Launch settings also fill the emulators' own game lists from `roms\<platform>` (`ProfileLaunchDirectories.gameFoldersFor`, `IniFile.add` for repeated keys), set PCSX2's BIOS folder and its RA login (`LaunchContext.raLogin`). The engine's strategies run on `sandboxedPlatform` too, and their own RA writers are off in a profile.
- `ui/widgets/sync_wait.dart` — `waitForSyncIdle`: switching or deleting a profile waits for its save lock and upload queue, saying what it waits for (both are refused while a game runs).
- `docs/state-sync-plan.md` — spec and plan for save-state sync on more emulators (one global switch; local states resumable with sync off; DuckStation's wiring traced; states never in save zips; PPSSPP → Dolphin → mGBA → MAME → Flycast → ares).
- `tool/make_release.ps1` — builds and packs `dist\Gargosy-<version>.zip`. `tool/make_dev_release.ps1` — runs it (version `<pubspec>-dev`) and installs the zip into `C:\Retro\apps\gargosy` (`-Target`), replacing only the app files. `thirdparty/7zr.exe` is bundled (LGPL, see `NOTICE.md`) to unpack `.7z` emulator downloads.
- `.github/pull_request_template.md` — every PR's description: Closes, What changes, Not in this PR, Tests, and a checklist of the rules above. Fill it in, don't drop its sections.

## Branding
- The app logo is the "G" with three face buttons: `assets/branding/gargosy_logo.svg`. It's the source for `gargosy_logo.png` (1024 px) and `gargosy_logo.ico` (16–256 px).
- To change it, edit the SVG and render again.
- `assets/branding/drafts/` keeps the other drafts for later use (A1/A2 controller, B2 G with a D-pad, C1 controller with player badges).
- The logo uses v2's purple with Gargosy's own gold `#F2C14E` and teal `#3DD6C4`, in a rounded square.
- Never use RomM's circle, its diagonal split or its logo.

## Testing
- `flutter_test` + `mockito` (`@GenerateMocks` + `build_runner`) + `fake_async`. HTTP is faked with `test/helpers/fake_dio_adapter.dart`.
- `test/helpers/widget_env.dart`: `testApp()` frames a widget (theme, input, covers as boxes, a Gargosy folder that doesn't exist unless `root:` is given) and `press()` sends a controller button (the D-pad moves focus like GamepadService). Fakes: `fake_library_api.dart`, `fake_download_service.dart`, `game_fixtures.dart`.
- `test/helpers/app_harness.dart` builds the whole app with fakes (protector, PC identity, RomM auth); its `settle()` lets file IO and timers finish (one round per sequential async step).
- `test/unit/` holds logic; `test/widgets/` holds widgets, including focus and controller navigation.
- Required tests:
  - profiles never share a path;
  - `PathGuard` rejects anything outside the allowed folders;
  - each emulator's `ProfileLaunchConfig` arguments or written keys;
  - device pairing states;
  - the pre-launch pull (late pull writes nothing, failures don't block).
- Gate: `flutter analyze && flutter test` (also what CI runs, on `windows-latest`).

## Release
`pwsh tool/make_release.ps1` builds and writes `dist\Gargosy-<version>.zip`: it unpacks to `Gargosy\` with the app, empty `roms\`, `emulators\`, `bios\` and `userdata\`, and the licence files. There is no installer. An update replaces only the app files.
