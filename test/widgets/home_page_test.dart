import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/pages/home_page.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  final overrides = [
    recentlyPlayedProvider.overrideWith((ref) async => [game(1, 'Okami')]),
    recentlyAddedProvider.overrideWith((ref) async => [game(2, 'Burnout 3'), game(3, 'Ico')]),
    favouriteGamesProvider.overrideWith((ref) async => [game(3, 'Ico')]),
    randomGameProvider.overrideWith((ref) async => game(4, 'Shadow of the Colossus')),
    favouriteIdsProvider.overrideWithValue({'3'}),
    gameProvider.overrideWith((ref, id) async => null),
    romSavesProvider.overrideWith((ref, id) async => const []),
    romStatesProvider.overrideWith((ref, id) async => const []),
    romNotesProvider.overrideWith((ref, id) async => const []),
  ];

  testWidgets('shows the welcome, the random pick and the shelves', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: overrides));
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Anna'), findsOneWidget);
    expect(find.text('Shadow of the Colossus'), findsWidgets);
    expect(find.text('Continue playing'), findsOneWidget);
    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Okami'), findsWidgets);
  });

  testWidgets('A on a game opens its page; B comes back', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: overrides));
    await tester.pumpAndSettle();
    await press(tester, GameAction.confirm);
    expect(find.byType(GameScreen), findsOneWidget);
    await press(tester, GameAction.back);
    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets('an empty library says so', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: [
      recentlyPlayedProvider.overrideWith((ref) async => const []),
      recentlyAddedProvider.overrideWith((ref) async => const []),
      favouriteGamesProvider.overrideWith((ref) async => const []),
      randomGameProvider.overrideWith((ref) async => null),
      favouriteIdsProvider.overrideWithValue(const {}),
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No games yet'), findsOneWidget);
  });

  testWidgets('shows the error with retry when RomM can\'t be reached', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: [
      recentlyPlayedProvider.overrideWith((ref) async => throw Exception('SocketException: connection refused')),
      recentlyAddedProvider.overrideWith((ref) async => throw Exception('SocketException: connection refused')),
      favouriteGamesProvider.overrideWith((ref) async => const []),
      randomGameProvider.overrideWith((ref) async => null),
      favouriteIdsProvider.overrideWithValue(const {}),
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining("Can't reach RomM"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('with RomM down, the real shelves report it (not "No games yet")', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: [
      libraryApiProvider.overrideWithValue(FakeLibraryApi(const [])..failWith = Exception('SocketException: connection refused')),
      collectionsProvider.overrideWith((ref) async => const []),
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining("Can't reach RomM"), findsOneWidget);
    expect(find.textContaining('No games yet'), findsNothing);
  });

  testWidgets('online, Installed games sits between Continue playing and Recently added', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: [
      ...overrides,
      rommOfflineProvider.overrideWithValue(false),
      gamesOnThisPcProvider.overrideWithValue([game(9, 'Rez'), game(8, 'Ico')]),
    ]));
    await tester.pumpAndSettle();
    final y = {for (final t in ['Continue playing', 'Installed games', 'Recently added']) t: tester.getTopLeft(find.text(t)).dy};
    expect(y['Continue playing']! < y['Installed games']!, isTrue);
    expect(y['Installed games']! < y['Recently added']!, isTrue);
    expect(find.text('Rez'), findsWidgets);
  });

  testWidgets('with nothing installed there is no Installed games shelf', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: [
      ...overrides,
      rommOfflineProvider.overrideWithValue(false),
      gamesOnThisPcProvider.overrideWithValue(const []),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Installed games'), findsNothing);
    expect(find.text('Continue playing'), findsOneWidget);
  });

  testWidgets('offline, Installed games comes first, has the focus, and still plays', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const HomePage(name: 'Anna'), overrides: [
      ...overrides,
      rommOfflineProvider.overrideWithValue(true),
      gamesOnThisPcProvider.overrideWithValue([game(9, 'Rez')]),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Installed games'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Installed games')).dy < tester.getTopLeft(find.text('Continue playing')).dy, isTrue);
    await press(tester, GameAction.confirm);
    expect(tester.widget<GameScreen>(find.byType(GameScreen)).game.name, 'Rez', reason: 'A opens the focused game');
  });
}
