import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/library/home_layout.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/library/continue_elsewhere.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/providers/ui_provider.dart';
import 'package:gargosy/ui/pages/home_page.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  Game played(int id, String name, DateTime at) => Game.fromJson({
    ...gameJson(id, name),
    'rom_user': {'last_played': at.toIso8601String()},
  });

  final okami = played(1, 'Okami', DateTime(2026, 10, 24, 12));
  final rez = played(5, 'Rez', DateTime(2026, 10, 20));
  final state = ResumeEntry(
    emulatorId: 'pcsx2',
    emulatorName: 'PCSX2',
    fileName: 'auto.p2s',
    slot: const AutoStateSlot(),
    savedAt: DateTime(2026, 10, 24, 12),
    where: ResumeWhere.thisPc,
  );

  List<Object> overrides({
    List<Game>? recent,
    Game? random,
    List<ResumeEntry> states = const [],
    bool offline = false,
    List<Game> installed = const [],
  }) => [
    recentlyPlayedProvider.overrideWith((ref) async => recent ?? [okami, rez]),
    recentlyAddedProvider.overrideWith((ref) async => [game(2, 'Burnout 3'), game(3, 'Ico')]),
    favouriteGamesProvider.overrideWith((ref) async => [game(3, 'Ico')]),
    randomGameProvider.overrideWith((ref) async => random ?? game(4, 'Shadow of the Colossus')),
    favouriteIdsProvider.overrideWithValue({'3'}),
    gameProvider.overrideWith((ref, id) async => null),
    romSavesProvider.overrideWith((ref, id) async => const []),
    romStatesProvider.overrideWith((ref, id) async => const []),
    romNotesProvider.overrideWith((ref, id) async => const []),
    playStatesProvider.overrideWith((ref, key) => Stream.value(key.game.id == '1' ? states : const [])),
    rommOfflineProvider.overrideWithValue(offline),
    gamesOnThisPcProvider.overrideWithValue(installed),
  ];

  Future<void> pump(WidgetTester tester, List<Object> o) async {
    await setDesktopSize(tester);
    // Tall enough that every row is built.
    tester.view.physicalSize = const Size(1920, 4000);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: o.cast()));
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String row) => tester.getTopLeft(find.byKey(ValueKey('home-$row'))).dy;

  testWidgets('saved on another PC since (#229): the header says where the player left off', (tester) async {
    await pump(tester, [
      ...overrides(states: [state]),
      continueElsewhereProvider.overrideWith((ref, id) async => ElsewhereSave('Gargosy on LIVINGROOM', DateTime(2026))),
    ]);
    final header = find.byKey(const ValueKey('home-header'));
    expect(
      find.descendant(of: header, matching: find.text('CONTINUE WHERE YOU LEFT OFF ON GARGOSY ON LIVINGROOM')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-resume')), findsOneWidget);
  });

  testWidgets('the header is the game played last, with Resume (focused) when it has a state', (tester) async {
    await pump(tester, overrides(states: [state]));
    final header = find.byKey(const ValueKey('home-header'));
    expect(find.descendant(of: header, matching: find.text('Okami')), findsWidgets);
    expect(find.descendant(of: header, matching: find.textContaining('LAST PLAYED')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-resume')), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(of: find.byWidget(focused.widget), matching: find.byKey(const ValueKey('home-resume'))),
      findsOneWidget,
    );
    expect(find.textContaining('State from'), findsOneWidget);
    // Not played on this PC, so Download; no Another for the game played last.
    expect(find.byKey(const ValueKey('home-download')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-another')), findsNothing);
  });

  testWidgets('a wide window stacks Random pick and On this day beside the header; Your library under', (tester) async {
    await pump(tester, overrides());
    final header = find.byKey(const ValueKey('home-header'));
    for (final key in ['widget-random', 'widget-on-this-day']) {
      expect(find.descendant(of: header, matching: find.byKey(ValueKey(key))), findsOneWidget);
    }
    expect(find.descendant(of: header, matching: find.byKey(const ValueKey('widget-library'))), findsNothing);
    final random = tester.getRect(find.byKey(const ValueKey('widget-random')));
    final onThisDay = tester.getRect(find.byKey(const ValueKey('widget-on-this-day')));
    expect(onThisDay.top, greaterThan(random.bottom), reason: 'stacked');
    expect(random.left, greaterThan(tester.getRect(find.byKey(const ValueKey('home-game-page'))).right));
    expect(
      tester.getRect(find.byKey(const ValueKey('widget-library'))).top,
      greaterThan(tester.getRect(header).bottom),
    );

    tester.view.physicalSize = const Size(1280, 4000);
    await tester.pumpAndSettle();
    expect(find.descendant(of: header, matching: find.byKey(const ValueKey('widget-random'))), findsNothing);
    final narrowRandom = tester.getRect(find.byKey(const ValueKey('widget-random')));
    expect(narrowRandom.top, greaterThan(tester.getRect(header).bottom));
    expect(
      narrowRandom.top,
      tester.getRect(find.byKey(const ValueKey('widget-on-this-day'))).top,
      reason: 'side by side',
    );
  });

  testWidgets('without a state there is no Resume; Game page opens the game, B comes back', (tester) async {
    await pump(tester, overrides());
    expect(find.byKey(const ValueKey('home-resume')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-game-page')));
    await tester.pumpAndSettle();
    expect(tester.widget<GameScreen>(find.byType(GameScreen)).game.name, 'Okami');
    await press(tester, GameAction.back);
    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets('the widgets, then the rows in the default order; the header game is not repeated', (tester) async {
    await pump(tester, overrides(installed: [game(9, 'Pikmin 2')]));
    expect(find.byKey(const ValueKey('widget-random')), findsOneWidget);
    expect(find.byKey(const ValueKey('widget-on-this-day')), findsOneWidget);
    expect(find.byKey(const ValueKey('widget-library')), findsOneWidget);
    expect(y(tester, 'continuePlaying') < y(tester, 'recentlyAdded'), isTrue);
    expect(y(tester, 'recentlyAdded') < y(tester, 'favourites'), isTrue);
    expect(y(tester, 'favourites') < y(tester, 'onThisPc'), isTrue);
    final row = find.byKey(const ValueKey('home-continuePlaying'));
    expect(find.descendant(of: row, matching: find.text('Rez')), findsWidgets);
    expect(
      find.descendant(of: row, matching: find.text('Okami')),
      findsNothing,
      reason: 'it is the header',
    );
    expect(find.byKey(const ValueKey('home-forYou')), findsNothing, reason: 'off by default');
  });

  testWidgets('nothing played yet: the random pick is the header, Another draws again', (tester) async {
    var draws = 0;
    await pump(tester, [
      ...overrides(recent: const []),
      randomGameProvider.overrideWith((ref) async {
        draws++;
        return game(4, 'Shadow of the Colossus');
      }),
    ]);
    final header = find.byKey(const ValueKey('home-header'));
    expect(find.descendant(of: header, matching: find.text('RANDOM PICK')), findsOneWidget);
    expect(find.byKey(const ValueKey('widget-random')), findsNothing, reason: 'not shown twice');
    final before = draws;
    await tester.tap(find.byKey(const ValueKey('home-another')));
    await tester.pumpAndSettle();
    expect(draws, before + 1);
  });

  testWidgets('Customize Home: a row off, a row moved up, the top changed — Home follows at once', (tester) async {
    await pump(tester, overrides());
    await tester.tap(find.byKey(const ValueKey('customize-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-row-check-favourites')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-row-up-recentlyAdded')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-widget-onThisDay')));
    await tester.tap(find.byKey(const ValueKey('home-top-nothing')));
    await tester.pumpAndSettle();
    await press(tester, GameAction.back);
    expect(find.byKey(const ValueKey('home-favourites')), findsNothing);
    expect(find.byKey(const ValueKey('widget-on-this-day')), findsNothing);
    expect(find.byKey(const ValueKey('home-header')), findsNothing);
    expect(find.text('Welcome, Anna'), findsOneWidget);
    expect(y(tester, 'recentlyAdded') < y(tester, 'continuePlaying'), isTrue);
  });

  testWidgets('offline: the last game played on this PC, On this PC first, no widgets', (tester) async {
    await pump(tester, overrides(offline: true, installed: [game(9, 'Pikmin 2'), rez]));
    final header = find.byKey(const ValueKey('home-header'));
    expect(find.descendant(of: header, matching: find.text('Rez')), findsWidgets);
    expect(find.byKey(const ValueKey('widget-library')), findsNothing);
    expect(find.byKey(const ValueKey('home-recentlyAdded')), findsNothing);
    expect(find.byKey(const ValueKey('home-onThisPc')), findsOneWidget);
    expect(find.text('Pikmin 2'), findsWidgets);
  });

  testWidgets('fits at 1280×720 with a long name and a state (no overflow)', (tester) async {
    final long = played(
      1,
      'The Legend of Zelda: Ocarina of Time – Master Quest (Europe) (Rev 1)',
      DateTime(2026, 10, 24),
    );
    await setDesktopSize(tester);
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpWidget(
      testApp(
        const HomePage(name: 'Anna'),
        overrides: overrides(recent: [long, rez], states: [state]).cast(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-resume')), findsOneWidget);
    expect(find.byKey(const ValueKey('widget-library')), findsOneWidget);
  });

  testWidgets('down to the end and back up with the D-pad scrolls back to the top', (tester) async {
    await setDesktopSize(tester);
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpWidget(
      testApp(
        const HomePage(name: 'Anna'),
        overrides: overrides(states: [state], installed: [game(9, 'Pikmin 2')]).cast(),
      ),
    );
    await tester.pumpAndSettle();
    final page = find.byKey(const Key('page-Home'));
    ProviderScope.containerOf(tester.element(page)).read(inputModeProvider.notifier).state = InputMode.gamepad;
    ScrollPosition position() =>
        tester.state<ScrollableState>(find.descendant(of: page, matching: find.byType(Scrollable)).first).position;
    for (var i = 0; i < 8; i++) {
      await press(tester, GameAction.down);
    }
    expect(position().pixels, greaterThan(0));
    for (var i = 0; i < 8; i++) {
      await press(tester, GameAction.up);
    }
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(of: find.byWidget(focused.widget), matching: find.byKey(const ValueKey('home-header'))),
      findsOneWidget,
    );
    expect(position().pixels, 0, reason: 'the whole header shows, not just its buttons');
  });

  testWidgets('an empty library says so', (tester) async {
    await pump(tester, [
      ...overrides(recent: const []),
      recentlyAddedProvider.overrideWith((ref) async => const []),
      favouriteGamesProvider.overrideWith((ref) async => const []),
      randomGameProvider.overrideWith((ref) async => null),
    ]);
    expect(find.textContaining('No games yet'), findsOneWidget);
  });

  testWidgets("shows the error with retry when RomM can't be reached", (tester) async {
    await pump(tester, [
      ...overrides(),
      recentlyPlayedProvider.overrideWith((ref) async => throw Exception('SocketException: connection refused')),
      recentlyAddedProvider.overrideWith((ref) async => throw Exception('SocketException: connection refused')),
      randomGameProvider.overrideWith((ref) async => null),
    ]);
    expect(find.textContaining("Can't reach RomM"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('with RomM down, the real shelves report it (not "No games yet")', (tester) async {
    await pump(tester, [
      libraryApiProvider.overrideWithValue(
        FakeLibraryApi(const [])..failWith = Exception('SocketException: connection refused'),
      ),
      collectionsProvider.overrideWith((ref) async => const []),
      rommOfflineProvider.overrideWithValue(false),
      gamesOnThisPcProvider.overrideWithValue(const []),
    ]);
    expect(find.textContaining("Can't reach RomM"), findsOneWidget);
    expect(find.textContaining('No games yet'), findsNothing);
  });

  test('HomeLayout: the default, moves, and a saved layout read back with rows it lacks added', () {
    final l = HomeLayout.standard;
    expect(l.top, HomeTop.lastPlayed);
    expect(l.shown, [
      HomeRow.playingNow,
      HomeRow.continuePlaying,
      HomeRow.recentlyAdded,
      HomeRow.favourites,
      HomeRow.onThisPc,
      HomeRow.platforms,
      HomeRow.collections,
    ]);
    final moved = l.moved(HomeRow.platforms, -1).moved(HomeRow.playingNow, -1);
    expect(moved.shown[4], HomeRow.platforms);
    expect(moved.shown.first, HomeRow.playingNow, reason: 'nothing past the top');
    final back = HomeLayout.fromJson({
      'top': 'randomPick',
      'widgets': ['library'],
      'rows': [
        {'row': 'forYou', 'on': true},
        {'row': 'favourites', 'on': false},
        {'row': 'somethingNewer', 'on': true},
      ],
    });
    expect(back.top, HomeTop.randomPick);
    expect(back.widgets, {HomeWidget.library});
    expect(back.rows.first, (HomeRow.playingNow, true), reason: 'a row it lacks goes where it is by default');
    final saved = [
      for (final (r, on) in back.rows)
        if (r == HomeRow.forYou || r == HomeRow.favourites) (r, on),
    ];
    expect(saved, [(HomeRow.forYou, true), (HomeRow.favourites, false)], reason: 'the saved order is kept');
    expect(back.rows.length, HomeRow.values.length);
    expect(HomeLayout.fromJson(back.toJson()).shown, back.shown);
  });

  test('On this day: the day, 29 February in a year without it, nothing on 1 January', () {
    expect(anniversaryDays(DateTime(2026, 10, 24)), ['10-24']);
    expect(anniversaryDays(DateTime(2026, 2, 28)), ['2-28', '2-29']);
    expect(anniversaryDays(DateTime(2028, 2, 28)), ['2-28']);
    expect(anniversaryDays(DateTime(2026, 1, 1)), isEmpty);
    Game g(DateTime d) => Game.fromJson({
      ...gameJson(1, 'X'),
      'metadatum': {'first_release_date': d.millisecondsSinceEpoch},
    });
    final today = DateTime(2026, 10, 24);
    expect(releasedOnDay(g(DateTime.utc(1998, 10, 24)), today), isTrue);
    expect(releasedOnDay(g(DateTime.utc(2026, 10, 24)), today), isFalse, reason: 'this year');
    expect(releasedOnDay(g(DateTime.utc(1998, 10, 23)), today), isFalse);
  });
}
