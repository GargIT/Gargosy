# Changelog

What changed in each release of Gargosy. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - Unreleased

The first release: a RomM client for Windows in the look of RomM's v2 web UI,
played with a controller, portable, with a profile per player.

### Profiles

- "Who is playing?" at start: each player has a profile with their own RomM
  account, saves, states and emulator settings.
- Add a profile by pairing with a phone (a code and QR) or with username and
  password; the password is exchanged for a token and never stored.
- An optional four-digit PIN per profile (a family lock, not security).
- Logins are encrypted for this PC's Windows user; on another PC a profile
  logs in again once.

### Library

- Home with a random pick, Continue playing, Recently added and Favourites.
- Platforms as cover-strip cards with RomM's own logos, and a Covers setting:
  top rated, random, recently added, last played or logo only.
- Collections (favourites first) and Search.
- Galleries with paging, sort and filters.
- A game page after RomM's: art, cover, status, rating and completion written
  to RomM, and tabs for Overview, Saves, Achievements, Notes and Details.
- Covers and logos are cached on disk, also from servers with a self-signed
  certificate the profile trusts.

### Playing

- Download a game, then Play. ROMs go to `roms\<platform>\` and nothing else
  is written there.
- The play screen picks the save or state and the emulator a game starts
  with, and remembers it for the game if you want; a Full screen switch per
  emulator.
- Emulators run on the profile's own data folder: Dolphin, PCSX2, RetroArch,
  MAME, Xenia Canary, ares, xemu, PPSSPP, DuckStation, mGBA and Flycast.
- Emulators screen: download an emulator, or import an install you already
  have (it's copied, yours isn't changed); updates when a newer version is out.
- A missing RetroArch core is downloaded when a game needs it.
- BIOS files come from RomM and from the shared `bios\` folder.
- RetroAchievements: emulators sign in from the profile's own settings.

### Saves and states

- Saves sync with RomM before a game starts and after it ends; save states
  sync too and can be resumed from the play screen.
- PCSX2, DuckStation, Dolphin (GameCube), PPSSPP, Flycast and mGBA (GB, GBC)
  sync through [argosy-sigil](https://github.com/rommapp/argosy-sigil), the
  library RomM and Argosy use, so their saves match what other RomM clients
  upload.
- Every save of a game in one list: this PC, local backups and RomM. Restore,
  delete, upload or back up from the game page's Saves tab.
- Saves from another emulator are converted where the formats allow.
- The current save is backed up before another one is put in its place.

### Offline

- The games on this PC still play without RomM; saves wait in a per-profile
  upload queue and go up when RomM can be reached again.

### Portable

- Unpack the zip anywhere you can write, a USB stick too. Everything stays in
  that folder: the app, `roms\`, `emulators\`, `bios\` and `userdata\`.
  Nothing goes in AppData.

[Unreleased]: https://github.com/GargIT/Gargosy/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.1.0
