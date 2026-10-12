Closes #

## What changes
<!-- What a user or a reviewer will notice, by area. -->

## Not in this PR
<!-- What was left out on purpose, and where it goes instead. Write "Nothing." if nothing was. -->

## Tests
<!-- New or changed tests, and what they pin down. -->
- [ ] `flutter analyze && flutter test` pass (CI on windows-latest is green)
- [ ] Tried in the app at 1080p, with a controller alone

## Checklist
- [ ] Every write goes through `PathGuard`; nothing written outside the Gargosy folder
- [ ] Paths and the RomM session come from the active profile (`ProfileContext`)
- [ ] Works with a controller alone: focus, B back, LB/RB
- [ ] Emulator behaviour lives in strategies, not the UI
- [ ] Copied Freegosy code is marked, and its tests came along
- [ ] CLAUDE.md file map updated (files created, split or moved)
- [ ] CHANGELOG.md line under [Unreleased], if a user would notice
- [ ] No link to the session that made it, in commits or here
