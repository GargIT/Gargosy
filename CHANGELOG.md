# Changelog

What changed in each release of Gargosy. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Saves other players shared on RomM: the play screen and the game's Saves
  tab list them under From other players, by player. Play with one, or put it
  on this PC (X on the Saves tab): it becomes your save, and your next one
  goes to RomM under you. Their save on RomM stays as it is. They are never
  picked for you, and asked about before they replace your own save.
- The same for save states others shared: the States list shows them under
  From other players. Resuming one starts from a copy; in RetroArch, ares and
  Flycast, which load a state by slot, the copy goes into a free slot of
  yours, so none of your states is replaced.
- Share your own saves and states from Gargosy: on the game's Saves tab, Y
  on one of yours on RomM shares it with the other players there (it gets a
  teal "shared" tag), and Y again stops. Uploads stay private until you do.
- Delete this PC's save from the game's Saves tab (hold A, or click it): it's
  backed up first, and RomM's copy stays and comes back the next time you
  play. A save on a memory card other games share, or one Gargosy reads
  through sigil (PlayStation, GameCube, PSP, Dreamcast, Game Boy, N64), is
  refused with why, for now.
- Delete a save state (hold A on the States list, or click it): on this PC
  and on RomM.

- A platform has its own page, as in RomM: its logo and name with its type,
  maker and generation, how many games it has in the library and on this PC,
  its size on RomM and its firmware count, and Random. The games are under
  three tabs (LB/RB):
  - Library: the games. The header goes as you scroll, and the name stays in
    the tab row with the filter and sort bar.
  - Firmware / BIOS: RomM's files for the platform, each On this PC or
    Missing, and Get missing from RomM.
  - Emulator: which installed emulator plays the platform and RetroArch's
    core for it, and the platform's emulators with a way to install the rest.
- A platform's, a collection's and the favourites' games have RomM's filter
  and sort bar: a filter box (it asks RomM, so it finds games not loaded
  yet), Filters (genre, region), On this PC, Sort by and the direction. With
  a controller, A on the filter box opens the on-screen keyboard.
- Sorted by name, a games page has an A–Z rail on its right: click a letter,
  or with a controller go right from the last column, pick a letter with up
  and down, and press A or left to jump to its first game (`#` for digits and
  symbols). X goes straight to the rail, at the focused game's letter. Letters
  without games are greyed.
- A game's versions (regions, revisions) are one card, with how many on its
  cover. Opening it opens the version on this PC, asks which when more than
  one is, and a game's page has Version to switch to another.
- Covers show the game's regions (`USA`, `EUR`, `JPN` …), and still whether
  it's on this PC and a favourite.
