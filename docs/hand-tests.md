# Hand tests for 0.2.0

These are the tests left for a person on the open issues. Everything else is covered by `flutter test` and the probes noted in each issue. Tick a row (`[x]`) once it passes. When every row of an issue is ticked, the issue can be closed. A failure goes in the issue, with the log (Settings → About → Open log folder).

The test install is `C:\Retro\apps\gargosy` (built from `main`). For tests that use two profiles, make two profiles signed in to the same RomM user, unless the row says otherwise.

## Logging (#1)

1. [ ] Sign in with a password, pair a device with the QR code, and sign in to RetroAchievements. Open the log in `userdata\app\logs\`, and check that no token, password or API key appears in it.
2. [ ] Lines written while a profile is open carry its `[p:…]` tag, and lines from the profile picker carry none.

## RetroArch saves through sigil (#7)

For each system below, play a game in RetroArch through Gargosy, save in-game and quit. Then:

- check that the save is on RomM in the `autosave` slot;
- delete the save on this PC;
- start the game again and check that the save comes back;
- open the game in RomM's web player and check that the save loads there.

3. [ ] Game Boy
4. [ ] Game Boy Color, a game with a clock (e.g. Pokémon Gold/Silver/Crystal)
5. [ ] Nintendo 64
6. [ ] PlayStation (PS1)
7. [ ] PlayStation 2 with the LRPS2 core

## Folder link on a USB stick (#8)

8. [ ] Copy Gargosy to a FAT32 or exFAT USB stick and start Eden, Azahar, Cemu or melonDS from it. The launch is refused with "A folder link can't be made … The drive may be FAT32 or exFAT", and nothing is written.

## Ryujinx (#9)

9. [ ] Settings → Emulators → Download Ryujinx (from Ryubing). It installs and starts.
10. [ ] Play a Switch game in profile A and save. Then play it in profile B: B has no save from A. The save is on RomM. Start a game once before a RomM save can be put in place.

## RPCS3 (#10)

11. [ ] Play a PS3 game in profile A and save. In profile B the save isn't there. The save is on RomM.
12. [ ] While a game runs, nothing in `emulators\rpcs3-firmware\dev_flash` changes (compare the modified dates before and after).

## ScummVM (#11)

13. [ ] Play a game downloaded from RomM as a `.scummvm` file, then save and load in-game.
14. [ ] Play a game that is a folder, then save and load in-game.

## Eden, Azahar, Cemu, melonDS (#12–#15)

For each one: play a real game in profile A and save. Then play it in profile B, which starts without A's save. A's save is on RomM.

15. [ ] Eden (Switch) (#12)
16. [ ] Azahar (3DS) (#13)
17. [ ] Cemu (Wii U) (#14)
18. [ ] melonDS (DS) (#15)

## Updates (#16)

These rows need preview releases published on GitHub.

19. [ ] Settings → About → Updates: the updater window shows its progress and starts Gargosy again when it's done.
20. [ ] On a preview build, About shows the preview version, and its Updates block shows the Preview channel.
21. [ ] A real update from preview N to N+1. Afterwards, `roms\`, `emulators\`, `bios\` and `userdata\` are unchanged, and What's new (#3) opens once with N+1's changes.
