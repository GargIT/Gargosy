# Changelog

What changed in each release of Gargosy. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.6.0] - 2026-10-31

Start a game from a desktop shortcut or Steam, an age limit per profile,
the achievements earned in a session, and Gargosy in Swedish.

### Added

- Start a game from outside Gargosy: `Gargosy.exe --play=<rom id>`, with
  `--profile=<profile id>` to name the profile (with several profiles and
  none named, Gargosy asks who is playing). The profile opens (its PIN
  asked), the game starts with its newest save, and Gargosy closes once its
  saves are synced, so a desktop shortcut or a non-Steam game in Steam
  starts and ends with the game. A save that didn't reach RomM is said
  first. `--play-stay` keeps Gargosy open. With Gargosy already open, the
  shortcut brings it to the front and plays the game there (switching
  profile first when another is named), and it stays open after; a second
  Gargosy never starts.
- An age limit per profile: Settings → Profile → Age limit (Off, up to 3,
  7, 12, 16 or 18, by PEGI's ages; ESRB, CERO, USK and the others are read
  as ages too), and Hide unrated games. Games above it are hidden from
  the galleries, Search, collections, Home's rows and the screensaver, and
  don't start, and an emulator can't be opened on its own.
  Changing it asks for a parent's PIN (another profile without a limit).
- Create desktop shortcut in a game's ⋯ menu: a shortcut with the game's
  cover as its icon that starts it in your profile (`--play`). It never
  replaces a file on the desktop.
- After a game, Gargosy says which RetroAchievements you earned in it:
  "2 achievements earned · 15 points (hardcore)", once RomM has read them,
  and the game's Achievements tab shows them.
- Gargosy in Swedish: Settings → Display → Language (System, English,
  Svenska). System follows Windows. Dates and decimals follow the language;
  names and descriptions from RomM stay as RomM has them. The on-screen
  keyboard has å, ä and ö.
- Save a gallery as a smart collection: in Filters, Save as smart
  collection keeps its platform or collection, search, genres, regions and
  sort on RomM, asks a name and who sees it, and opens it. Your own smart
  collections can be renamed, shared and deleted from ⋯ on their page.

### Fixed

- A smart collection's page said its filters as RomM's raw JSON; now in
  words (Search “girl” · Sorted by Name, A–Z).
- A zipped Xbox game whose disc ends in `.ISO` in capitals now plays in
  xemu; it failed with "Couldn't unpack" after unpacking the whole disc.
- "Couldn't unpack" no longer ends in nothing when the unpacker gives no
  reason; it says the code it stopped with.

## [0.5.0] - 2026-10-27

Playing now on Home, a game's Overview and Achievements as RomM's, Home's
rows fitted to the window, and quitting a game with any controller.

### Added

- Home starts with Playing now: who plays what on RomM right now, with
  the game's cover and the player's avatar, where and for how long, read
  again every 30 seconds. A opens the game. Other players' saves show
  their avatar too.
- Home's rows show only the games that fit the window, with See all in
  the last place; nothing scrolls sideways.
- In a wide window (1600 px and up) Random pick and On this day stand
  beside the game played last; Your library is a slim strip under them.
- A game's Overview, in RomM's order: the description, then its facts
  (last played and for how long, how many play, age ratings as their
  boards' icons) and How long to beat's times, screenshots, and similar
  games in your library.
- Quitting a game works with controllers SDL's controller list doesn't
  know: Gargosy guesses the usual button layout, and Settings → Controller
  → Controllers taught lets you press each quit button once to teach it.

### Changed

- The Achievements tab looks like RomM's: each achievement's badge, a
  summary (earned, points, progression and missable), filters by type and
  by earned or locked, the type as a coloured tag, and the list in up to
  four columns on a wide screen.

### Fixed

- A game's status, rating and completion, changed on its page, are kept
  on RomM 5.4: before, RomM took the change without saving it.
- A controller that isn't XInput (a DualSense, a Switch Pro controller, an
  8BitDo in D mode), connected or woken during a game, can now quit that
  game; before, it worked only from the next game.

## [0.4.0] - 2026-10-26

Home after RomM's v2 Home, a download queue with a Downloads page, adding
games to collections, Storage, play time, a screensaver, quitting a game
with the controller (and a save state kept on close), and this PC as a
device on RomM.

