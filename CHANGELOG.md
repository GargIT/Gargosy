# Changelog

What changed in each release of Gargosy. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- RetroArch's saves for PlayStation, PlayStation 2 (LRPS2), N64, Game Boy
  and Game Boy Color now sync through argosy-sigil, as the standalone
  emulators' do: one save per game in RomM's `autosave` slot, named for
  the core, so RomM's player and Argosy see the same save, and a game's save
  on a shared PS2 card travels without the other games' (#7). Other systems
  in RetroArch sync as before.
- Gargosy keeps a log in `userdata\app\logs`, one file per start (the
  newest 10 are kept, each at most 5 MB). Logins, tokens, passwords and API
  keys are left out. About → Open log folder; attach the newest log to a bug
  report (#1).

- About (user menu, and Settings → About): Gargosy's and the RomM server's
  version, and the documents that come with Gargosy.
- A reader for those documents — what's new, read me, licences, security
  policy — inside Gargosy, scrolled with the D-pad; X lists a document's links.
- A zipped game is unpacked the first time it's played in an emulator that
  can't open zips (xemu, PCSX2, Dolphin, DuckStation, …), with the progress
  under the Play button. Arcade sets and emulators that read zips keep the zip.
- Original Xbox discs in the Redump form are made XISO, which xemu needs: the
  video partition is left out while unpacking, so it takes no extra room.

### Changed

- Settings and the user menu look and work like RomM v2's profile page and
  user menu: sections in groups (Profile, Library, This PC, Gargosy), settings
  in cards, and the menu opens Settings on the section you pick. The menu
  also has the changelog, and Switch profile sits at the bottom.
- Save states on RomM are one switch, "Sync save states with RomM", for every
  emulator that can sync them, instead of one per emulator. A profile that had
  it on for any emulator keeps it on.

### Fixed

- Dolphin can be downloaded again: its download page now turns programs away,
  so Gargosy reads the update API Dolphin's own updater uses.
- DuckStation's download is its portable zip, not the installer.
- When GitHub's hourly limit for programs is used up, emulator downloads and
  updates still get the latest release, never a preview or nightly build.
- Emulator downloads show their progress while they run, instead of
  "Downloading 0 %" until done.
- A PS2 save from RomM goes back onto a memory card file again: the check
  after writing the card failed every time ("I/O error"), because of how the
  save engine was compiled.
- Emulators that come as a zip (PPSSPP, xemu, ares, DuckStation) unpacked
  only their first file, so they never counted as installed.
- xemu finds its hard disk: the first launch in a profile copies
  `bios\xbox_hdd.qcow2` (from RomM's firmware) into the profile, where its
  saves live, and points xemu at the boot and flash ROMs in `bios\`.
- A game in a folder starts with its disc file, not the folder: xemu was
  given the folder of an Xbox game and couldn't load it (the same for other
  platforms Gargosy has no file list for).
- MAME games start: MAME is given the game's set name and its folder
  (`-rompath`), not the zip's path, which made it close at once.

## [0.1.0] - 2026-10-10

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
- The user menu (Start) shows Gargosy's version beside the profile name.

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
