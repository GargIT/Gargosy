# Gargosy

A RomM client for Windows that looks and feels like RomM's v2 web UI: controller-first,
always portable, with a profile per player. Built on code from
[Freegosy](https://github.com/abduznik/Freegosy) (see `NOTICE.md`).

## Screenshots

**Who is playing?** Pick a profile.

![The profile picker](docs/screenshots/1-profiles.png)

**Home.** A random pick and the games you were playing.

![Home](docs/screenshots/2-home.png)

**Platforms.** Each platform with a strip of its covers.

![Platforms](docs/screenshots/3-platforms.png)

**A game's page.** Status, rating, saves, achievements and notes, as on RomM.

![A game's page](docs/screenshots/4-game-page.png)

**The play screen.** Choose the save or state and the emulator the game starts with.

![The play screen](docs/screenshots/5-play-screen.png)

## Using it

Unpack `Gargosy-<version>.zip` anywhere you can write (a USB stick works too). The folder holds
everything: the app, `roms\`, `emulators\`, `bios\` and `userdata\`. Nothing goes in AppData.
Download it from [Releases](https://github.com/GargIT/Gargosy/releases); what changed is in
`CHANGELOG.md`. A *preview* of the next version (e.g. `0.2.0-preview.12`) is there too, marked
pre-release: it's rebuilt each time an issue of that version's milestone is done. Take it to try
what's coming; take the latest release for everyday use.

**RomM version.** Gargosy needs RomM 4.8 or newer, and works best with 5.3 or newer (tested on 5.3.1).
Pairing with a phone needs 5.0; before that you log in with username and password. Before 5.3, RomM
doesn't send game ids (disc serials, title ids), so Gargosy reads them from the ROM itself.

Gargosy.exe isn't code-signed, so the first start may show Windows' "Windows protected your PC".
Choose **More info**, then **Run anyway**.

- **Profiles.** Each player adds a profile with their own RomM account (pair with a phone, or
  username and password). A profile's saves, states and emulator settings are its own.
- **PIN.** A profile can have a four-digit PIN. It's a family lock, not security: anyone using
  the same Windows account can open the Gargosy folder.
- **Emulators.** Start → Emulators: download one, or import an install you already have
  (it's copied; your install isn't changed). Put BIOS files in `bios\`. ScummVM has no
  download here: get it from scummvm.org and import it.
- **Playing.** On a game's page: Download, then Play. The play screen picks the newest save;
  Y changes the emulator, RB shows the save states.
- **Offline.** Games on this PC still play; saves upload when RomM can be reached again.
- **Wii U (Cemu).** Each profile has its own Wii U storage, so updates and DLC are installed per
  profile.
- **Another PC.** Copy the folder. Profiles, saves and settings come along; each profile logs
  in again once (the login is encrypted for this PC's Windows user).
- **Updating.** Gargosy checks GitHub once a start (not more than every 6 hours) and puts a dot
  on your avatar when a new version is out. About → **Update now** downloads it, closes Gargosy,
  swaps the app files and starts it again; your games, emulators, BIOS files and `userdata\`
  are never touched. The **channel** in About is *Latest* (releases only) or *Preview* (the
  preview too). Gargosy never goes back to an older version, so switching from Preview to
  Latest offers nothing until a release is newer than what you have.
  - **From 0.1.0**, update by hand once: unpack the new zip and copy its files over the old
    ones. 0.1.0 has no updater; every version after it updates itself.
  - **If an update stops half way** (the PC lost power) and Gargosy won't start, copy everything
    from `userdata\app\update\previous\` back into the Gargosy folder, or unpack the new zip
    over it. `userdata\app\update\update.log` says how far it got.

## Developing

```
flutter analyze && flutter test
flutter run -d windows -a --root=<a scratch folder>
pwsh tool/make_release.ps1        # dist\Gargosy-<version>.zip
```

`sigil.dll` comes from the `third_party/argosy-sigil` submodule: clone with
`--recurse-submodules`, and run `pwsh tool/build_sigil.ps1` once before `flutter test`.

To release: set the version in `pubspec.yaml`, give its section in `CHANGELOG.md` a date, commit,
then push a tag `v<version>`. The Release workflow tests, builds the zip and publishes it with that
section as the notes.

Previews: closing an issue of a milestone (e.g. `0.2.0`) as completed runs the Preview workflow. It
tests `main`, builds `Gargosy-0.2.0-preview.<run>.zip` and replaces the pre-release `v0.2.0-preview`,
with the milestone's progress and the `[Unreleased]` changelog as notes. It can also be run by hand
from the Actions tab.