### Added

- Gargosy registers this PC as a device on RomM ("Gargosy on <PC name>") the
  first time a profile opens, so RomM knows which PC your saves and play
  sessions came from and shows what you're playing now.
- Closing a game in RetroArch, DuckStation or PCSX2 (the quit buttons too)
  keeps a save state of where you were: RetroArch's auto state, DuckStation's
  and PCSX2's resume state. It syncs to RomM like your other states, and
  Resume starts from it.
- Home is new, after RomM's v2 Home: the game you played last at the top, over
  its art, with Resume when it has a save state (a random pick until you've
  played something); three small widgets (a random pick, games released on
  this day, your library in numbers); then rows: Continue playing, Recently
  added, Favourites, On this PC, Platforms and Collections, each with See all.
  While RomM is offline it shows what's on this PC.
- Customize Home, at the end of Home and in Settings → Home: what's at the top,
  which widgets show, and which rows show in what order, each profile its own.
  For you (RomM 5.4's recommendations), Smart collections and Virtual
  collections are there to turn on.
- Quit a game with the controller: hold Select (View), LB and RB together for
  a second while a game runs, and Gargosy closes the emulator the way its
  close button does, so it saves first, then syncs as usual, and comes back
  in front. It works in every emulator and with most controllers (Xbox ones,
  a DualSense or DualShock, a Switch Pro controller, an 8BitDo in any mode);
  Settings → Controller picks other buttons (Select + Start, or both sticks
  pressed in) or turns it off.
- A download checks the free space first: when the drive hasn't room for the
  game (and, for a game that comes as a zip, its unpacked copy), it doesn't
  start and says how much it needs and how much is free. The game page shows
  the free space under Download when it's tight. Unpacking a zip for an
  emulator checks the same.
- Downloads go in a queue: one at a time, in the order you pressed Download,
  the others "Queued" on their game page. A Downloads page in the user menu
  (while there are any) shows the running one with its speed and time left,
  the queue (Y puts one first, X takes one out or stops the running one),
  the ones that failed (A tries again) and the ones done. A game that won't
  fit with the downloads queued before it isn't queued. Switching profile
  asks first while downloads are waiting.
- Add a game to your collections from its page: ⋯ → Add to collection… lists
  your own, with a ✓ on those it's in, and New collection… makes one (only
  yours, or shared) with the game in it. On your own collection's page, ⋯
  renames it, shares it or stops sharing it, and deletes it.
- Settings → Storage shows what takes space on this PC: the drive, then
  ROMs, emulators, BIOS, the profiles' data, the image cache and Temp. ROMs
  are listed by platform, largest first; open one to see its games by size
  and when they were last played, and delete one or several (X marks them)
  from this PC. Only the ROM files go; the saves stay. Temp can be emptied.
  The image cache's settings moved here.
