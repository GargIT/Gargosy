# Hand tests for 0.2.0

These are the tests left for a person on the open issues. Everything else is covered by `flutter test` and the probes noted in each issue. Tick a row (`[x]`) once it passes. When every row of an issue is ticked, the issue can be closed. A failure goes in the issue, with the log (Settings → About → Open log folder).

The test install is `C:\Retro\apps\gargosy` (built from `main`). For tests that use two profiles, make two profiles signed in to the same RomM user, unless the row says otherwise.

## Logging (#1)

1. [x] Sign in with a password, pair a device with the QR code, and sign in to RetroAchievements. Open the log in `userdata\app\logs\`, and check that no token, password or API key appears in it.
2. [x] Lines written while a profile is open carry its `[p:…]` tag, and lines from the profile picker carry none.

## RetroArch saves through sigil (#7)

For each system below, play a game in RetroArch through Gargosy, save in-game and quit. Then:

- check that the save is on RomM in the `autosave` slot;
- delete the save on this PC;
- start the game again and check that the save comes back;
- open the game in RomM's web player and check that the save loads there.

3. [x] Game Boy
4. [x] Game Boy Color, a game with a clock (e.g. Pokémon Gold/Silver/Crystal)
5. [x] Nintendo 64
6. [x] PlayStation (PS1)
7. [x] PlayStation 2 with the LRPS2 core

## Folder link on a USB stick (#8)

8. [ ] Copy Gargosy to a FAT32 or exFAT USB stick and start Eden, Azahar, Cemu or melonDS from it. The launch is refused with "A folder link can't be made … The drive may be FAT32 or exFAT", and nothing is written. *Not tested: no FAT32 or exFAT drive at hand; #8 closed without it (2026-10-16).*

## Ryujinx (#9)

9. [ ] Settings → Emulators → Download Ryujinx (from Ryubing). It installs and starts. *On hold: the download is off while Ryubing's server doesn't answer.*
10. [ ] Play a Switch game in profile A and save. Then play it in profile B: B has no save from A. The save is on RomM. Start a game once before a RomM save can be put in place.

## RPCS3 (#10)

11. [x] Play a PS3 game in profile A and save. In profile B the save isn't there. The save is on RomM.
12. [x] While a game runs, nothing in `emulators\rpcs3-firmware\dev_flash` changes (compare the modified dates before and after).

## ScummVM (#11)

13. [x] Play a game downloaded from RomM as a `.scummvm` file, then save and load in-game.
14. [x] Play a game that is a folder, then save and load in-game.
22. [x] Save in a ScummVM game and quit: the save is on RomM. In profile B, the game starts with that save (pulled into `saves\<game>\`). Saves made before this fix sit loose in `saves\` and aren't synced; move them into the game's folder.

## Eden, Azahar, Cemu, melonDS (#12–#15)

For each one: play a real game in profile A and save. Then play it in profile B, which starts without A's save. A's save is on RomM.

15. [x] Eden (Switch) (#12)
16. [x] Azahar (3DS) (#13)
17. [x] Cemu (Wii U) (#14)
18. [x] melonDS (DS) (#15)

## Updates (#16)

These rows need preview releases published on GitHub.

19. [x] Settings → About → Updates: the updater window shows its progress and starts Gargosy again when it's done.
20. [x] On a preview build, About shows the preview version, and its Updates block shows the Preview channel.
21. [x] A real update from preview N to N+1. Afterwards, the profiles, ROMs, emulators and BIOS files are all still there, and What's new (#3) opens once with N+1's changes.

## Unclaimed saves on Flycast's shared VMU (#56)

Flycast with its per-game VMU setting off (`PerGameVmu = no` in the profile's `emu.cfg`), so every game shares one VMU.

23. [ ] Two Dreamcast games save to the shared VMU. A save sigil can't tie to a game shows under "Unclaimed saves on the shared VMU" on the game page's Saves tab. "Take it" uploads it with that game, and the other game's save on the VMU is untouched. In profile B, the claimed save comes down with the game. *Not tested by hand; #56 closed without it (2026-10-19).*

## Save states between profiles (#58)

With "Save states on RomM" on (Settings → Emulator settings) in both profiles. For each: in profile A, play, save a state to a slot and quit. The state is on RomM. In profile B, the state comes down before launch and Resume (Y on the play screen) starts the game in it. Then make a newer state of the same slot in each profile without syncing between them: the next launch says the state differs and keeps this PC's copy.

24. [x] DuckStation (PS1)
25. [x] PCSX2 (PS2)
26. [x] RetroArch, a PS1 game (Beetle PSX HW or PCSX ReARMed)

## PPSSPP save states (#59)

27. [x] With "Save states on RomM" on: in profile A, play a PSP game in PPSSPP, save a state to a slot and quit. The state is on RomM, with its screenshot on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it.

## Dolphin save states (#60)

28. [x] With "Save states on RomM" on: in profile A, play a GameCube game in Dolphin, save a state to a slot (Shift+F1) and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.
29. [x] The same with a Wii game.

## mGBA save states (#61)

30. [x] With "Save states on RomM" on: in profile A, play a GBA game in mGBA, save a state to a slot (Shift+F1) and quit. The state is on RomM, with its picture on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it.
31. [x] The same with a Game Boy (or Game Boy Color) game.

## MAME save states (#62)

32. [x] With "Save states on RomM" on: in profile A, play an arcade game in MAME, save a state (Shift+F6, then a key, e.g. 1; Shift+F7 loads) and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.

## Flycast save states (#63)

33. [x] With "Save states on RomM" on: in profile A, play a Dreamcast game in Flycast, save a state and quit. The state is on RomM, with its picture on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it (Flycast loads the slot at boot). Afterwards, Flycast's own "load state on start" setting is as it was (the Resume setting is for that launch only).

## Azahar save states (#64)

34. [x] With "Save states on RomM" on: in profile A, play a 3DS game in Azahar, save a state to a slot and quit. The state is on RomM. In profile B, the play screen's States list shows it with "load it from Azahar's menu" (A doesn't pick it). Start the game: the state is in Azahar's Load State menu under that slot, and loading it continues where A stopped.

## melonDS save states (#65)

35. [x] With "Save states on RomM" on: in profile A, play a DS game in melonDS, save a state to a slot and quit. The state is on RomM. In profile B, the play screen's States list shows it with "load it from melonDS's menu" (A doesn't pick it). Start the game: the state is in melonDS's Load State menu under that slot, and loading it continues where A stopped.

## ares save states (#66)

36. [x] With "Save states on RomM" on: in profile A, play a game in ares (e.g. N64), save a state to a slot and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.

## sigil required, old save code removed (#57)

37. [x] Rename `sigil.dll` beside `Gargosy.exe` and start Gargosy: it shows "Gargosy can't load sigil.dll" with the path, and doesn't start. Rename it back: Gargosy starts as before.

For 38–40, profile B is a second profile signed in to the **same RomM user** as A: it stands for another PC of the same player. (Another RomM user doesn't see A's saves or states, public or not: #92.)

38. [x] On PCSX2 (PS2), DuckStation (PS1), Dolphin (GameCube), PPSSPP (PSP) and mGBA (Game Boy): in profile A, save in-game and quit; the save is on RomM. In profile B, start the game: it comes down before launch and the game finds it.
39. [x] With "Save states on RomM" on in both profiles, the same with a state on each of them: in profile A, save a state and quit; the state is on RomM. In profile B, Resume starts the game in it.
40. [x] A Wii game in Dolphin and a PS2 game in RetroArch (LRPS2): the save round trip of row 38.

## Platform page: filter and sort bar (#95)

41. [x] On PlayStation 2, type "hack" in the filter box with the keyboard: shortly after typing stops, the .hack games show, also ones beyond the first page. With a controller, A on the box opens the on-screen keyboard and the filter applies when it closes.
42. [x] Turn On this PC on: only this platform's downloaded games show, with their count on the switch. Sort by Downloaded puts the newest download first. With RomM stopped (or the PC offline), the switch still works.
43. [x] Sort by Size, Players, Length and My rating: the order is the expected one, and the direction button turns it round. Games without the value (no HowLongToBeat time, no rating) come last either way.

## Platform page: header and tabs (#95)

44. [x] Open PlayStation 2: the header shows its logo, Console · Sony · Generation 6, In library, On this PC (your downloaded PS2 games), On disk and Firmware. Random opens a PS2 game.
45. [x] Scroll the games: the header goes, the name sits in the tab row, and the filter and sort bar stays. Back at the top, the header returns. With a controller, D-pad up from the first row reaches the bar, then the tabs, then Random.
46. [x] Firmware / BIOS marks what's in `bios\`. Get missing from RomM brings the rest, and they show as On this PC.
47. [x] Emulator: change the emulator (with two installed) or RetroArch's core; Settings → Emulator settings shows the same, and a game without "Always for this game" plays in it. An uninstalled emulator's Install under Emulators opens Settings → Emulators.
48. [x] LB/RB switch tabs. Move to a cover, RB, move in the firmware list, LB: focus is back on that cover; RB: back in the list.

## A–Z rail (#95)

49. [x] On a big platform sorted by Name, click a letter far down (T): the page jumps to the first T game, also when it wasn't loaded yet. `#` jumps to games starting with a digit or symbol; letters without games are greyed.
50. [x] With a controller: D-pad right from the last column reaches the rail, up/down picks a letter (skipping greyed ones), A or left jumps into the grid at it. X from a cover goes to the rail at that game's letter. Sorted by anything else, there's no rail. On this PC, the rail jumps within the downloaded games.

