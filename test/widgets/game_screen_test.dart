import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/widgets/game_transition.dart';
import 'package:gargosy/ui/widgets/hint_bar.dart';
import 'package:gargosy/ui/widgets/g_focusable.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_play_sessions.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/disk_space.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/download_providers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/core/save/catalog/save_catalog.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/play/play_time.dart';
import 'package:gargosy/play/play_menu.dart';
import 'package:gargosy/ui/screens/play/play_screen.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';
import 'package:gargosy/ui/screens/game/overview_tab.dart';
import 'package:gargosy/ui/screens/game/game_cover_column.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/fake_download_service.dart';
import 'play_screen_test.dart' show gamePageCoverOffset;
import '../unit/play_controller_test.dart' show FakeEngine;
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';
import '../helpers/fake_disk.dart';

void main() {
  late AppRoot root;
  late FakeDownloadService downloads;
  late FakeEngine engine;

  final burnout = Game.fromJson({
    ...gameJson(7564, 'Burnout 3: Takedown', fsName: 'Burnout 3 (USA).chd'),
    'summary': 'Crash your rivals.',
    'metadatum': {
      'genres': ['Racing'],
      'first_release_date': 1094428800000,
    },
    'regions': ['USA'],
  });

  final opened = <String>[];
  var gameReads = 0;
  Game? fresh;

  Future<void> pump(
    WidgetTester tester, {
    Set<String> favourites = const {},
    PlayMenu? menu,
    List<ResumeEntry> states = const [],
    bool downloaded = false,
    List<Override> extra = const [],
  }) async {
    await setDesktopSize(tester);
    root = (await tester.runAsync(tempAppRoot))!;
    final mine = root.root;
    addTearDown(() => io.Directory(mine).deleteSync(recursive: true));
    downloads = FakeDownloadService(RomFiles(root), PathGuard(root));
    engine = FakeEngine()
      ..menu =
          menu ??
          const PlayMenu(
            emulators: [EmulatorOption(SaveMaker('pcsx2'), 'PCSX2')],
            platformDefault: SaveMaker('pcsx2'),
            catalog: SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false),
          )
      ..states = states;
    opened.clear();
    gameReads = 0;
    if (downloaded) {
      io.File(RomFiles(root).pathFor(burnout))
        ..createSync(recursive: true)
        ..writeAsStringSync('rom');
    }
    await tester.pumpWidget(
      testApp(
        GameScreen(game: burnout),
        root: root,
        overrides: [
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          gameProvider.overrideWith((ref, id) async {
            gameReads++;
            return fresh ?? burnout;
          }),
          favouriteIdsProvider.overrideWithValue(favourites),
          downloadServiceProvider.overrideWithValue(downloads),
          playEngineProvider.overrideWithValue(engine),
          folderOpenerProvider.overrideWithValue(opened.add),
          romSavesProvider.overrideWith(
            (ref, id) async => [
              {'id': 1, 'file_name': 'burnout.ps2', 'emulator': 'pcsx2'},
            ],
          ),
          romStatesProvider.overrideWith((ref, id) async => const []),
          romNotesProvider.overrideWith((ref, id) async => const []),
          raProgressionProvider.overrideWith((ref) async => const {}),
          ...extra,
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title, platform, year and the Overview', (tester) async {
    await pump(tester);
    expect(
      find.text('Burnout 3: Takedown'),
      findsWidgets,
    ); // the title, and the cover's placeholder art (no server in tests)
    expect(find.textContaining('PlayStation 2'), findsWidgets);
    expect(find.textContaining('2004'), findsWidgets);
    expect(find.text('Crash your rivals.'), findsOneWidget);
    expect(find.text('Racing'), findsOneWidget);
  });

  testWidgets('RB and LB walk the tabs; Details lists the file', (tester) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await press(tester, GameAction.r1);
    }
    expect(find.text('Burnout 3 (USA).chd'), findsOneWidget);
    await press(tester, GameAction.r1); // stays on the last tab
    expect(find.text('Burnout 3 (USA).chd'), findsOneWidget);
    await press(tester, GameAction.l1);
    await press(tester, GameAction.l1);
    await press(tester, GameAction.l1);
    await press(tester, GameAction.l1);
    expect(find.text('Crash your rivals.'), findsOneWidget);
  });

  testWidgets('Download puts the ROM in roms\\, then Delete removes it after asking', (tester) async {
    await pump(tester);
    expect(find.textContaining('Download'), findsOneWidget);
    await press(tester, GameAction.confirm); // Download has focus
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(downloads.started, ['7564']);
    expect(RomFiles(root).isDownloaded(burnout), isTrue);
    expect(find.text('Delete from this PC…'), findsNothing, reason: 'it is in the ⋯ menu');
    await tester.tap(find.byKey(const ValueKey('game-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from this PC…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete Burnout 3: Takedown from this PC?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(RomFiles(root).isDownloaded(burnout), isFalse);
  });

  testWidgets("Download says the drive's free space when it is tight (#142)", (tester) async {
    await pump(tester, extra: [diskInfoProvider.overrideWithValue(FakeDisk((_) => burnout.fileSize + spaceHeadroom))]);
    expect(find.byKey(const ValueKey('free-space')), findsOneWidget);
    await pump(tester, extra: [diskInfoProvider.overrideWithValue(FakeDisk((_) => 1 << 50))]);
    expect(find.byKey(const ValueKey('free-space')), findsNothing);
  });

  testWidgets('behind another download it is Queued, and can be taken out of the queue (#143)', (tester) async {
    await pump(tester);
    downloads.holds['1'] = Completer<void>();
    final c = ProviderScope.containerOf(tester.element(find.byType(GameScreen)));
    unawaited(c.read(downloadsProvider.notifier).start(game(1, 'Okami')));
    await tester.pump();
    await press(tester, GameAction.confirm); // Download
    expect(find.text('Queued'), findsOneWidget);
    await tester.tap(find.text('Remove from the queue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Download'), findsOneWidget);
    expect(c.read(downloadsProvider).containsKey('7564'), isFalse);
    downloads.holds['1']!.complete();
  });

  testWidgets('the Overview says how long it was played (#146)', (tester) async {
    await pump(
      tester,
      extra: [playTimeProvider.overrideWith((ref, id) async => const PlayTime(Duration(hours: 12, minutes: 40), 8))],
    );
    expect(find.textContaining('Played 12 h 40 min · 8 sessions'), findsOneWidget);
  });

  testWidgets('a favourite shows a filled heart', (tester) async {
    await pump(tester, favourites: {'7564'});
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('while unpacking there is no Cancel (it could not stop the unzip)', (tester) async {
    await pump(tester);
    downloads.hold = Completer<void>();
    downloads.holdIn = DownloadPhase.extracting;
    await press(tester, GameAction.confirm);
    expect(find.text('Unpacking…'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    downloads.hold!.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  });

  testWidgets('LB/RB keep working after switching tabs from inside a tab', (tester) async {
    await pump(tester);
    await press(tester, GameAction.r1); // Saves
    Focus.of(tester.element(find.text('Upload to RomM'))).requestFocus();
    await tester.pumpAndSettle();
    await press(tester, GameAction.r1); // Achievements
    await press(tester, GameAction.r1); // Notes
    expect(find.text('Add a note'), findsOneWidget);
  });

  testWidgets('once downloaded, Play opens the play screen; Start plays and the page shows it is playing', (
    tester,
  ) async {
    await pump(tester);
    engine.menu = const PlayMenu(
      emulators: [EmulatorOption(SaveMaker('pcsx2'), 'PCSX2')],
      platformDefault: SaveMaker('pcsx2'),
      catalog: SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false),
    );
    await press(tester, GameAction.confirm); // Download
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsOneWidget);
    expect(engine.steps, isEmpty);
    await tester.tap(find.byKey(const ValueKey('play-start')));
    await tester.pumpAndSettle();
    expect(engine.steps, ['states', 'prepare', 'launch']);
    expect(find.byType(PlayScreen), findsNothing);
    expect(find.text('Playing…'), findsOneWidget);
    engine.running!.complete(const PlayResult('Save synced to RomM.'));
    await tester.pumpAndSettle();
    expect(find.text('Save synced to RomM.'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('the cover column: the cover is 240 × 324; Play, ♥ and ⋯; Delete is in ⋯, in red, last', (tester) async {
    await pump(tester, downloaded: true);
    expect(tester.getSize(find.byKey(const ValueKey('game-cover'))), const Size(240, 324));
    expect(find.text('Play'), findsOneWidget);
    expect(find.byKey(const ValueKey('game-fav')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game-more')));
    await tester.pumpAndSettle();
    final items = ["Open the game's folder", 'Sync save states now', 'Delete from this PC…'];
    for (final i in items) {
      expect(find.text(i), findsOneWidget, reason: i);
    }
    expect(
      tester.getTopLeft(find.text('Delete from this PC…')).dy,
      greaterThan(tester.getTopLeft(find.text("Open the game's folder")).dy),
    );
    await tester.tap(find.text("Open the game's folder"));
    await tester.pumpAndSettle();
    expect(opened.single, contains('ps2'));
  });

  group('Delete from RomM', () {
    late FakeDioAdapter server;

    Future<void> pumpDeletable(WidgetTester tester, {required bool allowed, int status = 200}) {
      server = FakeDioAdapter(
        (_) => (status: status, body: status == 200 ? {'successful_items': 1, 'failed_items': 0} : {}),
      );
      final romm = RommService(
        RomMConfig(baseUrl: 'https://romm.example', username: '', password: '', apiKey: 't'),
        dio: fakeDio(server),
        skipConnectivityCheck: true,
      );
      return pump(
        tester,
        downloaded: true,
        extra: [
          canDeleteGamesProvider.overrideWith((ref) async => allowed),
          rommServiceProvider.overrideWithValue(romm),
          // Only the delete is asked of this server.
          playSessionsApiProvider.overrideWithValue(null),
          similarGamesProvider.overrideWith((ref, id) async => const []),
        ],
      );
    }

    Future<void> openPrompt(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('game-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from RomM…'));
      await tester.pumpAndSettle();
    }

    testWidgets('⋯ offers it only to a RomM user who may delete games, last, after Delete from this PC', (
      tester,
    ) async {
      await pumpDeletable(tester, allowed: true);
      await tester.tap(find.byKey(const ValueKey('game-more')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Delete from RomM…')).dy,
        greaterThan(tester.getTopLeft(find.text('Delete from this PC…')).dy),
      );
    });

    testWidgets('not for a RomM user who may not delete games', (tester) async {
      await pumpDeletable(tester, allowed: false);
      await tester.tap(find.byKey(const ValueKey('game-more')));
      await tester.pumpAndSettle();
      expect(find.text('Delete from this PC…'), findsOneWidget);
      expect(find.text('Delete from RomM…'), findsNothing);
    });

    testWidgets('the prompt: permanent, Cancel focused, a press of Delete does nothing, holding it deletes', (
      tester,
    ) async {
      await pumpDeletable(tester, allowed: true);
      await openPrompt(tester);
      expect(find.text('Delete Burnout 3: Takedown from RomM?'), findsOneWidget);
      expect(find.textContaining('permanent'), findsOneWidget);
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.ancestor(of: find.byWidget(focused.widget), matching: find.byKey(const ValueKey('delete-cancel'))),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(server.requests, isEmpty, reason: 'a press is not a hold');
      expect(find.byKey(const ValueKey('delete-confirm')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('delete-server-file'))); // off
      await tester.pump();
      await tester.longPress(find.byKey(const ValueKey('delete-confirm')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(server.requests.single.data, {
        'roms': [7564],
        'delete_from_fs': <int>[],
      });
      expect(io.File(RomFiles(root).pathFor(burnout)).existsSync(), isFalse, reason: 'this PC ticked');
      expect(find.text('Deleted Burnout 3: Takedown from RomM.'), findsOneWidget);
    });

    testWidgets('B cancels; this PC unticked keeps the copy', (tester) async {
      await pumpDeletable(tester, allowed: true);
      await openPrompt(tester);
      await press(tester, GameAction.back);
      expect(find.byKey(const ValueKey('delete-confirm')), findsNothing);
      expect(server.requests, isEmpty);

      await openPrompt(tester);
      await tester.tap(find.byKey(const ValueKey('delete-this-pc')));
      await tester.pump();
      await tester.longPress(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(server.requests.single.data, {
        'roms': [7564],
        'delete_from_fs': [7564],
      });
      expect(io.File(RomFiles(root).pathFor(burnout)).existsSync(), isTrue);
    });

    testWidgets('RomM refuses: says to sign in again, and nothing is deleted here', (tester) async {
      await pumpDeletable(tester, allowed: true, status: 403);
      await openPrompt(tester);
      await tester.longPress(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text("RomM didn't allow it"), findsOneWidget);
      expect(find.textContaining('Sign in again'), findsOneWidget);
      expect(io.File(RomFiles(root).pathFor(burnout)).existsSync(), isTrue);
    });
  });

  testWidgets('⋯ offers Forget "Always in PCSX2" only when one is remembered', (tester) async {
    await pump(tester, downloaded: true);
    await tester.tap(find.byKey(const ValueKey('game-more')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Forget'), findsNothing);
    await press(tester, GameAction.back);
    await pump(
      tester,
      downloaded: true,
      menu: const PlayMenu(
        emulators: [EmulatorOption(SaveMaker('pcsx2'), 'PCSX2')],
        remembered: SaveMaker('pcsx2'),
        platformDefault: SaveMaker('pcsx2'),
        catalog: SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('game-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget "Always in PCSX2"'));
    await tester.pumpAndSettle();
    expect(engine.remembered['7564'], isNull);
    expect(engine.remembered.containsKey('7564'), isTrue);
  });

  testWidgets('⋯ Sync save states now only when state sync is on; it says what moved', (tester) async {
    await pump(tester, downloaded: true);
    engine.stateSyncOn = false;
    await tester.tap(find.byKey(const ValueKey('game-more')));
    await tester.pumpAndSettle();
    expect(find.text('Sync save states now'), findsNothing);
    await press(tester, GameAction.back);
    await tester.pumpAndSettle();
    engine.stateSyncOn = true;
    await tester.tap(find.byKey(const ValueKey('game-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync save states now'));
    await tester.pumpAndSettle();
    expect(find.text('1 state down, 0 up'), findsOneWidget);
  });

  testWidgets('♥ toggles favourite', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('game-fav')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('Y resumes the newest save state', (tester) async {
    await pump(
      tester,
      downloaded: true,
      states: [
        ResumeEntry(
          emulatorId: 'pcsx2',
          emulatorName: 'PCSX2',
          fileName: 'auto.p2s',
          slot: const AutoStateSlot(),
          savedAt: DateTime(2026, 10, 9),
          where: ResumeWhere.thisPc,
        ),
      ],
    );
    await press(tester, GameAction.favorite);
    expect(engine.steps, containsAllInOrder(['check', 'launch']));
  });

  testWidgets("Y skips a state the emulator can't start in, even a newer one", (tester) async {
    await pump(
      tester,
      downloaded: true,
      states: [
        ResumeEntry(
          emulatorId: 'pcsx2',
          emulatorName: 'PCSX2',
          fileName: 'auto.p2s',
          slot: const AutoStateSlot(),
          savedAt: DateTime(2026, 10, 9),
          where: ResumeWhere.thisPc,
        ),
        ResumeEntry(
          emulatorId: 'azahar',
          emulatorName: 'Azahar',
          fileName: 'x.01.cst',
          slot: const NumberedStateSlot(1),
          savedAt: DateTime(2026, 10, 10),
          where: ResumeWhere.thisPc,
          resumable: false,
        ),
      ],
    );
    await press(tester, GameAction.favorite);
    expect(engine.steps, containsAllInOrder(['check', 'launch']));
    expect(engine.resumed?.fileName, 'auto.p2s');
  });

  testWidgets('tab badges: the number of saves, achievements earned/total, notes', (tester) async {
    await pump(
      tester,
      menu: PlayMenu(
        emulators: const [EmulatorOption(SaveMaker('pcsx2'), 'PCSX2')],
        platformDefault: const SaveMaker('pcsx2'),
        catalog: SaveCatalog(
          thisPc: const [],
          backups: const [],
          rommOffline: false,
          romm: [
            RommSaveGroup(
              slot: 's',
              tag: 'pcsx2',
              newest: SaveEntry(
                source: SaveSource.romm,
                fileName: 'a',
                savedAt: DateTime(2026),
                maker: const SaveMaker('pcsx2'),
                tag: 'pcsx2',
                slot: 's',
              ),
              older: [
                SaveEntry(
                  source: SaveSource.romm,
                  fileName: 'b',
                  savedAt: DateTime(2025),
                  maker: const SaveMaker('pcsx2'),
                  tag: 'pcsx2',
                  slot: 's',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.descendant(of: find.byKey(const ValueKey('tab-badge-1')), matching: find.text('2')), findsOneWidget);
  });

  testWidgets('the Saves badge counts a save once, wherever its copies are', (tester) async {
    final t = DateTime(2026, 10, 16);
    SaveEntry romm(String id, String hash) => SaveEntry(
      source: SaveSource.romm,
      fileName: id,
      savedAt: t,
      maker: const SaveMaker('pcsx2'),
      tag: 'pcsx2',
      slot: 'autosave',
      rommSave: {'id': id, 'content_hash': hash},
    );
    await pump(
      tester,
      menu: PlayMenu(
        emulators: const [EmulatorOption(SaveMaker('pcsx2'), 'PCSX2')],
        platformDefault: const SaveMaker('pcsx2'),
        catalog: SaveCatalog(
          thisPc: [
            SaveEntry(
              source: SaveSource.local,
              fileName: 'l',
              savedAt: t,
              maker: const SaveMaker('pcsx2'),
              contentHashes: const {'h'},
            ),
          ],
          backups: [
            SaveEntry(
              source: SaveSource.backup,
              fileName: 'b.zip',
              savedAt: t,
              maker: const SaveMaker('pcsx2'),
              contentHashes: const {'h'},
            ),
          ],
          rommOffline: false,
          romm: [
            RommSaveGroup(slot: 'autosave', tag: 'pcsx2', newest: romm('9', 'h'), older: [romm('8', 'old')]),
          ],
        ),
      ),
    );
    // The same save on this PC, in a backup and on RomM, and an older one on RomM.
    expect(find.descendant(of: find.byKey(const ValueKey('tab-badge-1')), matching: find.text('2')), findsOneWidget);
  });

  testWidgets('the pills write status, rating and completion', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('pill-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finished'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pill-rating')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pill-completion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('40 %').last);
    await tester.pumpAndSettle();
    expect(engine.rommUserCalls, [
      {'status': 'finished'},
      {'rating': 8},
      {'completion': 40},
    ]);
    expect(
      find.descendant(of: find.byKey(const ValueKey('pill-status')), matching: find.text('Finished')),
      findsOneWidget,
    );
  });

  testWidgets('a refused rating goes back and says why', (tester) async {
    await pump(tester);
    engine.rommUserOk = false;
    await tester.tap(find.byKey(const ValueKey('pill-rating')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const ValueKey('pill-rating')), matching: find.textContaining('8')),
      findsNothing,
    );
    expect(find.textContaining("RomM didn't save"), findsOneWidget);
  });

  testWidgets('Overview says when the game was last played', (tester) async {
    await pump(tester);
    expect(find.text('LAST PLAYED'), findsNothing);
  });

  testWidgets('Overview: last played, from RomM', (tester) async {
    final played = Game.fromJson({
      ...gameJson(7564, 'Burnout 3: Takedown', fsName: 'Burnout 3 (USA).chd'),
      'rom_user': {'last_played': '2026-10-01T18:40:00Z'},
    });
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(OverviewTab(game: played)));
    await tester.pumpAndSettle();
    expect(find.text('LAST PLAYED'), findsOneWidget);
    expect(find.textContaining('1 Oct'), findsOneWidget);
  });

  testWidgets('Y on a state older than the newest save asks first; Cancel starts nothing', (tester) async {
    await pump(
      tester,
      downloaded: true,
      menu: PlayMenu(
        emulators: const [EmulatorOption(SaveMaker('pcsx2'), 'PCSX2')],
        platformDefault: const SaveMaker('pcsx2'),
        catalog: SaveCatalog(
          thisPc: const [],
          backups: const [],
          rommOffline: false,
          romm: [
            RommSaveGroup(
              slot: 's',
              tag: 'pcsx2',
              newest: SaveEntry(
                source: SaveSource.romm,
                fileName: 'wed.ps2',
                savedAt: DateTime(2026, 10, 8),
                maker: const SaveMaker('pcsx2'),
                tag: 'pcsx2',
                slot: 's',
              ),
              older: const [],
            ),
          ],
        ),
      ),
      states: [
        ResumeEntry(
          emulatorId: 'pcsx2',
          emulatorName: 'PCSX2',
          fileName: 'mon.p2s',
          slot: const AutoStateSlot(),
          savedAt: DateTime(2026, 10, 6),
          where: ResumeWhere.thisPc,
        ),
      ],
    );
    await press(tester, GameAction.favorite);
    expect(find.text('Resume an older state?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(engine.steps, isNot(contains('launch')));
  });

  testWidgets("the pills show RomM's values once the game's details arrive", (tester) async {
    fresh = Game.fromJson({
      ...gameJson(7564, 'Burnout 3: Takedown', fsName: 'Burnout 3 (USA).chd'),
      'rom_user': {'status': 'finished', 'rating': 7},
    });
    addTearDown(() => fresh = null);
    await pump(tester);
    expect(
      find.descendant(of: find.byKey(const ValueKey('pill-status')), matching: find.text('Finished')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('pill-rating')), matching: find.text('7 / 10')),
      findsOneWidget,
    );
  });

  testWidgets('a pill change that RomM took reads the game again (no stale value next time)', (tester) async {
    await pump(tester);
    final before = gameReads;
    await tester.tap(find.byKey(const ValueKey('pill-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finished'));
    await tester.pumpAndSettle();
    expect(gameReads, greaterThan(before));
  });

  testWidgets("the game page's cover sits where the play screen's does", (tester) async {
    await pump(tester);
    expect(tester.getTopLeft(find.byKey(const ValueKey('game-cover'))), gamePageCoverOffset);
  });

  testWidgets('Play fades to the play screen: the cover stays put and the same art is behind', (tester) async {
    await pump(tester);
    engine.menu = const PlayMenu(
      emulators: [EmulatorOption(SaveMaker('pcsx2'), 'PCSX2')],
      platformDefault: SaveMaker('pcsx2'),
      catalog: SaveCatalog(thisPc: [], backups: [], romm: [], rommOffline: false),
    );
    await press(tester, GameAction.confirm); // Download
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // halfway
    expect(tester.getTopLeft(find.byKey(const ValueKey('play-cover'))), gamePageCoverOffset);
    expect(tester.getTopLeft(find.text(burnout.displayName).last).dx, greaterThan(gamePageCoverOffset.dx + 240));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(PlayScreen), matching: find.byType(GameArtBackdrop)), findsOneWidget);
  });

  testWidgets('Back is at the bottom of the cover column, as wide as Play, outlined, clear of the hints', (
    tester,
  ) async {
    await pump(tester, downloaded: true);
    final play = tester.getRect(find.ancestor(of: find.text('Play'), matching: find.byType(GFocusable)).first);
    final back = tester.getRect(find.byKey(const ValueKey('game-back')));
    expect(back.width, play.width);
    expect(back.top, greaterThan(play.bottom));
    expect(back.bottom, lessThanOrEqualTo(tester.getRect(find.byType(HintBar)).top));
    final boxes = tester
        .widgetList<Container>(
          find.descendant(of: find.byKey(const ValueKey('game-back')), matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    expect(boxes.any((d) => d.border != null && d.color == null), isTrue, reason: 'outlined, not filled');

    // Opened from somewhere, Back goes there.
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => GameScreen(game: burnout)));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game-back')));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('game-back')), findsOneWidget);
  });
}
