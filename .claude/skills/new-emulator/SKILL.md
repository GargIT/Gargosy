---
name: new-emulator
description: Use when adding a new emulator to Gargosy, or making an existing one play per profile. Lists every place an emulator is wired in, so none is missed.
---

# Adding an emulator to Gargosy

An emulator is supported only when it can be pointed at the profile's data folder
(`userdata\profiles\<id>\emulators\<emu>\`). Find out how first. If it can't be pointed, stop and say so: it is not supported.

## 1. Probe before writing code

Find how the emulator chooses its data folder: from its docs, its `--help`, and its source.
Pick one mechanism, in this order of preference:

1. **arg**: a command-line argument at launch (Dolphin `--user=`, PCSX2 `-datapath`, MAME `-inipath …`).
2. **settings**: files or keys written into its folder just before launch (PPSSPP `installed.txt`, DuckStation, mGBA, Flycast).
3. **link**: a junction from a folder next to its exe to the profile (`LinkedFolderConfig`: Eden, Azahar, Cemu, melonDS).

Never copy saves in or out of a shared folder.

## 2. Wire it in (ScummVM, #11, is a complete example: `git show 0fe14a9 --stat`)

| What | Where |
|---|---|
| Download, exe names, platforms | `lib/core/emulator/emulator_registry_data.dart` (`id`, `platform_slugs`, download source) |
| Launch strategy | new file `lib/core/emulator/strategies/<emu>_strategy.dart`, registered in `strategy_registry.dart` **only** (the `allPossibleStrategies` list) |
| Pointing at the profile | `lib/emulators/profile_launch_config.dart` (arg / settings), or `lib/emulators/linked_emulators.dart` (link) |
| Data folder layout | `lib/emulators/emulator_layout.dart`: `saveView`, `seed` folders, `markers` |
| Its user data in an install | `EmulatorLibrary.dataNames` in `lib/emulators/emulator_library.dart` |
| Full screen flags | `lib/emulators/fullscreen.dart` (`on:` / `off:`) |
| Save sync | new file `lib/core/save/strategies/<emu>_save_strategy.dart`, registered in `save_sync_service.dart` **only**. A game id goes through `GameIdResolver` (RomM's `titleId`/`saveTarget` first). If sigil syncs the platform, wrap it through `SigilSaveStrategy` instead |
| Save states | `StateSyncCapable` on the save strategy, plus a resume argument in the launch strategy; add its row to `test/unit/profile_state_dirs_test.dart` |
| Folder-based games | `RomConstants.folderGamePlatforms` (`lib/core/romm/rom_constants.dart`) |

Rules that apply here (from CLAUDE.md):
- No emulator logic in the UI.
- Take `PlatformInfo` as a constructor parameter. Never use `Platform.isWindows` directly.
- Every write goes through `PathGuard`.
- A strategy copied from Freegosy starts with `// Adapted from Freegosy (MIT, © 2026 abduznik).`, and its tests come along with it.

## 3. Tests (required)

- `test/unit/profile_launch_config_test.dart`: the exact arguments or written keys for the new emulator.
- `test/unit/<emu>_profile_test.dart`: two profiles never share a path, and the settings are put back after the session.
- `test/unit/emulator_library_test.dart`: `dataNames` and the exe search.
- The save strategy: where saves are read from and restored to.

## 4. Docs

- `docs/emulator-profiles.md`: add a row with the mechanism, the exact args or keys, and where saves land. Put it under "Not probed" until a person has run it.
- `docs/hand-tests.md`: add numbered `[ ]` rows: install, play on two profiles, saves stay apart, sync.
- `CLAUDE.md` file map: list the new files.
- `CHANGELOG.md`: a line under `[Unreleased]`.
- `README.md`: the list of supported emulators.

## 5. Gate

`dart format lib test tool && flutter analyze && flutter test`
