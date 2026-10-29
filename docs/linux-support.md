# Linux support

The investigation for #192, as of 2026-10-28 (Gargosy `main` at `b9ae6fe`). No
code was changed for it. Sizes are S (a day or less), M (a few days), L (a
week or more).

## In short

- **Linux is doable.** The Windows-only code sits in about 20 files and
  most of it already has a seam. The two large parts are the emulators
  (how each is installed and pointed at a profile on Linux) and the
  release and update path. The rest is S or M each.
- **The case-insensitive `PathGuard` must change before any Linux build.**
  On Linux, a path that differs only in case is a different folder, and
  the guard would allow it.
- **Ship Linux as a folder, like the Windows zip, with emulators as
  AppImages in `emulators/`.** An AppImage of Gargosy itself is read-only
  inside, and Flatpak emulators can't see the profile folders; both break
  the portable rules.
- **Next:** the OS seams below are worth doing on Windows alone, since they
  make the code easier to test, and so is a Linux CI job for analyze and
  tests. Decide on a Linux milestone after those, if a Steam Deck build is
  wanted.

## Linux

### 1. Windows-only code

Each place, what it does on Windows, what Linux would use, and a size.

#### FFI and Win32

| Place | Windows | Linux | Size |
|---|---|---|---|
| `core/security/dpapi.dart` | DPAPI encrypts the RomM token per Windows user (`login.<PC>.dpapi`) | libsecret (needs a keyring; Steam Deck desktop has KWallet, Gaming Mode may have none). Fallback: a key file with mode 0600 in the profile, which is family-lock level like the PIN. Already behind `DataProtector`. | M |
| `core/input/xinput_pads.dart`, `hid_pads.dart`, `hid_buttons.dart` | The quit buttons are read while an emulator is in front, because GameInput sends nothing then | evdev (`/dev/input/event*`) is read the same whether Gargosy is in front or not. Desktop sessions get access through logind's `uaccess` for joysticks. One `BackgroundPads` (the interface exists) reading evdev replaces both. SDL's mapping DB still names the buttons. | M |
| `core/platform/window_service.dart` | `bringToFront`: `windowManager.focus`, then an Alt tap through `SendInput` | X11: `window_manager` focus works. Wayland doesn't let an app take focus, so Gargosy can't come back to the front by itself after a game. Under gamescope (Steam Deck Gaming Mode) the last window wins anyway. | S (X11), not possible on Wayland |
| `library/disk_space.dart` | `GetDiskFreeSpaceExW` | `statvfs` through libc FFI, or `df --output` | S |
| `profiles/portable_temp.dart` | Sets TMP/TEMP through FFI so temp files stay in `userdata\app\temp` | `setenv("TMPDIR")` through libc, before anything starts | S |
| `emulators/bios_links.dart` | `CreateHardLinkW`; it already copies where that fails | `link()` through libc, or `ln`. A hard link fails across file systems, and the copy already covers that. | S |
| `sigil/` | `sigil.dll` beside the exe; layouts pinned to MSVC x64 | See [sigil](#sigil). | S–M |

#### Processes and files

| Place | Windows | Linux | Size |
|---|---|---|---|
| `emulators/folder_link.dart` | Junctions through `io.Link`; a test link first; FAT32/exFAT refused | `io.Link` already makes a symlink, and no rights are needed. FAT32/exFAT has no symlinks there either, so the same check applies. For most emulators, `XDG_*` variables per launch may replace the link (see [2. Emulators](#2-emulators)). | S |
| `emulators/close_process.dart` | `taskkill`, then `taskkill /F /T` after 10 s | SIGTERM, then SIGKILL to the process group after 10 s. Start the emulator in its own group. | S |
| `library/rom_preparer.dart`, `library/xbox_disc.dart` | `System32\tar.exe` (bsdtar) unpacks zips and streams an `.iso` out (`tar -xOf`) | GNU tar doesn't read zip. Use `bsdtar` (libarchive-tools, not always installed), `unzip -p`, or Dart's `archive` streaming (slower; the reason `tar.exe` was chosen). Bundling a static `bsdtar` is the safe option. | M |
| `core/extraction/extraction_service.dart` | `tar.exe`, `thirdparty/7zr.exe` | It already has Linux branches (`unzip`, `tar`, `chmod`). The `.7z` downloads need `7zz` (7-Zip's own Linux build), bundled like `7zr.exe`. | S |
| `library/storage_usage.dart` | Sizes; never follows junctions | `sizeOf` already never follows links; check it with symlinks | S |
| `emulators/ps3_firmware.dart` | `powershell.exe` UI Automation presses RPCS3's Yes during `--installfw` | Not known yet whether RPCS3 asks on Linux. Options: `xdotool` (X11 only), or install the PUP another way. Verify first. | M–L, unknown |
| `ui/screens/game/game_cover_column.dart` (`explorer.exe`), `providers/about_providers.dart` (`cmd /c start`) | Open a folder, open a web link | `xdg-open`. The openers are already providers. | S |
| `windows/updater/`, `update/update_installer.dart` | `GargosyUpdate.exe` (Win32 C++) replaces the listed app files after Gargosy exits | Linux can replace a running binary, so a short shell script, or Gargosy itself before it restarts, can do the same file list with the same rollback. Releases on GitHub need a Linux asset, and `UpdateVersion` must choose by OS. | M |
| `tool/make_release.ps1`, `make_dev_release.ps1`, `tool/build_sigil.ps1` | PowerShell, MSVC | A bash (or cross-platform `pwsh`) script: `flutter build linux`, `libsigil.so`, `app-files.txt`, a `.tar.gz` | M |

#### sigil

- argosy-sigil's own CI builds and tests on `ubuntu-latest`,
  `ubuntu-24.04-arm` and macOS, so a `libsigil.so` is supported upstream.
  `windows/sigil.cmake` needs a Linux twin (`linux/CMakeLists.txt`).
- **The layouts should hold on x86-64 and arm64 Linux.** `sigil.h` uses
  fixed-size integers, `size_t`, `bool`, `char[]` and enums. It has no
  `long` and no `wchar_t`, so LP64 (Linux) and LLP64 (Windows) don't differ
  here. `sigil_bindings_test.dart` would show any difference, so it should
  run in the Linux CI job.
- `sigil_library.dart` looks for `sigil.dll` beside `Gargosy.exe`. On Linux
  it should look for `lib/libsigil.so` in the bundle.
- The `/Od` workaround for `card_ps2.c` is MSVC's alone. GCC needs a check
  that the PS2 card read-back passes; the existing tests do that.

#### Plugins and packages

- Ready for Linux: `window_manager`, `path_provider`, `shared_preferences`,
  `file_picker`, `package_info_plus`, `cached_network_image`, `flutter_svg`.
- `gamepads`: its Linux part reads the joystick devices. It is used through
  the patched `third_party/gamepads_windows`, so the Linux build would use
  upstream `gamepads_linux` (the crash on exit that the patch fixes is
  Windows-only).
- `zstandard` (save formats): check that its Linux part builds.

### 2. Emulators

Gargosy installs each emulator into `emulators/<id>/` and points it at the
profile for each launch. On Linux the same model works only with an AppImage
or a plain archive.

**Flatpak and the distro packages don't fit:**
- A Flatpak runs in a sandbox that can't see `roms/` or the profile without
  `flatpak override --filesystem`.
- A Flatpak puts its own `XDG_*` folders under `~/.var/app`.
- Neither kind sits in the Gargosy folder.

**`XDG_*` variables replace most of the Windows tricks.** Most Linux builds
read `XDG_CONFIG_HOME` / `XDG_DATA_HOME`. Setting them to the profile's
folder for one launch (`ProfileLaunchConfig.environment` already exists for
RPCS3) points the emulator at the profile without a link or a swapped
settings file.

| Emulator | Windows today | Linux build | Pointing on Linux | Size |
|---|---|---|---|---|
| RetroArch | Its own cfg (`--config`) | AppImage (official) | Same `--config` | S |
| Dolphin | `--user=` | Flatpak official; no official AppImage | `--user=` works; needs an AppImage source (community) or Flatpak with overrides | M |
| PCSX2 | `-datapath` | AppImage (official) | Same | S |
| DuckStation | Settings swapped in, `portable.txt` | AppImage (official) | `XDG_DATA_HOME` (verify), else the swap | S–M |
| PPSSPP | `installed.txt` | AppImage / Flatpak | `XDG_CONFIG_HOME` (memstick under it) | S |
| mGBA | Settings swapped, `-C` paths | AppImage (official) | `XDG_CONFIG_HOME` plus the same `-C` | S |
| Flycast | `emu.cfg` swapped, `-config` | AppImage (official) | `XDG_CONFIG_HOME` / `XDG_DATA_HOME` plus `-config` | S |
| MAME | Arguments (`-inipath` …) | Distro, or a self-built binary; no official Linux download | Same arguments; no download source for the installer | M |
| Xenia Canary | Arguments | No usable Linux build | Not supported (Wine/Proton only) | — |
| ares | `--settings-file`, `--setting` paths ending in `\` | Linux builds exist (Flatpak, check for an official AppImage) | Same arguments, with `/` | S–M |
| xemu | Its own `-config_path` | AppImage (official) | Same | S |
| Ryujinx (Ryubing) | `-r` | Linux archive / AppImage | Same `-r` | S |
| Eden | Junction `user/` | AppImage | `XDG_*` or a symlink | S |
| Azahar | Junction `user/` | AppImage, Flatpak | `XDG_*` or a symlink | S |
| Cemu | Junction `portable/`, `-m` | AppImage (official) | `XDG_*` plus `-m` | S |
| melonDS | Junction `portable/` | AppImage, Flatpak | `XDG_*` or a symlink | S |
| RPCS3 | `RPCS3_CONFIG_DIR` | AppImage (official) | Same variable; the firmware install is open (see above) | S, plus the firmware |
| ScummVM | `--config`, `--savepath` | Flatpak, Snap, distro; no AppImage from ScummVM | Same arguments; needs a download source | M |

Changes across all of them:
- **Download sources per OS:** `emulator_registry_data.dart` has Windows
  assets (`windows_url`, `*_asset_required_windows`). Each needs a Linux
  asset rule. M overall.
- **Executables:** strategies look for `*.exe`. An AppImage needs the
  executable bit and a different exe name.
- **Saves:** the save strategies mostly read folders under the profile's
  data. Check each one's Linux layout, above all the ones patched for
  profiles (`ProfileRootedDirectories`).
- **Paths with `\`:** a few launch configs write `\` (ares' paths). Use
  `p.join` and the profile's style.
- **`docs/emulator-profiles.md`** needs a Linux column. The test
  `profile_state_dirs_test.dart` should run for both.

Emulators total: **L.**

### 3. Portable layout

- **The rules hold** if Gargosy ships as a folder (a `.tar.gz` holding
  `gargosy`, `lib/`, `data/` and the user's folders), unpacked somewhere the
  user can write, such as `~/Games/Gargosy`. `AppRoot` finds the folder from
  the executable, as on Windows.
- **An AppImage of Gargosy breaks it.** It runs from a read-only mount in
  `/tmp`, so the root would have to come from `$APPIMAGE`'s folder. That
  works, but every update replaces one large file and the user's folders
  sit loose beside it. Not recommended.
- `path_provider` and `shared_preferences` are already pointed into
  `userdata/`, and nothing uses `~/.local/share`. `TMPDIR` must be set
  instead of TMP/TEMP.
- **Credentials:** the file stays per PC (`login.<PC>…`), with a different
  protector behind it (see `dpapi.dart` above). The PC name comes from
  `/etc/machine-id` instead of the Windows MachineGuid.
- **`PathGuard` must compare case-sensitively on Linux.** Today
  `path_guard.dart` lowercases both sides, which is right on Windows. On
  Linux, `roms/` and `ROMS/` are different folders, and the lowercased check
  would let a server path write into the wrong one. 19 files in `library/`,
  `emulators/` and `profiles/` lowercase paths for matching. Each needs a
  look; most only match ROM or BIOS file names, which may stay
  case-insensitive. S for the guard, M for the review.

### 4. `PlatformInfo` as the seam

`PlatformInfo` only answers "which OS" and holds the environment. It isn't
enough: with it alone, every service grows `if (isLinux)` branches.

Several services already have their own seam:
- `DataProtector`
- `BackgroundPads`
- `LinkMaker`
- `externalOpenerProvider` / `folderOpenerProvider`
- `closeProcess`
- `ProfileLaunchConfig.environment`

What's missing is one interface for each OS concern, chosen once in
`main.dart` (or a provider) by `PlatformInfo`:

| Interface | Today | Notes |
|---|---|---|
| `SecretStore` (rename of `DataProtector`) | DPAPI | Linux: libsecret or key file |
| `ProcessCloser` | `closeProcess` (`taskkill`) | Linux: signals |
| `Unpacker` | `tar.exe` in `RomPreparer`, `XisoWriter`, extraction | One place that lists, unpacks and streams a zip |
| `DiskInfo` | `windowsFreeSpace`, `windowsDiskUsage` | |
| `BackgroundPads` | XInput + HID | Linux: evdev |
| `WindowFocus` | `WindowService.bringToFront` | |
| `AppUpdater` | `UpdateInstaller` + `GargosyUpdate.exe` | |
| `ExternalOpener` | exists | Linux: `xdg-open` |

Each is small and makes the Windows code easier to test (fakes instead of
`kernel32`). They are the follow-ups worth doing even without Linux.

### 5. CI

- An `ubuntu-latest` job running `flutter analyze` and `flutter test` needs
  `libsigil.so` built first (CMake, as `build_sigil.ps1` does).
- **31 of the 291 test files use `C:\` paths.** Most pass
  `PlatformInfo('windows')` and join Windows paths, and with
  `package:path` on Linux these break. Each needs `p.windows` used
  explicitly, or the test kept to Windows (`@TestOn('windows')`). M.
- Tests that call `kernel32` (hard links, disk space) already fall back, or
  need the seams above.
- `tool/test_updater.ps1` stays Windows-only until there's a Linux updater.

## Follow-up issues (proposed, not filed)

These are worth doing on Windows alone:
1. **OS seams**, one issue each, all S: `SecretStore`, `ProcessCloser`,
   `Unpacker`, `DiskInfo`, `WindowFocus`, `AppUpdater`.
2. **`PathGuard` on a case-sensitive file system** (S), with the
   lowercase review (M). Only urgent for Linux.
3. **Linux CI job** for analyze and tests, with `libsigil.so` and the 31
   test files fixed (M).

**A Linux milestone, only if a Steam Deck or Linux build is wanted:** the
seams' Linux sides, the emulators table (L), the release and updater (M),
the evdev quit buttons (M), and the RPCS3 firmware question.
