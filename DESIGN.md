# Gargosy — Design

How Gargosy looks and behaves. The code follows this file: when a design
decision changes, change this file in the same PR, and add a line to the
decisions log at the end.

## Principles

1. **RomM v2's look, dark only.** Gargosy should feel like RomM's v2 web UI.
   Copy token *values* only: never RomM's code, CSS, icons or logo (RomM is
   AGPL-3.0). Images RomM itself takes from elsewhere (IGDB's rating icons)
   may be used the same way.
2. **Controller first.** Every screen works with a controller alone. Mouse
   and keyboard come second, but they always work.
3. **Made for a TV.** Read at a distance: text 13 px or more for anything
   that matters at 1080p, the focus always visible, one focus ring style.
4. **Nothing scrolls sideways** except a gallery's grid. Rows show what fits
   the window, with See all last.
5. **Say why.** An action that can't run is greyed with the reason beside
   it, or refused with a message that says why. Never a silent no.
6. **RomM's order.** Where RomM's v2 page has an order (the Overview's
   sections, a header's facts), Gargosy keeps it.

## Tokens

All in `lib/ui/theme/tokens.dart`. Never a raw colour or size in a widget
when a token exists.

### Colours (`GColors`)

| Token | Value | Use |
|---|---|---|
| `bg` | `#07070F` | The page |
| `bgElevated` | white 4.5 % | A panel on the page (HowLongToBeat strip) |
| `surface` | white 7 % | Chips, badges, See all, empty cover |
| `surfaceHover` | white 12 % | Secondary buttons, hover |
| `card` | `rgba(20,16,36,.6)` | Cards: settings, Home widgets, Playing now |
| `panel` | `rgba(16,12,28,.97)` | Menus, dialogs, dropdowns |
| `border` / `borderStrong` | white 7 % / 15 % | Card edges / emphasised edges |
| `fg` / `fgSecondary` / `fgMuted` / `fgFaint` | white 100 / 75 / 45 / 25 % | Text by importance |
| `primary` (+ `Hover`, `Pressed`) | `#8B74E8` | The main button, the active tab |
| `fav` | `#FF4F6B` | Favourite ♥ |
| `danger`, `dangerFill` | `#FF5050`, `#D83A3A` | Delete, Switch profile |
| `success`, `warning` | `#4ADE80`, `#FBBF24` | States, Achievements |
| `gargosyTeal` | `#3DD6C4` | "On this PC", Gargosy's own marks |
| `gargosyGold` | `#F2C14E` | Logo only |
| `coverArtBase` / `coverArtShade` | `#553E98` / `#371F69` | The gradient of a missing cover |
| `profileColors` | six | A profile's badge; another player's initial |

### Space, radius, type, motion

| Group | Values |
|---|---|
| `GSpace` | `s1` 4, `s2` 8, `s3` 12, `s4` 16, `s5` 20, `s6` 24, `s8` 32, `s10` 40, `s12` 48, `s14` 56; `rowPad` 36 (a page's side edge) |
| `GRadius` | `sm` 4, `chip` 6, `md` 8, `lg` 10, `card` 14, `xl` 20, `pill` 100 |
| `GFont` | `xs` 10.5, `sm` 11.5, `md` 13, `lg` 14.5, `xl` 17, `xxl` 22, `xxxl` 32, `xxxxl` 38 |
| `GMotion` | `fast` 150 ms, `med` 220 ms, `slow` 360 ms; `easeOut`, `easeInOut` |
| `GFocusRing` | 2 px mouse, 2.5 px keyboard, 3.5 px controller, 3 px offset |
| `GLayout` | top bar 58 px, tab pill 38 px, touch target 44 px |

### Type roles

| Role | Size | Weight | Colour |
|---|---|---|---|
| Section label (`LAST PLAYED`, `RANDOM PICK`) | `xs`, CAPS, letter-spacing 0.8–1.2 | 700 | `fgSecondary` or `fgMuted` |
| Row title (`Recently added  42`) | `xl`, count `md` | 700, count 400 | `fg`, count `fgMuted` |
| Card title | `lg` | 700 | `fg` |
| Card line | `sm` | 400 | `fgSecondary` |
| Small print (where, how long) | `xs` | 400 | `fgMuted` |
| Page title (header) | `xxxxl` | 800 | `fg` |
| Body (description) | `lg`, line height 1.6 | 400 | `fgSecondary` |

## Layout

- **Page:** `rowPad` (36 px) on both sides. Under the top bar (58 px, glass
  once the page has scrolled).
- **Header:** the art blurred behind; the cover on the left, then label,
  title, a line of facts, chips, buttons. Game page and play screen share
  the cover's place, so going between them doesn't move it.
- **Breakpoints:**
  - under 1100 px: one column (saves, play screen's panels in a row above
    the list);
  - 1100 px and up: two columns for saves and the play screen;
  - 1600 px and up: Home's Random pick and On this day stand stacked beside
    the header.
- **Rows** (`Shelf`): only the cards that fit; See all in the last place when
  they don't all fit, after them when they do.
- **Grids** (`CoverGrid`): as many columns as fit, focus wraps from the end
  of a row to the next; the A–Z rail in the right margin when sorted by name.

## Components

| Component | File | Size | Rules |
|---|---|---|---|
| Game card | `ui/widgets/game_card.dart` | 158 × 213 cover | Marks: versions top left, regions bottom left (three, then +N), on this PC and ♥ top right. Small cover from RomM in grids and rows. |
| Platform card | `ui/pages/platform_card.dart` | 280 × 190 on Home | A fan of up to five covers, logo, name, "maker · year · N games". |
| Collection tile | `ui/widgets/collection_tile.dart` | 158 wide, 140:188 | Mosaic of up to four covers; marks for smart, shared, another player's. |
| Row | `ui/widgets/shelf.dart` | card height + 12 | Title with count; fits the width; See all last. |
| Home widget | `ui/pages/home/home_widgets.dart` | 128 high (120 stacked) | `card` box, 16 px padding, cover 66 × 88 left, label in caps, title, lines. |
| Playing now | `ui/pages/home/playing_now.dart` | 420 × 128 | As a Home widget; the player's avatar beside their name. |
| Your library | `home_widgets.dart` | one line | Label, then each number bold with its name muted. |
| Fact row | `ui/screens/game/overview_facts.dart` | label 130 px | Label in caps left, value right (text, badge or icons). |
| Badge / chip | various | pill | `surface`, 12 × 5 padding, icon 16 px before the text. |
| Age rating | `overview_facts.dart` | 44 × 44 | The board's icon from IGDB, its text as tooltip; the text when the icon doesn't load. |
| Player avatar | `ui/widgets/save_list/player_avatar.dart` | 22–32 | Their RomM avatar; else their initial on their colour. |
| Dropdown | `ui/widgets/g_dropdown.dart` | | Outlined field with icon and chevron; the list opens under it, ✓ on the current. |
| Buttons | | pill | Primary: `primary` fill. Secondary: `surfaceHover`. Destructive: `dangerFill`, and only on hold A. |
| Dialogs | `ui/widgets/controller_dialogs.dart` | | Cancel focused when the action destroys something. |

## Controller

| Button | Everywhere | Where it differs |
|---|---|---|
| D-pad / stick | Moves focus to the nearest item in that direction | A–Z rail: left jumps |
| A | Open, activate | Hold A: delete or forget (saves, recent searches, games) |
| B | Back | In a filled text box: clears it first |
| X | Options for the focused item | Gallery: the A–Z rail; profile picker: profile options |
| Y | Favourite the focused game | Home: another random pick; game page: resume the newest state; Saves tab: share |
| LB / RB | Previous / next tab | |
| Start | The user menu | |
| Hold the quit buttons (Select + LB + RB by default) | Quits the running game | Set in Settings → Controller |

- Every screen remembers its focus; the first item gets focus once when the
  screen opens.
- Each tab of a page is its own focus scope; LB/RB gives back its last focus.
- A text box opens the on-screen keyboard on A with a controller, and is
  typed into directly with a keyboard.
- The mouse's back button and Escape do what B does.

## Patterns

- **Empty:** say what is missing and what to do ("Nothing matches your
  filters · Show all"). A row or section with nothing in it is left out, not
  shown empty.
- **Loading:** a spinner where the content will be, under the header, never
  over it; a filter being typed keeps its focus.
- **Errors:** what failed, and Retry.
- **Offline:** a banner; only this PC's games; RomM-only sections are left
  out, not greyed.
- **Images:** RomM's small cover in grids and rows, the large one on the
  game page and play screen. A missing or failed image is the cover
  gradient with the title.
- **Other players:** their avatar from RomM, else their initial on their
  colour; "You" for the profile's own.
- **Counts** next to titles count different things, not copies (a save on
  RomM and here is one).
- **Time:** "for 25 min", "7 h", "9.5 h"; dates as RomM shows them.

## Screens

| Screen | Order, top to bottom | Decided in |
|---|---|---|
| Home | Header (last played, Resume / Play, Game page; ≥ 1600 px the widgets beside it); widgets (Random pick, On this day); Your library; rows in the profile's order, Playing now first | #139, #180, #184 |
| Game page | Cover column (Play, ♥, ⋯); title, pills (status, rating, completion); tabs Overview, Saves, Achievements, Notes, Details | #95 |
| Overview tab | Description and genres; facts (Last played, Players, Age rating); How long to beat; screenshots; similar games in your library | #179 |
| Achievements tab | Summary; filters by type and earned / locked; badges in 1–4 columns (380 px each) | #174 |
| Play screen | Cover + Play / Resume + what A does; Saves \| States; Plays in (emulator, core, full screen) | |
| Platform page | Header (logo, facts, Random); tabs Library, Firmware, BIOS, Emulator | #95 |
| Gallery | Filter bar (search, Filters, On this PC, Sort); grid; A–Z rail when sorted by name | #95 |
| Collections | Heading, filter bar, Kind and Whose; the players' collections; RomM's virtual ones by type | #121 |
| Search | Header with the search box (moves onto the bar on scroll), counts, recent searches; the library by best match | #132 |
| Settings | RomM v2's profile page: grouped sidebar (Profile, Library, This PC, Gargosy), cards on the right | #6 |

Mockups are linked from each issue.

## Language

- Gargosy's own text is in English or Swedish (Settings → Display →
  Language; System follows Windows). Names, descriptions, genres and
  regions from RomM are shown as RomM sends them.
- Every text the player sees goes through `tr()`; nothing is hard-coded.
  The English text is the key, and `sv.dart` holds its Swedish.
- Words: game **spel**, save **sparfil**, state **sparläge**, collection
  **samling**, platform **plattform**, profile **profil**, achievement
  **prestation**, On this PC **På datorn** (short, it sits on buttons).
- Swedish runs longer than English: rows of buttons wrap rather than
  overflow, and a label that sits on a button stays short.

## Branding

- The app logo is the "G" with three face buttons:
  `assets/branding/gargosy_logo.svg`. It's the source for `gargosy_logo.png`
  (1024 px) and `gargosy_logo.ico` (16–256 px). To change it, edit the SVG
  and render again.
- `assets/branding/drafts/` keeps the other drafts for later use (A1/A2
  controller, B2 G with a D-pad, C1 controller with player badges).
- The logo uses v2's purple with Gargosy's own gold `#F2C14E` and teal
  `#3DD6C4`, in a rounded square.
- Never use RomM's circle, its diagonal split or its logo.

## Decisions log

| Date | Decision | Issue |
|---|---|---|
| 2026-10-21 | Versions of a game are folded into one card; the version count on the cover | #95 |
| 2026-10-24 | Grids and rows use RomM's small covers | PR #125 |
| 2026-10-24 | Home after RomM v2: last played as the header, widgets on/off, rows on/off and ordered per profile | #139 |
| 2026-10-26 | Achievements tab as RomM v2: badges, summary, filters, columns | #174 |
| 2026-10-27 | No Patch tab: patching stays in RomM's web UI | #181 |
| 2026-10-27 | Overview in RomM's order: description first, then facts; no related-games rows (remasters, ports) | #179 |
| 2026-10-27 | Age ratings as their boards' icons, text as tooltip | #179 |
| 2026-10-27 | Playing now as large as a Home widget, cover left, the player's avatar | #180 |
| 2026-10-27 | From 1600 px Home's widgets stand beside the header; Your library one slim line | #180 |
| 2026-10-27 | Home rows show only what fits, See all last; nothing scrolls sideways | #184 |
| 2026-10-27 | Swedish beside English, the English text as the key (`tr()`); app-wide, System follows Windows | #191 |
