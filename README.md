# Gargosy

A RomM client for Windows that looks and feels like RomM's v2 web UI: controller-first,
always portable, with a profile per player. Built on code from
[Freegosy](https://github.com/abduznik/Freegosy) (see `NOTICE.md`).

## Using it

Unpack `Gargosy-<version>.zip` anywhere you can write (a USB stick works too). The folder holds
everything: the app, `roms\`, `emulators\`, `bios\` and `userdata\`. Nothing goes in AppData.

- **Profiles.** Each player adds a profile with their own RomM account (pair with a phone, or
  username and password). A profile's saves, states and emulator settings are its own.
- **PIN.** A profile can have a four-digit PIN. It's a family lock, not security: anyone using
  the same Windows account can open the Gargosy folder.
- **Emulators.** Start → Emulators: download one, or import an install you already have
  (it's copied; your install isn't changed). Put BIOS files in `bios\`.
- **Playing.** On a game's page: Download, then Play. The play screen picks the newest save;
  Y changes the emulator, RB shows the save states.
- **Offline.** Games on this PC still play; saves upload when RomM can be reached again.
- **Another PC.** Copy the folder. Profiles, saves and settings come along; each profile logs
  in again once (the login is encrypted for this PC's Windows user).

## Developing

```
flutter analyze && flutter test
flutter run -d windows -a --root=<a scratch folder>
pwsh tool/make_release.ps1        # dist\Gargosy-<version>.zip
```