- Sort by Size, Players, Length (HowLongToBeat's main story), and your own
  rating, completion and status.
- On this PC shows only the games downloaded here, and works with RomM away.
  It can sort by Downloaded, newest first. On a platform's page, Scan finds
  the platform's games already in `roms\` that the profile hadn't listed
  (another profile's downloads, files put there by hand).

### Changed

- X no longer opens sort and filters on a games page; they're on the bar.

### Fixed

- The on-screen keyboard: the D-pad reaches every row with a controller (it
  stopped at the second).
- A game's size shows on its Details tab (RomM sends it as `fs_size_bytes`).

## [0.2.0] - 2026-10-20

Logging, What's new, Settings and the user menu in RomM's style, updates from
inside the app, save states on RomM for most emulators, saves through
argosy-sigil (RetroArch too), and profiles for the remaining emulators.

### Added

- Settings → Emulators has Open for each installed emulator: it starts on its
  own with this profile's settings, so you can set up controllers (Dolphin's
  Wii Remote, say) in its own menus. A game started from it doesn't sync.
- A RetroArch save state on RomM is labelled with the core that made it
  ("PCSX ReARMed", "Beetle PSX HW"). Your own labels on it are kept.
- The logo on "Who is playing?" is 2.5 times larger.
- Settings → Emulator settings lists the installed emulators in two groups
  under "Sync save states with RomM": synced with RomM, and only on this PC.
  Emulators that sync but can't start in a state say where to load one.
- The play screen's States list shows Azahar's and melonDS's states too, with
  where to load them: those emulators can't start in a state, so A doesn't
  pick one and Resume never chooses it.
- ares' save states sync with RomM when "Save states on RomM" is on, and
  Resume starts a game straight in one (#66).
- melonDS's save states (DS) sync with RomM when "Save states on RomM" is on.
  melonDS can't start in a state, so load it from melonDS's menu (#65).
- Azahar's save states (3DS) sync with RomM when "Save states on RomM" is on.
  Azahar can't start in a state, so load it from Azahar's menu (#64).
- Flycast's save states (Dreamcast) sync with RomM when "Save states on RomM"
  is on, and Resume starts a game straight in one (#63).
- MAME's save states sync with RomM when "Save states on RomM" is on, and
  Resume starts an arcade game straight in one (#62).
- mGBA's save states (GBA, Game Boy, Game Boy Color) sync with RomM when
  "Save states on RomM" is on, and Resume starts a game straight in one (#61).
- Dolphin's save states (GameCube and Wii) sync with RomM when "Save states on
  RomM" is on, and Resume starts a game straight in one (#60).
- PPSSPP's save states sync with RomM when "Save states on RomM" is on, and
  Resume starts a PSP game straight in one (#59).
- Flycast's shared VMU: saves no game is known to own are listed on the
  game page's Saves tab under "Unclaimed saves on the shared VMU". Take one
  for the game and it syncs with that game from then on (#56).
- Home has an Installed games shelf, between Continue playing and Recently
  added: the games on this PC, newest download first. While RomM can't be
  reached it comes first, as On this PC did (#39).
- What's new: the first start of a newer version opens its changes once,
  every release since the last one that ran, also after an update by hand
  (#3).
- RetroArch's saves for PlayStation, PlayStation 2 (LRPS2), N64, Game Boy
  and Game Boy Color now sync through argosy-sigil, as the standalone
  emulators' do: one save per game in RomM's `autosave` slot, named for
  the core, so RomM's player and Argosy see the same save, and a game's save
  on a shared PS2 card travels without the other games' (#7). Other systems
  in RetroArch sync as before.
- Ryujinx (Switch) plays on each profile's own data (`-r`), with the keys
  from RomM's firmware in place, and downloads again: from Ryubing, which
  carries Ryujinx on since its GitHub went away (#9).
- Eden (Switch), Azahar (3DS), Cemu (Wii U) and melonDS (DS) play on each
  profile's own data: their `user\` or `portable\` folder is a link to the
  profile's (#8, #12–#15). Keys from RomM's firmware go into place, and
  melonDS's saves stay out of `roms\`. Wii U updates and DLC are installed
  per profile.
- Gargosy keeps a log in `userdata\app\logs`, one file per start (the
  newest 10 are kept, each at most 5 MB). Logins, tokens, passwords and API
  keys are left out. About → Open log folder; attach the newest log to a bug
  report (#1).
- RPCS3 (PS3) plays on each profile's own data and saves, through
  `RPCS3_CONFIG_DIR`. The firmware is shared: Settings → Emulators installs
  RomM's `PS3UPDAT.PUP` once for every profile (#10). Updates and DLC are
  per profile.

- About (user menu, and Settings → About): Gargosy's and the RomM server's
  version, and the documents that come with Gargosy.
- A reader for those documents — what's new, read me, licences, security
  policy — inside Gargosy, scrolled with the D-pad; X lists a document's links.
- A zipped game is unpacked the first time it's played in an emulator that
  can't open zips (xemu, PCSX2, Dolphin, DuckStation, …), with the progress
  under the Play button. Arcade sets and emulators that read zips keep the zip.
- Original Xbox discs in the Redump form are made XISO, which xemu needs: the
  video partition is left out while unpacking, so it takes no extra room.
- Gargosy updates itself (#16): it checks GitHub at start, shows a dot on the
  avatar when a new version is out, and About → Update now downloads it,
  checks it, and swaps the app files with the new `GargosyUpdate.exe`. Your
  games, emulators, BIOS files and `userdata\` are never touched. The channel
  is *Latest* (releases) or *Preview* (the rolling preview too). Coming from
  0.1.0, update by hand once.
- ScummVM can play games: download it (or import one) in Settings →
  Emulators, and each profile keeps its own settings, saves, screenshots and
  log in its folder. Each game's saves sit in their own folder and sync with
  RomM like other emulators' (#11).

### Changed

- "Save states on RomM" (Settings → Emulator settings) is on by default. A
  profile where it was turned off keeps it off.
- Gargosy doesn't start without `sigil.dll`, which syncs the saves: it says
  so and to unpack the Gargosy zip again. Before, saves quietly went through
  older code that could store them differently on RomM (#57).
- On a drive that can't hold folder links (FAT32, exFAT), starting Eden,
  Azahar, Cemu or melonDS is refused before anything is moved: the
  emulator's own `user\` or `portable\` folder stays where it was (#49).
- Ryujinx can't be downloaded from Gargosy for now: Ryubing's server
  doesn't answer. Settings → Emulators says so; a Ryujinx imported from a
  folder still plays (#9).
- Save states never travel inside a game's save any more (Dolphin, PPSSPP,
  RetroArch): they go to RomM only through "Sync save states" (#30).
  Dolphin's and PPSSPP's states stay on this PC until those emulators get
  state sync of their own. A state in an older save on RomM is put back
  only when this PC has none of that name.
- Settings and the user menu look and work like RomM v2's profile page and
  user menu: sections in groups (Profile, Library, This PC, Gargosy), settings
  in cards, and the menu opens Settings on the section you pick. The menu
  also has the changelog, and Switch profile sits at the bottom.
- Save states on RomM are one switch, "Sync save states with RomM", for every
  emulator that can sync them, instead of one per emulator. A profile that had
  it on for any emulator keeps it on.
- A profile's list of save backups is `backups\index.json`, a readable file
  beside the backups, instead of a Hive database in the profile's own folder.
  Gargosy no longer uses Hive. The old list isn't moved, so a profile from
  0.1.0 starts with an empty backup list: its zips stay in `backups\`, and
  saves that were waiting to upload aren't retried.

### Fixed

- "Always for this game" was saved, but the play screen opened again from
  the game page showed it unticked, with the platform's emulator: it read
  the menu the game page held from before. It now opens on the remembered
  emulator and core.
- "Always for this game" on the play screen is kept when another emulator
  is picked after ticking it (it unticked itself), and when the game
  starts with Resume (only Play saved it). Unticked, it forgets the
  game's remembered emulator.
- Gargosy no longer crashes when it closes (an error in the controller
  plugin, `gamepads_windows_plugin.dll`).
- Resume starts a RetroArch state in the core it was made with (PCSX ReARMed,
  say), not the platform's default core.
- RetroArch's Auto save state slot is in the States list and Resume starts
  in it: Gargosy turns on RetroArch's "Auto Load State" for that launch only,
  and keeps it off for every other launch.
- Resume in DuckStation no longer warns that it can't open the CD image when
  the state was made on another PC, or with the ROMs in another folder:
  DuckStation starts a copy of the state that names this PC's ROM. The synced
  state is never changed.
- RomM's save states show on the play screen in a profile that hasn't started
  that emulator yet (a new PC or profile): the emulator's folders are made
  before the states are listed, as its first launch would.
- Save states on a new profile: DuckStation's are read from the profile's
  own folder from the first launch on, and RetroArch's state folder is set
  before its first run, so a state from RomM lands where the emulator looks.
- Cemu (Wii U) opens an encrypted disc image (`.wux`, `.wud`) whose key
  sits beside it as `<name>.key`, as Redump sets have it: Gargosy adds the key
  to the profile's `keys.txt` before the game starts. Before, Cemu asked for
  the key.
- Azahar (3DS) syncs saves when RomM doesn't know the game's title id:
  Gargosy reads it from the ROM. Before, no 3DS save was found to upload.
- Downloading a game of several files (RomM sends them as one zip) works
  again: it failed with "object is unsendable" when the zip was unpacked.
- A zipped game that was unpacked already, but whose zip stayed beside it,
  plays from its folder again: Gargosy unpacked it all over each time, then
  refused because the folder was in the way. The leftover zip goes.
- A game's Saves count counts each save once: the same save on this PC,
  on RomM and in a backup is 1, not 3. A backup's name now carries RomM's
  hash of the save, so it's known as the same save.
- Eden downloads again: its nightly builds no longer carry files, so Gargosy
  takes Eden's latest release (the x64 Windows build).
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

[Unreleased]: https://github.com/GargIT/Gargosy/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.2.0
[0.1.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.1.0