- Play time: every game you play is sent to RomM 5.4's play sessions, and
  a game's page says how long you've played it, on every device ("Played
  12 h 40 min · 8 sessions"); Home's header too. A session RomM didn't take
  goes after the next game, and on an older RomM the time is this PC's.
- A screensaver: left untouched on Home or a tab for 5 minutes, Gargosy
  shows the library a game at a time over its art, each drifting across a
  different part of the screen. Any button puts you back
  where you were; A opens the game shown. Settings → Display sets the wait
  (2, 5, 10 or 30 minutes) or turns it off.

### Changed

- Progress bars are easier to see: a bright fill on a dark track, thicker.

## [0.3.0] - 2026-10-24

A page for each platform and collection, the Collections tab, Search like
RomM's with recent searches, the A–Z rail, a game's versions on one card,
saves and states other players shared, deleting saves and states (and, for
RomM's admins and editors, games), and DSi games in RetroArch.

### Added

- The Collections tab is new, after RomM's: your collections and the ones
  other players share, in a panel with Favourites first, then RomM's
  virtual collections (series, franchise, genre, play mode, company) by
  type. Smart collections are there too. Each shows a mosaic of its covers
  with marks for smart, shared, another player's, and how many of its
  games are on this PC. Filter them by name, Kind (Collections, Smart,
  Virtual) and whose (Mine, Others'), and sort by name, games or recently
  updated. Y on one opens a random game of it.
- A collection has its own page, like a platform's: its covers and name,
  what kind it is (a smart one's filters, a virtual one's type), whether
  it's shared and whose it is, its games and how many are on this PC, and
  Random. The header goes as you scroll, and the name stays above the bar.
  It counts the platforms its games are on, and Platform on its bar shows
  the games of one of them.
- Search looks like a collection's page: before you type it shows your whole
  library by name, with the A–Z rail; a large box at the top, with how many
  games match, how many are on this PC and on how many platforms; and the
  same bar, with Filters, Platform, On this PC and Sort by. Typing sorts by
  Best match, RomM's own search order, unless you picked another sort. The
  header goes as you scroll, and the box moves onto the bar.
- In Filters, X applies and Y clears, wherever the focus is; the two buttons
  show them when you play with a controller.
- Search remembers your recent searches, each profile its own: they show under
  the box, A runs one again and holding A (or its × with a mouse) forgets it.
  A search is remembered when you press Enter or Done, or open a game from it.
- B on a search or filter box clears it, like its ×; on an empty box B goes
  back as before.
- A RomM admin or editor can delete a game from RomM: the game page's ⋯ →
  Delete from RomM…. The prompt says it's permanent and that everyone's saves
  and states of it on RomM go too; it can also delete the file on the server
  and the copy on this PC (both ticked), and Delete has to be held.
- Settings → Profile → RomM account → Sign in again: signs the profile in
  again as the same RomM user. A profile made before this version needs it
  once to delete games.
- When the filters hide every game, a gallery says which ones (On this PC, a
  platform, genres, regions) and how many games RomM has, with Show all to
  clear them.
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
  play. On a PlayStation memory card or in PSP's save folder, only that
  game's save comes off; the other games' stay, and the card as it was is
  kept in the profile's `backups\deleted\` first. A GameCube card or a
  Dreamcast VMU is refused with why, for now.
- Delete a save state (hold A on the States list, or click it): on this PC
  and on RomM.
- A DSiWare game's Details tab says so, and which regions' DSi NAND it needs.
  Put one NAND per region in `bios\` under any name: melonDS DS picks the
  one that matches the game.

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

- The back button on a mouse works like Escape: it closes what is open,
  else goes back a page.

- Covers load faster and more of them stay on this PC: grids and shelves
  use RomM's small covers (a game's page keeps the large one), and the
  image cache keeps 10 000 by default instead of 1 000. Settings → Image
  cache sets how many (2 000 to 50 000), shows what it takes, and clears
  it. The cache moved to `userdata\app\cache\images\`; the old one in
  `userdata\app\temp\` is removed at the first start.

- X no longer opens sort and filters on a games page; they're on the bar.
- The A–Z rail lights the letter you're at as you scroll: the focused game's,
  else that of the first game shown.
- A DSiWare game isn't offered in standalone melonDS any more, which starts
  it but can't save it; it plays in RetroArch's melonDS DS. With only
  melonDS installed, the play screen says why.
- DSi games play in RetroArch's melonDS DS core, the only one that runs
  them (DSiWare included); the DS cores aren't offered for them. Its DSi
  BIOS, firmware and a NAND of the game's region are needed.

### Fixed

- The on-screen keyboard: the D-pad reaches every row with a controller (it
  stopped at the second).
- A game's size shows on its Details tab (RomM sends it as `fs_size_bytes`).
- A DSiWare game's save in RetroArch (`<game>.public.sav`, and its
  `.private.sav` and `.banner.sav`) syncs whole and comes back under its own
  name; it was put back as `.srm`, which the game never reads.
- A DSi NAND in `bios\` is no longer changed by playing: each profile gets
  its own copy (melonDS DS writes into the NAND it plays on), where it was a
  link to the shared file.
- A RetroArch core chosen on a platform's page is used for that platform's
  games when RomM names the platform differently (the DSi's, the DS Lite's).

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

[Unreleased]: https://github.com/GargIT/Gargosy/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.6.0
[0.5.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.5.0
[0.4.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.4.0
[0.3.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.3.0
[0.2.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.2.0
[0.1.0]: https://github.com/GargIT/Gargosy/releases/tag/v0.1.0
