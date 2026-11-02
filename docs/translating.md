# Translating Gargosy

Gargosy speaks English, Swedish and German, and more languages come the same way. A
correction or a new language is welcome as a pull request.

## How the text works

- Every text a player sees is written in English in the code, as `tr('…')` (`lib/l10n/tr.dart`).
  The English is the key: a language is a table from the English to its own text, one file per
  language in `lib/l10n/` (`sv.dart`, `de.dart`, …).
- `{0}`, `{1}` … are filled in by Gargosy (a game's name, a number). Keep each of them in your
  text, in whatever order your language needs. `\n` is a line break.
- Names and descriptions from RomM are never translated: they stay as RomM has them.
- `test/unit/l10n_test.dart` fails when a language misses a text, has one the Swedish table
  (`sv.dart`, kept by hand with the code) doesn't, or loses a placeholder. A text removed from the
  code goes from `sv.dart` by hand, and then from every other table.

## Correcting a text

Find the English in the language's file and change the text after it. Keep the quotes escaped as
they are (`\'`).

## A new language

1. Export every text, numbered: `dart --packages=.dart_tool/package_config.json tool/l10n.dart export en.tsv`
   (`<number><Tab><English>`, a line each).
2. Translate each line's text, keeping its number: `<number><Tab><your text>`. Keep the first line (`# texts …`) as it is.
3. Build the table: `dart --packages=.dart_tool/package_config.json tool/l10n.dart build <code> <English name of the language> <your file>`, from the Gargosy folder (`<code>`: the language as Windows names it, two or three small letters).
   It writes and formats `lib/l10n/<code>.dart`, and refuses a missing line, a number twice, a lost
   placeholder, or a file exported before Gargosy's texts changed (export again then).
4. Add the language to `AppLanguage` in `lib/l10n/tr.dart` (its own name, its `intl` locale and the
   table), and the letters it needs to `keyboardRowsFor` in `lib/ui/widgets/on_screen_keyboard.dart`.
5. Check that nothing is cut off at 1280 × 720:
   `flutter test test/widgets --dart-define=GARGOSY_LANG=<code>` (and with
   `--dart-define=GARGOSY_TEXT_150=1` for the largest text size). A "RenderFlex overflowed" names
   the widget to fix; tests that look for English text fail then, which is expected.

## Words

Use the words the language's own game launchers and emulators use, and the same word for the same
thing throughout: a save (the game's own save file) is not a save state (an emulator's snapshot).
Keep RomM, RetroArch, BIOS, PIN, LB/RB and other names as they are.
