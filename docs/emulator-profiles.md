# Emulators and profile data folders

How Gargosy points each emulator at the profile's own folder (spec §6). That folder is `<data>` below, meaning `userdata\profiles\<id>\emulators\<emulatorId>\`.

- **Checked by hand on 2026-10-08.** Each emulator was a copy of the user's install from `C:\Retro\emulators`, run from `%TEMP%`.
- **How each probe worked:** start the copy with the arguments below, wait about 12 s, close it politely so it saves its settings, then compare.
- **What "pass" means:** files appeared in `<data>`, and nothing next to the exe was created or changed.
- **Mechanisms:**
  - `arg`: a command-line argument at launch.
  - `settings`: Gargosy writes a file or keys into the emulator's own folder just before launch. This is safe because only one emulator runs at a time.

| emulatorId | Version | Mechanism | Exact args / file + keys | Settings follow profile | Saves land in | Evidence |
|---|---|---|---|---|---|---|
| dolphin | (no version resource; `Dolphin-x64` build) | arg | `--user="<data>"` | yes (`Config\Dolphin.ini` etc. in `<data>`) | `<data>\GC`, `<data>\Wii` | pass; works even with `portable.txt` next to the exe |
| pcsx2 | 2.8.2.0 | arg | `-datapath "<data>"`, and the install must have **no** `portable.txt` / `portable.ini` (portable mode overrides `-datapath`, as `-help` says) | yes (`<data>\PCSX2\inis\PCSX2.ini`) | `<data>\PCSX2\memcards`, `<data>\PCSX2\sstates` | first run with `portable.txt` failed (wrote to the exe folder); pass once it was removed. PCSX2 adds a `PCSX2\` level inside `<data>` |
| retroarch | (no version resource) | arg | `--config="<data>\retroarch.cfg"`, with a cfg that sets `savefile_directory`, `savestate_directory`, `system_directory`, `playlist_directory`, `content_history_directory`, `input_remapping_directory`, `rgui_config_directory`, `log_dir` under `<data>`, plus `core_info_cache_enable = "false"` | yes (the whole `retroarch.cfg`, saved on exit) | `<data>\saves`, `<data>\states` | pass. With only the three save keys, it still wrote playlists and `core_info.cache` next to the exe (paths starting `:\` are relative to the exe) |
| mame | 0.289 | arg | `-inipath "<data>" -homepath "<data>" -cfg_directory "<data>\cfg" -nvram_directory "<data>\nvram" -state_directory "<data>\sta" -input_directory "<data>\inp" -snapshot_directory "<data>\snap" -diff_directory "<data>\diff" -comment_directory "<data>\comments"` | yes (`cfg\default.cfg`, `ui.ini`) | `<data>\nvram`, `<data>\sta` | pass |
| xenia_canary | (no version resource) | arg | `--content_root="<data>\content" --storage_root="<data>\storage" --cache_root="<data>\cache" --log_file="<data>\xenia.log"` | yes (`storage\xenia-canary.config.toml`) | `<data>\content` (game saves are content) | pass. Without `--log_file`, `xenia.log` was written next to the exe |
| ares | v148 (folder name) | arg | `--settings-file "<data>\settings.bml" --setting Paths/Saves="<data>\saves\" --setting Paths/Firmware="<data>\firmware\"` | yes (`settings.bml`), except the window layout | `<data>\saves` | pass, except that `hiro\windows.bml` (window positions) is still written next to the exe. Harmless: no saves or settings |
| ppsspp | v1.20.4 | settings | `installed.txt` next to the exe containing the full `<data>` path, and **no** `memstick\` folder next to the exe (that one forces portable mode) | yes (`PSP\SYSTEM\ppsspp.ini` lives on the memory stick) | `<data>\PSP\SAVEDATA`, `<data>\PSP\PPSSPP_STATE` | pass. `memstick_dir.txt` was ignored, and with `memstick\` present everything went there |
| duckstation | 0.1.11894 | settings | `settings.ini` next to the exe (`portable.txt` install): `[MemoryCards] Directory`, `[Folders] Cache, Cheats, Covers, GameIcons, GameSettings, InputProfiles, Patches, SaveStates, Screenshots, Shaders, Subchannels, Textures, UserResources, Videos` set to absolute paths under `<data>` | **no**: `settings.ini` itself stays next to the exe. `-help` has no settings or data path argument | `<data>\memcards`, `<data>\savestates` | pass for folders (all 14 created in `<data>`, nothing new next to the exe) |
| mgba | 0.10.5 | arg | `-C savegamePath="<data>\saves" -C savestatePath="<data>\states"` (transient, not saved to `config.ini`) | **no**: `config.ini` / `qt.ini` stay next to the exe (`portable.ini` install) | `<data>\saves`, `<data>\states` | the overrides were not written into the shared `config.ini`. Saves under `<data>` not seen yet: no game was run |
| flycast | v2.7-1 | arg | `-config config:Dreamcast.SavePath=<data>\saves,config:Dreamcast.VMUPath=<data>\vmu,config:Dreamcast.SavestatePath=<data>\states` (transient) | **no**: `emu.cfg` stays next to the exe | `<data>\vmu`, `<data>\states` | the transient values were not saved to `emu.cfg`. VMU files under `<data>` not seen yet: no game was run |
| xemu | 0.8.136 | arg | `-config_path "<data>\xemu.toml"`, and in that toml `[sys.files] eeprom_path` and `hdd_path` under `<data>` (the first launch copies `bios\xbox_hdd.qcow2` there, never replaced after), and `bootrom_path` / `flashrom_path` to `bios\mcpx_1.0.bin` / `bios\Complex_4627.bin` unless the profile names files that exist | yes (`xemu.toml`) | inside the HDD image at `hdd_path` (Xbox saves live on the virtual disk) | pass for the config. The default `eeprom_path` points at `%APPDATA%\xemu`, so it **must** be set in the profile's toml |

## Not probed (not installed in `C:\Retro\emulators`)

These rows come from the emulators' documentation and from Freegosy, not from a run. Each must be probed when Gargosy installs the emulator, and dropped from v1 if it fails.

| emulatorId | Expected mechanism (to verify) |
|---|---|
| ryujinx | arg: `--root-data-dir "<data>"` (`-r`) |
| cemu | arg: `-mlc "<data>\mlc01"` for saves; settings (`settings.xml`) likely stay next to the exe |
| eden | settings: a `user\` folder next to the exe makes it portable; per-profile needs the NAND/SDMC keys in `qt-config.ini`, or a data-folder argument if the build has one |
| azahar | as eden: `user\` folder; per-profile through the SDMC/NAND keys in `qt-config.ini` |
| melonds | settings: `melonDS.toml` next to the exe; save and state path keys |
| rpcs3 | settings: `config\vfs.yml`, key `$(EmulatorDir)dev_hdd0/` pointing under `<data>` |
| scummvm | arg: `--config="<data>\scummvm.ini" --savepath="<data>\saves"` |

## RetroArch saves through sigil (issue #7)

Checked on 2026-10-12 against argosy-sigil v1.0.0 (`third_party/argosy-sigil`), built for the tests and called the way Gargosy calls it (`test/unit/sigil_retroarch_test.dart`, real save files, no emulator run). The layout is the game's core without `_libretro`.

| System | Cores tried | Unit (what goes to RomM) | Restore writes | Result |
|---|---|---|---|---|
| Game Boy | `gambatte`, `sameboy`, `mgba`, a core sigil has no row for | `<stem>.srm`, raw | `<stem>.srm` | pass. An RZIP save (`save_file_compression`) gives the same raw unit and hash; restore writes it plain. A zip ROM (`x.zip#Tetris (World).gb`) saves under the member's name |
| Game Boy Color, cart with a clock | `gambatte` | `<stem>.zip` with `save.sram` and `clock.rtc` (sigil's own form) | `<stem>.srm` and `<stem>.rtc` | pass. The clock is read from the ROM's header, so it needs the ROM file |
| N64 | `mupen64plus_next` | `<stem>.zip` with `eeprom`, `pak1`–`pak4`, `sram`, `flash` | `<stem>.srm`, byte for byte | pass |
| PS1 | `pcsx_rearmed` | the game's card `<stem>.srm` | `<stem>.srm` | pass |
| PS2 (LRPS2) | `pcsx2`, root `system\pcsx2\memcards` | an 8 MB card with only this game's saves | shared `Mcd001.ps2`: this game's saves replaced, the other games' left; `pcsx2_shared_memory_cards=disabled`: `<stem>.ps2` | pass, on cards made by Gargosy's card writer, **not yet on a card LRPS2 made** |
| SNES, GBA, Genesis, NES, NDS, arcade | `snes9x`, `mgba`, `genesis_plus_gx`, `fceumm`, `melonds`, `fbneo` | — | — | sigil's sync refuses them (`unsupported format`): RetroArch's own strategy keeps them |
| Saturn, Sega CD, Dreamcast | — | — | — | not checked (needs real volumes): RetroArch's own strategy keeps them for now |

## Not supported in v1

None so far. Every installed emulator passed with one of the two mechanisms.

## Notes for milestone C

- **Settings that stay shared.** Three emulators keep their settings next to the exe whatever we do: DuckStation (`settings.ini`), mGBA (`config.ini`, `qt.ini`) and Flycast (`emu.cfg`). Their saves are per profile, their settings are not. To meet spec B (settings per profile), Gargosy must copy the profile's settings file into place before launch and back afterwards. This is safe because only one emulator runs at a time. If Gargosy crashes, the file is copied back at the next start. Copying is for settings files only, never saves.
- **Installs Gargosy makes:**
  - PCSX2 without `portable.txt` / `portable.ini`.
  - PPSSPP without a `memstick\` folder.
  - Dolphin may keep `portable.txt`, because `--user` wins.
- **First-run wizards and dialogs** may open on a fresh profile. PCSX2 and DuckStation have setup wizards. The profile templates (`userdata\templates\<emu>\`) should be made with the wizard already done.
- **BIOS.** Point each profile's BIOS or firmware key at the shared `bios\`. The keys: PCSX2 `[Folders] Bios`, DuckStation `[BIOS] SearchDirectory`, RetroArch `system_directory` (or a `system` folder), ares `Paths/Firmware`, xemu `[sys.files] bootrom_path` / `flashrom_path`.
- **Leftovers in the shared install folder:** ares writes `hiro\windows.bml`. It's harmless, but `PathGuard` must allow writes inside `emulators\` (it does).