## Cover marks and folded versions (#95)

51. [x] A game with two or more versions on RomM (e.g. USA and Europe) shows as one card with the count top left and its region (`USA`) bottom left; a favourite has the heart and a downloaded one the on-this-PC mark.
52. [x] Open a folded game with none of its versions downloaded: RomM's version opens, and Version on its page lists the others; pick one to go to its page and download it. With one version downloaded, the card opens that one. With two downloaded, it asks "Which version?".
53. [x] Collections and Favourites have the bar, the A–Z rail (by name) and the marks.
54. [x] Put a game's file in `roms\ps2\` by hand, or download one in another profile: it has the ✓ but isn't counted On this PC. On PlayStation 2 with On this PC on, Scan says "Found 1 more on this PC." and the game is listed. Scan isn't there on a collection or with On this PC off.

## Other players' saves (#92)

For these, a second RomM user (player A) on the same server, with a save of a game made public in RomM's web UI. Player B is a Gargosy profile of another RomM user.

55. [x] In B's profile, the game's play screen and Saves tab list A's save under From other players, with A's name. B's own saves come first, and the Saves count doesn't include A's.
56. [x] With a save of B's own on this PC, pick A's save and Play: it asks "Play A's save?" first. The game starts in A's save. After quitting, the save is on RomM under B, and A's save on RomM is unchanged.
57. [x] On the Saves tab, X on A's save puts it on this PC (B's save is backed up first); hold A does nothing on it. A makes the save private again: B no longer sees it.
58. [x] A makes a state public (PCSX2, DuckStation, Dolphin, PPSSPP, mGBA or MAME). In B's profile, the play screen's States list shows it under From other players with A's name; the States count is B's own. Resume it: the game starts in A's state, and B's own states are unchanged.
59. [x] The same with a RetroArch (or ares, Flycast) state: it goes into the first free slot of B's (Slot 1 when B has none), the game starts in it, and after quitting it's B's state in that slot (on RomM under B with state sync on). B's state in A's slot number, if any, is unchanged.
60. [x] In B's profile, on the game's Saves tab, Y on one of B's saves on RomM: it says it's shared and gets the teal "shared" tag. In A's profile (or RomM's web UI as A), B's save shows under From other players / is public. Y again: it stops being shared, and A no longer sees it. The same on the States list for a state of B's on RomM. With the mouse, a click on B's RomM save offers Share on RomM / Stop sharing.

## Delete this PC's saves and states (#94)

61. [x] A GBA game in mGBA (or a SNES game in RetroArch) with a save: on the Saves tab, hold A on its This PC row and confirm. The row goes, a new backup row appears, and the save file is gone from the emulator's save folder. Play again: RomM's save comes back.
62. [x] Two PS2 games in PCSX2 with saves on the same memory card: hold A on one game's This PC row and confirm. Its save folders (`BASLUS-…`) are gone from `memcards\Mcd001.ps2`, the other game's stay and still load in PCSX2, and a copy of the folders is in the profile's `backups\deleted\<time>\`.
63. [x] On the States list: hold A on one of your states (on this PC and RomM) and confirm: it's gone from the list, from the emulator's state folder and from RomM. One only on RomM goes the same way. Another player's state has no delete.
64. [x] A Game Boy game in mGBA (or in RetroArch) with a save: hold A on its This PC row and confirm. The row goes, a backup row appears, the game's `.sav` (RetroArch: `.srm`) is gone and other games' saves stay. Play again: RomM's save comes back without asking about a changed save.
65. [x] Two PS1 games in DuckStation (or RetroArch) on one shared card: hold A on one game's This PC row and confirm. Its save is gone from the card, the other game's still loads, and the whole card as it was is in `backups\deleted\<time>\`.
66. [x] A GameCube game in Dolphin (or a Dreamcast game in Flycast): hold A on its This PC row: it says why it can't be deleted, and nothing changes.

## DSi games in melonDS DS (#114)

67. [x] A DSi platform game (Zuma's Revenge! (USA)): its play screen offers RetroArch with melonDS DS only, chosen already; Play downloads the core the first time, and the game starts.
68. [x] Save in it and quit: `<game>.public.sav` is in the profile's RetroArch `saves\` and on RomM (the Saves tab). Delete it on this PC, play again: RomM's save comes back as `.public.sav` (no new `.public.srm`) and the game has it.
69. [x] On the DSi platform's page, Emulator tab: RetroArch's core is melonDS DS; a DS game still starts in the DS platform's core.
70. [x] Zuma's Revenge! (Europe, Australia) on this PC: its Details tab has a DSiWare row asking for a NAND from Europe or Australia; Zuma's Revenge! (USA) asks for USA.
71. [x] Play a DSi game in RetroArch: the profile's `system\dsi_nand.bin` is its own copy now (`bios\dsi_nand.bin` keeps its date after playing), and the game still starts.
72. [x] With a European NAND in `bios\` under its own name beside `dsi_nand.bin`: Zuma's Revenge! (Europe, Australia) starts, and the USA copy still does.

## A–Z rail: the current letter (#118)

73. [x] A platform's games sorted by name: scroll with the mouse wheel, then with the D-pad. The rail lights the letter you're at and follows; after a jump to T it lights T.

## DSiWare not in standalone melonDS (#119)

74. [x] Zuma's Revenge! (USA): its play screen offers RetroArch (melonDS DS) only, not melonDS, though melonDS is installed. A DSi or DS cartridge game still offers melonDS.
75. [x] A DSiWare game you played in standalone melonDS before (Zuma's Revenge! (Europe, Australia)): its play screen picks RetroArch now, not melonDS, and Play starts it there.

## Collections page (#121)

76. [x] The Collections tab: your collections and the shared ones in the panel, Favourites first; RomM's virtual ones below it by type (Franchise, Genre …). The covers, the smart / shared / player marks and "N on PC" look right.
77. [x] Filter by name, Kind (Smart, Virtual) and Whose (Mine, Others'); Whose is greyed with Virtual; Sort by Games and Recently updated. All of it with the controller.
78. [x] A on a smart and on a virtual collection opens its games; Y on one opens a random game of it.
79. [x] A collection's page: its mosaic, name, kind, Shared / By you (or the owner), description (a smart one's filters), games and on this PC; Random opens one of its games. Scroll: the header goes and the name stays above the bar; up again, it comes back. B goes back to the tab.

## Covers and the image cache (PR #125), the mouse's back button (PR #126)

80. [x] Covers in the gallery, Home shelves and platform cards look sharp enough with RomM's small covers (else revert to the large ones); a game's page still shows the large cover.
81. [x] Settings → Image cache: Keep up to changes (2 000–50 000), On this PC now shows the count and size, Clear the cache empties it and covers load again. `userdata\app\temp\gargosy-images` is gone after the first start; `userdata\app\cache\images` fills instead.
82. [x] The mouse's back button works like Escape: on a game's page it goes back, with a dropdown, the on-screen keyboard or a dialog open it closes that first.

## A collection's platforms (#128)

83. [x] A collection with games on several platforms: the header's PLATFORMS counts them, and Platform on the bar says "All N". Pick one with the controller: only its games show, and the list still offers the others; All brings them all back. On this PC with a platform picked shows that platform's downloaded games of the collection. A collection on one platform has the count but no Platform pick.

## Search like a collection's page (#132)

84. [x] Open Search with the controller: the box has focus, the whole library shows by name with the A–Z rail, and GAMES / ON THIS PC / PLATFORMS count it. A on the box opens the keyboard; a term shows its matches, sorted by Best match, with the counts for the term. Pick Rating, then change the term: Rating stays. Clear the box: the whole library by name again. Platform and On this PC narrow the matches. Scroll down: the header goes and the box is on the bar, still working; at the top the header is back. With a mouse and keyboard, click the box and type: the matches follow as you stop typing.
85. [x] Filters with the controller (any gallery): Apply shows X and Clear filters shows Y. Pick a genre with A, press Y: nothing is picked. Pick one again and press X with the focus on the genre: the sheet closes and the gallery shows that genre (Filters · 1). B closes without applying. With a mouse, no X or Y shows.
86. [x] Recent searches: on Search, type a term and press Enter (or Done on the on-screen keyboard): it shows under the box after RECENT. Type another and open a game from it: that one comes first. A on a recent runs it again; hold A on one forgets it (with a mouse, its ×). Switch profile: the other profile has its own. Restart Gargosy: they're still there.
87. [x] Nothing matches: on Search, type a term with matches, turn On this PC on where none of them is downloaded: the panel says "Nothing matches “term” here.", how many RomM has, and that On this PC hides them. Show all turns it off and shows them. The same with a genre from Filters, and on a platform's page with a region (not the platform itself). A term nothing matches at all shows only the plain line.
88. [x] With the controller on Search, the box focused with a term in it: B clears it and the whole library shows again; B again goes back as anywhere else. The same on a platform's page filter box.

## Delete a game from RomM (#135)

89. [x] Sign in again: Settings → Profile → RomM account → Sign in again on your admin profile. Pair (RomM's page lists "Modify ROMs" among what Gargosy asks for) or use the password; you're back on Settings with "Signed in again as …", the profile, its PIN and saves unchanged. A profile of a player who isn't an admin or editor signs in again too, and its ⋯ menu has no Delete from RomM….
90. [x] Delete a test game you can lose (downloaded): ⋯ → Delete from RomM… opens the prompt with Cancel focused; it says permanent and that everyone's saves and states of it go. A on Delete only says "Hold A to delete"; B cancels and nothing changes. Open it again, leave both ticked, hold A on Delete: the page closes, "Deleted … from RomM.", the game is gone from its platform's gallery and from Home, gone in RomM's web UI, its file gone from the server (a rescan doesn't bring it back), and gone from `roms\` here. Another game with "Also delete the file on the server" unticked: gone from RomM's library until the next scan.

## Home after RomM v2's Home (#139)

91. [x] Home with the controller: the game you played last fills the top over its art, with "LAST PLAYED · …", On this PC, and its newest state; Resume has focus and resumes it (a game without a state has Play, or Download when it isn't on this PC). Game page opens it. The three widgets show a random pick (Y draws another), a game released on this day (or says none), and your library's numbers. The rows come in order: Continue playing (without the header's game), Recently added, Favourites, On this PC, Platforms, Collections; See all at a row's end opens the gallery, or the Platforms / Collections tab. The D-pad reaches every row; LB/RB still switch tabs.
92. [x] Customize Home (at the end of Home, and Settings → Home): turn Favourites off, move Recently added to the top with ↑, turn For you on, turn On this day off, choose Random pick at the top: Home follows at once and keeps it after a restart. Another profile's Home is unchanged. Reset to the default brings the standard Home back.
93. [x] With RomM unreachable (stop it, or unplug the network): Home shows the game last played on this PC at the top, On this PC first, then Continue playing from this PC; no widgets, nothing that needs RomM. A new profile that has played nothing gets the random pick at the top with Download and Another.


## Quit a game with the controller (#141)

94. [x] Start a game in RetroArch from the controller and play a bit (make a save). Hold Select (View) + LB + RB for 1 second: the emulator closes on its own, Gargosy comes back in front with the focus (the controller moves around Gargosy at once, no click needed), and the session's message says the save synced. Try it in PCSX2 and Dolphin too: they close the same way, without asking "are you sure?"; the log has `[Quit]`, `[Close]` and `[Window]` lines. Let go before 1 second: nothing happens. Settings → Controller → Hold to quit: Select + Start works instead, with both an Xbox controller and an 8BitDo; Off: holding does nothing. Close an emulator the usual way (its own menu): Gargosy comes back in front too.

## Free space before a download (#142)

95. [x] On a drive with less free space than a game needs (a small USB stick or a nearly full partition holding the Gargosy folder, or pick a game bigger than the free space): the game page shows "… free on X:" under Download, and Download fails at once with "Needs …, … free on X:", leaving nothing in `roms\` or `userdata\app\temp`. With enough space it downloads as before, without the line.

## Download queue and the Downloads page (#143)

96. [x] Press Download on three games, one after another: only the first downloads, the game page of the others says Queued (with Remove from the queue). Start → Downloads (it shows the number waiting) lists the running one with its size, speed and time left, then the queue. Y on the last queued one moves it first; X on a queued one takes it out; X on the running one stops it and the next starts. When they're done they're under DONE, and A opens the game. Switch profile while one waits: Gargosy asks first, and Cancel keeps them going. Queue more than the drive holds: the one that wouldn't fit with those before it isn't queued, and its page says "With the downloads before it: Needs …".

## Collections from the game page (#144)

97. [x] On a game's page, ⋯ → Add to collection…: your own collections are listed (Favourites first, not other players'), ✓ on those it's in. A on one puts the game in, A again takes it out; RomM's web UI shows the same. New collection…: type a name, choose Only you or Shared: it's made with the game in it, and shows on the Collections tab. On your own collection's page, ⋯: Rename… changes the name there and on RomM; Share / Stop sharing changes the "Shared on RomM" chip; Delete collection… asks first, then the page closes and the collection is gone (its games stay). Another player's shared collection has no ⋯.

## Storage on this PC (#145)

98. [x] Settings → Storage (THIS PC; it replaces Image cache, whose card is at its end): the drive's free space and size, then ROMs, Emulators, BIOS, profiles' data, Image cache and Temp with their sizes (Explorer's folder properties agree, roughly). ROMs by platform, largest first: A on one lists its games largest first, with size and when last played; a game another profile downloaded says it isn't in this profile's library. A on one asks, then deletes only that ROM (its saves stay; the game page says Download again). X marks two, Delete marked asks with the total, and both go. Empty Temp is refused while a download runs.

## Play time (#146)

99. [x] Play a game for a few minutes and close it. Its page's Overview says "Last played … · Played N min · 1 session", and Home's header shows "N min played". RomM's web UI (the game's play sessions, or Profile → Play sessions) lists the session. Play it on another PC (or another profile of the same RomM user): the time adds up there too. With RomM unreachable, play again: the time says "on this PC", and the session reaches RomM after the next game played with RomM back.

## Screensaver (#147)

100. [x] Leave Gargosy on Home untouched for 5 minutes: the screensaver shows a game at a time (its art, cover, name, platform and year, drifting), a new one every 8 seconds. Any button (or a key, a click, moving the mouse) closes it and puts you back on Home, and that press does nothing else. A opens the game shown. It doesn't come while a game runs, or over a game's page or a menu. Settings → Display → Screensaver: Off stops it; After 2 minutes makes it come sooner.

## A save state on close

101. [x] With save-state sync on, play a game in RetroArch, DuckStation and PCSX2 in turn, a minute each, and close it with the quit buttons. Each time the game's Saves tab → States has a new state from now (RetroArch: Auto; DuckStation and PCSX2: Resume) and it is on RomM; Resume starts the game where it was closed. A plain Play still starts the game from the beginning.

## This PC as a RomM device (#162)

102. [x] Open a profile that signed in with a password: RomM's web UI (Profile → Devices) lists "Gargosy on <PC name>" once, and the log has `[RomM] this PC is device …`. Close and open Gargosy: no second device. Play a game: while it runs RomM shows it as being played on that device; after, the play session and the uploaded save name that device. Copy the Gargosy folder to another PC (or Windows user) and open the profile there: it signs in again and gets its own device. A profile paired with a code keeps the device it was paired as.

## Both sticks in to quit (#163)

103. [x] Settings → Controller → Hold to quit → Both sticks in (L3 + R3). Start a game and press both sticks in for 1 second: the emulator closes and Gargosy comes back in front, with an Xbox controller and with the 8BitDo in X mode. One stick alone does nothing; Select + LB + RB does nothing while this is chosen.

## Quit with a controller that isn't XInput (#164)

104. [x] With a DualSense (or DualShock 4), a Switch Pro controller, or the 8BitDo in D or S mode: start a game from that controller, hold the quit buttons for 1 second (Select is Create/Share on a DualSense, − on Switch): the emulator closes and Gargosy comes back in front. The log has `[Quit] hid<n> is <name> (<vendor>:<product>)` at the start and `[Quit] hid<n> holds …` while you press. With a controller SDL doesn't know, the log says so and nothing else changes. An Xbox controller still works as before.

## A controller connected during a game (#172)

105. [x] Start a game with only an Xbox controller (or the keyboard). Then turn on or plug in a DualSense, Switch Pro controller or the 8BitDo in D mode, wait 2 seconds and hold the quit buttons for 1 second: the emulator closes. The log has `[Quit] hid<n> is <name>` after the controller came. Turn a controller off during a game: the log has `[Quit] hid<n> disconnected` once and nothing more; another controller still quits.

## The Achievements tab as RomM's (#174)

106. [x] Open a game with RetroAchievements and some unlocked on RomM, then its Achievements tab: each row has its badge (the locked ones greyed and dimmed), the summary shows earned / all, points, and the progression and missable counts, and the rows have their type tag. With the controller alone, go up to the filters: Missable shows only missable ones, ✓ Earned only earned ones, pressing it again shows all. The list is 2 columns at 1280 px wide, 3 at 1920, 4 on a wider screen.

## Controllers SDL's list doesn't know (#171)

107. [x] Start Gargosy with `--hid-ignore-sdl` (add it to a shortcut's target), so the 8BitDo in D mode counts as unknown. Start a game: the log has `[Quit] hid<n> is … buttons from a guess`; try holding the quit buttons (it may or may not work, it's a guess). Quit the game, then Settings → Controller → Controllers taught → Teach: press Select, Start, LB, RB, L3 and R3 on the 8BitDo, one at a time. B and A on it are taught too, not Back or OK; a button pressed twice says it's already taught; Escape cancels, Enter skips. It ends with "Saved for …" and the row says 1 controller. Start a game: the log has `buttons from taught` and holding the quit buttons closes it. Forget taught buttons sets the row back to None.

## Status, rating and completion kept on RomM 5.4 (#177)

108. [x] On a game's page, change its status, rating and completion. Go back and open the game again: the new values are there. RomM's web UI shows them too. Set Backlog and Now playing: they stay as well.

## Overview as RomM's (#179)

109. [x] Open a well-known game RomM matched on HowLongToBeat (Super Metroid, Ocarina of Time): the Overview starts with the description and genres, then Last played, Players with an icon and Age rating as the boards' icons (PEGI, ESRB…; the mouse over one shows its text, e.g. `PEGI 7`) as rows, then How long to beat's times, then screenshots, then Similar games in your library as small covers (A opens one). Go through it all with the controller alone. A game without facts, times or similar games shows none of those.

## Playing now (#180)

110. [x] Start a game in RomM's web UI (or on another PC with Gargosy) as another RomM user. Within 30 seconds Home in Gargosy starts with Playing now: a card as large as Random pick with the game's cover on the left, then the game, the platform, their avatar from RomM (their initial when they have none), their name, where ("in RomM's web UI", "on Gargosy") and for how long. Start a game in Gargosy on this PC: after it, the card says "You" and "on this PC". A on a card opens the game's page. When nobody plays, the row is gone. Customize Home lists Playing now first and can turn it off. In a window 1600 px wide or more, Random pick and On this day are stacked to the right of the game played last, as tall as its cover, and the D-pad reaches them from its buttons; narrower, they sit side by side under it. Your library is one slim line under them either way.

## Home rows fit the window (#184)

111. [x] On Home, every row (Continue playing, Recently added, Favourites, On this PC, Platforms, Collections, Playing now) ends inside the window: no card cut off at the right edge, and nothing scrolls sideways. A row with more than fit ends with See all, which opens that section; a short row shows all its games with See all after them. Make the window narrower and wider: rows show fewer and more. Go along a row with the D-pad to See all and press A.

## A gallery saved as a smart collection (#188)

112. [x] Open a platform's page, then Filters: pick a genre, then Save as smart collection…. Type a name with the on-screen keyboard, pick Only you: the new collection opens, marked Smart collection, with that platform's games of that genre, and RomM's web UI lists it under smart collections with the same games. Turn On this PC on and save again: Gargosy says On this PC can't be saved before asking a name. On the new collection's page, ⋯ renames it, shares it (Shared on RomM) and deletes it (after asking); its games stay. Do it once with the controller alone. Inside a smart collection, Filters has no Save button.

## Achievements earned in a session (#189)

113. [x] With a RetroAchievements login in Settings → RetroAchievements and your RA username linked on your RomM profile, play a game RomM matched on RetroAchievements and earn one achievement (an easy first one: Sonic's rings, a first level). Quit: the save message comes first, then within a minute a second line says "1 achievement earned · N points (softcore)" (hardcore when that switch is on), and the Achievements tab shows it earned. Start it once more with Home's Resume and earn another: the line shows on Home too. Play again without earning one: no second line. A game without RetroAchievements, or a profile without an RA login: no second line, and nothing else changes.

## Swedish (#191)

114. [x] Settings → Display → Language → Svenska: the whole of Gargosy is Swedish at once, the sidebar and the top bar too, without a restart. Go through Home, a platform's page, a game's page (every tab), the play screen, Downloads, Collections, Search and every Settings page with the controller: no English left in Gargosy's own text (names and descriptions from RomM stay as they are), nothing cut off or overlapping at 1080p. A save's date reads "28 sep." and a size "1,4 MB". Quit and start Gargosy: still Swedish, the profile picker too. Type å, ä and ö on the on-screen keyboard. Set System: Swedish when Windows is, English otherwise. Set English: all English again.

## Secrets behind one interface (#198)

115. [x] Install this build over the last one. Every profile opens without signing in again (with its PIN where it has one), and a game in RetroArch still signs in to RetroAchievements. Nothing else looks different.

## Ending an emulator behind one interface (#199)

116. [x] Start a game and hold the quit buttons (Settings → Controller → Hold to quit): the emulator closes as before, its state is kept where it keeps one on close (RetroArch, DuckStation, PCSX2), and Gargosy comes back to the front with the session's message. Nothing else looks different.

## Unpacking behind one interface (#200)

117. [x] Play a zipped game in an emulator that can't open zips (PCSX2, Dolphin or DuckStation): it unpacks with a percentage once, the zip goes, and the game starts. Play a zipped original Xbox disc in xemu: it streams into an XISO and starts. Install or update an emulator whose download is a zip (Settings → Emulators): it installs as before.

## Free space behind one interface (#201)

118. [x] Settings → Storage: the drive line says the Gargosy folder's drive with its free space and size, as before. A game page whose download is large for the free space says "… free on D:" under Download. A download bigger than the free space is refused with "Needs …, … free on D:." before anything is written.

## Coming back to the front behind one interface (#202)

119. [x] Play a game in full screen with the controller alone and quit it from the emulator's own menu: Gargosy is in front again, ready for the controller, without touching the mouse or keyboard. Do the same with Settings → Emulators → Open and close the emulator.

## Updates behind one interface (#203)

120. [x] Settings → About → Updates → Check now: it finds the newest release as before (on a dev build, 0.5.0 is offered) and Update now is there; no need to press it. The release notes open.

## PathGuard on a case-sensitive file system (#204)

121. [x] On Windows nothing changes: download a game, play one in Eden, Azahar, Cemu or melonDS with one profile, switch profile and play it again (its own saves; the folder link is re-pointed), and update an emulator from Settings → Emulators.

## Starting a game from outside Gargosy (#223)

122. [x] Make a desktop shortcut to `Gargosy.exe --play=<rom id>` (the id from the game's RomM address) for a downloaded game. With Gargosy closed, open it: with one profile it opens (its PIN asked when it has one), with several the picker asks who is playing and the one picked plays; the game starts without a press, and when you quit the game its saves sync and Gargosy closes.
123. [x] The same with `--profile=<profile id>` (its folder's name under `userdata\profiles\`): that profile opens without asking who. With a wrong PIN or Back, the picker stays and no game starts. With RomM unreachable, quit the game: Gargosy says the save didn't reach RomM before it closes.
124. [x] Add `Gargosy.exe` to Steam as a non-Steam game with `--play=<rom id>` as its launch options, start it from Big Picture with a controller: the game runs, and Steam sees it end when Gargosy closes after the sync.
125. [ ] `--play-stay`: Gargosy stays open on the game's page after the session, with the session's message.
126. [ ] With Gargosy open on Home, open the shortcut: no second Gargosy starts; the open one comes to the front, plays the game, and stays open after it. With `--profile=` of another profile: it switches (asking about downloads, PIN where it has one) and plays it there. With a game running: "A game is already running" and nothing else. Open `Gargosy.exe` twice without arguments: the first comes to the front.
127. [x] A downloaded game's page → ⋯ → Create desktop shortcut: a shortcut named after the game, with its cover as the icon, is on the desktop and the toast says its name. Do it again: a second one, `(2)`, the first untouched. Open one with Gargosy closed: the game starts in this profile without asking who.

## Age limit per profile (#224)

128. [x] Give a parent's profile a PIN. On a child's profile: Settings → Profile → Age limit → Up to 12 asks for the parent's PIN (a wrong one changes nothing). A game rated M or PEGI 16 then says "… is above this profile's age limit." at Play and Resume. Turn on Hide unrated games: an unrated game is refused too. Settings → Emulators → Open is refused while the limit is on. Off, with the parent's PIN, plays everything again. A profile made after the child's (with a PIN, no limit) is never asked for as the parent's.
129. [ ] On a child's profile with Up to 12: a platform's page, Search, a collection, Home's rows (not Playing now), For you, Similar games and the screensaver show no game rated above 12 (an M or PEGI 16 game you know of isn't there); the A–Z rail and the GAMES count leave them out too. Hide unrated games: unrated ones go as well. On a profile without a limit everything is there.

## Checking a download (#225)

130. [ ] Download a one-file game and a multi-disc game: each says Checking… after downloading, then lands as before. Settings → Storage → Check downloads off: no Checking…. (A damaged download is hard to make by hand: the unit tests cover it; if one ever fails with "The download is damaged", Retry gets it again.)

## Download all (#226)

131. [ ] A collection with a few games, some on this PC: Download all says how many and about how big (only those not on this PC), and queues them in the collection's order; Downloads lists them. Cancel all empties the queue while the first goes on. A platform's page does the same. With too little room it says "Needs …" and queues nothing.
