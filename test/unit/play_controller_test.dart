import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:gargosy/core/input/held_combo.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/library/xbox_disc.dart';
import 'package:gargosy/core/save/catalog/play_request.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/profiles/age_limit.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/play/play_menu.dart';
import 'package:gargosy/play/quit_combo.dart';
import 'package:gargosy/play/session_achievements.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/retroachievements/ra_account.dart';
import 'package:gargosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:gargosy/core/retroachievements/retroachievements_game_models.dart';

import '../helpers/fake_secret_store.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

/// RomM's RA progress: nothing earned before the session, one after.
class _Progress implements AchievementProgress {
  int reads = 0;
  @override
  Future<Map<int, Map<String, dynamic>>?> progression() async => {
    if (reads++ > 0)
      77: {
        'earned_achievements': [
          {'id': 'b1', 'date': '2026-10-27'},
        ],
      },
  };
  @override
  Future<bool> refresh(int userId) async => true;
}

class _Strategy extends Fake implements EmulatorStrategy {
  _Strategy([this.emulatorId = 'pcsx2']);
  @override
  final String emulatorId;
  @override
  String get name => emulatorId == 'pcsx2' ? 'PCSX2' : emulatorId;
}

class FakeEngine implements PlayEngine {
  bool installed = true;
  bool downloaded = true;
  final steps = <String>[];
  Completer<PlayResult>? running;
  PlayMenu? menu;
  PlayRequest? request;
  String? launchedIn;
  String? coreOverride;
  final remembered = <String, String?>{};
  final fullscreen = <String, bool>{};

  /// Whether the session can be closed (#141), and how often it was.
  bool closable = false;
  int closes = 0;

  /// How many closes fail before one works (#235's retry).
  int closeFails = 0;
  bool returnsAfterExit = false;

  @override
  Future<void> setFullscreen(String emulatorId, bool on) async => fullscreen[emulatorId] = on;

  int menuReads = 0;
  bool failDelete = false;
  bool rommUserOk = true;
  bool stateSyncOn = true;
  final rommUserCalls = <Map<String, Object?>>[];

  Object? menuError;

  @override
  Future<PlayMenu?> menuFor(Game game) async {
    menuReads++;
    if (menuError != null) throw menuError!;
    return menu;
  }

  @override
  Future<void> restore(Game game, SaveEntry save, SaveMaker target) async => steps.add('restore');

  @override
  Future<void> deleteSave(Game game, SaveEntry save) async {
    if (failDelete) throw StateError('RomM refused');
    steps.add('delete');
  }

  @override
  Future<bool> upload(Game game, SaveMaker who) async {
    steps.add('upload');
    return true;
  }

  @override
  Future<void> backUpNow(Game game, SaveMaker who) async => steps.add('backup');

  /// The unclaimed saves on the shared volume; a claim takes one off.
  List<String> unclaimed = [];
  bool claimUploads = true;

  @override
  Future<List<String>> unclaimedSaves(Game game, SaveMaker who) async => unclaimed;

  @override
  Future<bool> claimSave(Game game, SaveMaker who, String name) async {
    steps.add('claim $name');
    unclaimed = [
      for (final n in unclaimed)
        if (n != name) n,
    ];
    return claimUploads;
  }

  @override
  bool stateSyncAvailable(Game game) => stateSyncOn;

  @override
  Future<String> syncStatesNow(Game game) async {
    steps.add('sync states');
    return '1 state down, 0 up';
  }

  @override
  Future<bool> setRommUser(
    Game game, {
    String? status,
    int? rating,
    int? completion,
    bool? backlogged,
    bool? nowPlaying,
  }) async {
    rommUserCalls.add({
      'status': ?status,
      'rating': ?rating,
      'completion': ?completion,
      'backlogged': ?backlogged,
      'nowPlaying': ?nowPlaying,
    });
    return rommUserOk;
  }

  @override
  Future<EmulatorStrategy?> emulatorFor(Game game, {String? emulatorId}) async => _Strategy(emulatorId ?? 'pcsx2');
  @override
  Future<void> remember(Game game, PlayRequest request) async {
    if (request.remember) remembered[game.id] = request.emulator.emulatorId;
    if (request.forget) remembered[game.id] = null;
  }

  @override
  Future<bool> isInstalled(EmulatorStrategy s) async => installed;

  /// What readyRom returns (the unpacked ROM), its progress line, a gate it
  /// waits on, and what it throws.
  String? readyPath;
  String? readyProgress;
  Completer<void>? readyGate;
  Object? readyError;
  String? readiedFor;
  String? launchedRom;

  @override
  Future<String> readyRom(Game game, String romPath, EmulatorStrategy s, {void Function(String)? onProgress}) async {
    readiedFor = s.emulatorId;
    if (readyProgress != null) onProgress?.call(readyProgress!);
    await readyGate?.future;
    if (readyError != null) throw readyError!;
    return readyPath ?? romPath;
  }

  /// What [whyNotIn] says (null: it can be played).
  String? whyNot;

  @override
  Future<String?> whyNotIn(Game game, String romPath, EmulatorStrategy strategy) async => whyNot;

  @override
  Future<String?> romPathFor(Game game) async {
    await Future<void>.delayed(Duration.zero); // lists a folder
    return downloaded ? r'D:\G\roms\ps2\g.chd' : null;
  }

  String? problem;
  @override
  Future<void> prepare(
    Game game,
    String romPath,
    EmulatorStrategy s, {
    PlayRequest? request,
    String? coreOverride,
    void Function(String)? onProblem,
  }) async {
    steps.add('prepare');
    this.request = request;
    if (problem != null) onProblem?.call(problem!);
  }

  ResumeCheck check = const ResumeReady(r'D:\G\states\auto.p2s');
  StatePull statePull = const StatePull();
  String? loadStatePath;
  List<ResumeEntry> states = const [];

  @override
  Stream<List<ResumeEntry>> statesFor(Game game) => Stream.value(states);
  @override
  Future<StatePull> pullStates(
    Game game,
    String romPath,
    EmulatorStrategy s, {
    String? priority,
    String? coreOverride,
    void Function(String)? onProblem,
  }) async {
    steps.add('states');
    pulledCore = coreOverride;
    return statePull;
  }

  /// The core the last state pull was for.
  String? pulledCore;

  /// The state the last resume checked.
  ResumeEntry? resumed;

  @override
  Future<ResumeCheck> checkResume(ResumeEntry entry, Game game, String romPath, StatePull pull) async {
    steps.add('check');
    resumed = entry;
    return check;
  }

  @override
  Future<String?> deleteState(Game game, ResumeEntry entry) async {
    steps.add('delete state ${entry.fileName}');
    return null;
  }

  /// Another player's state: where it was put, or null to fail.
  String? sharedPath = '/temp/shared-state';

  @override
  Future<String> takeSharedState(ResumeEntry entry, Game game, String romPath, EmulatorStrategy strategy) async {
    steps.add('take ${entry.fileName}');
    resumed = entry;
    return sharedPath ?? (throw StateError('every slot is in use'));
  }

  /// The core the next launch says is missing (once).
  String? missingCore;
  bool coreDownloadFails = false;

  @override
  Future<void> installCore(EmulatorStrategy s, MissingRetroArchCoreException missing) async {
    steps.add('core ${missing.coreName}');
    if (coreDownloadFails) throw StateError("The ${missing.coreName} core couldn't be downloaded");
  }

  @override
  Future<PlaySession> launch(
    Game game,
    String romPath,
    EmulatorStrategy s, {
    String? coreOverride,
    String? loadStatePath,
    void Function(CloseGame close)? onStarted,
  }) async {
    final missing = missingCore;
    if (missing != null) {
      missingCore = null;
      steps.add('launch (no core)');
      throw MissingRetroArchCoreException(
        coreName: missing,
        corePath: r'D:\G\emulators\retroarch\cores\' + missing,
        exePath: 'ra.exe',
      );
    }
    steps.add('launch');
    launchedRom = romPath;
    this.loadStatePath = loadStatePath;
    launchedIn = s.emulatorId;
    this.coreOverride = coreOverride;
    running = Completer<PlayResult>();
    if (closable) {
      onStarted?.call(() async {
        closes++;
        if (closeFails > 0) {
          closeFails--;
          throw StateError('the emulator went on');
        }
        running!.complete(const PlayResult('The game ended.'));
      });
    }
    // As the copied launch does: it returns once the emulator has exited.
    if (returnsAfterExit) await running!.future;
    return PlaySession(running!.future);
  }

  /// The emulator opened on its own, and how to close it.
  String? opened;
  void Function()? closeOpened;
  bool openFails = false;

  @override
  Future<void> openEmulator(String emulatorId, String exePath, {required void Function() onExit}) async {
    if (openFails) throw StateError('no exe');
    opened = '$emulatorId $exePath';
    closeOpened = onExit;
  }
}

/// Select + LB + RB held on one controller.
const _quit = HeldButtons('p1', {PadButton.select, PadButton.l1, PadButton.r1});

void main() {
  late FakeEngine engine;
  late ProviderContainer c;
  setUp(() {
    engine = FakeEngine();
    c = ProviderContainer(overrides: [playEngineProvider.overrideWithValue(engine)]);
  });
  tearDown(() => c.dispose());

  test('pulls the save, then launches; while it runs the game is marked running', () async {
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), isNull);
    expect(engine.steps, ['states', 'prepare', 'launch']);
    expect(c.read(playControllerProvider).runningGameId, '1');
    engine.running!.complete(const PlayResult('Save synced'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playControllerProvider).runningGameId, isNull);
    expect(c.read(playControllerProvider).message, 'Save synced');
  });

  test("after the session's message, what it earned on RetroAchievements (#189)", () async {
    final progress = _Progress();
    final prefs = MemoryPrefs()..values[kRaUsernameKey] = 'henrik';
    final c = ProviderContainer(
      overrides: [
        playEngineProvider.overrideWithValue(engine),
        achievementProgressProvider.overrideWithValue(progress),
        rommUserIdProvider.overrideWithValue(7),
        raAccountProvider.overrideWithValue(
          RaAccount(prefs, secrets: FakeSecretStore(), fetchToken: (u, p) async => (username: u, token: 't')),
        ),
      ],
    );
    addTearDown(c.dispose);
    final sonic = Game.fromJson({
      ...gameJson(9, 'Sonic'),
      'ra_id': 77,
      'merged_ra_metadata': {
        'achievements': [
          const RetroAchievement(id: 1, title: 'Rings', description: '', points: 5, badgeName: 'b1').toRommJson(),
        ],
      },
    });
    expect(await c.read(playControllerProvider.notifier).play(sonic), isNull);
    expect(progress.reads, 1, reason: 'read before the emulator starts');
    engine.running!.complete(const PlayResult('Save synced'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playControllerProvider).message, 'Save synced', reason: 'the save message comes first');
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.read(sessionAchievementsProvider)?.line, '1 achievement earned · 5 points (softcore)');
  });

  group('the quit buttons held (#141)', () {
    void playing(FakeAsync async, ProviderContainer c) {
      engine.closable = true;
      c.read(playControllerProvider.notifier).play(game(1, 'G'));
      async.elapse(Duration.zero);
      expect(engine.steps, ['states', 'prepare', 'launch']);
      expect(c.read(playControllerProvider).runningGameId, '1');
    }

    test('for 1 second closes the emulator; the session ends as usual', () {
      fakeAsync((async) {
        final c = ProviderContainer(
          overrides: [
            playEngineProvider.overrideWithValue(engine),
            quitButtonsProvider.overrideWithValue(QuitButtons.selectBumpers),
          ],
        );
        playing(async, c);
        heldButtons.add(_quit);
        async.elapse(const Duration(milliseconds: 900));
        expect(engine.closes, 0);
        async.elapse(const Duration(milliseconds: 200));
        expect(engine.closes, 1);
        expect(c.read(playControllerProvider).runningGameId, isNull);
        expect(c.read(playControllerProvider).message, 'The game ended.');
        c.dispose();
      });
    });

    test('the launch returns only after the emulator exits: held still closes it', () {
      fakeAsync((async) {
        engine.returnsAfterExit = true;
        final c = ProviderContainer(
          overrides: [
            playEngineProvider.overrideWithValue(engine),
            quitButtonsProvider.overrideWithValue(QuitButtons.selectBumpers),
          ],
        );
        playing(async, c);
        heldButtons.add(_quit);
        async.elapse(const Duration(seconds: 3));
        expect(engine.closes, 1);
        async.elapse(Duration.zero);
        expect(c.read(playControllerProvider).runningGameId, isNull);
        c.dispose();
      });
    });

    test('let go too soon, or turned off in Settings: nothing closes', () {
      fakeAsync((async) {
        final c = ProviderContainer(
          overrides: [
            playEngineProvider.overrideWithValue(engine),
            quitButtonsProvider.overrideWithValue(QuitButtons.selectBumpers),
          ],
        );
        playing(async, c);
        heldButtons.add(_quit);
        async.elapse(const Duration(milliseconds: 500));
        heldButtons.add(const HeldButtons('p1', {PadButton.select}));
        async.elapse(const Duration(seconds: 5));
        expect(engine.closes, 0);
        c.dispose();
      });
      engine = FakeEngine();
      fakeAsync((async) {
        final c = ProviderContainer(
          overrides: [playEngineProvider.overrideWithValue(engine), quitButtonsProvider.overrideWithValue(null)],
        );
        playing(async, c);
        heldButtons.add(_quit);
        async.elapse(const Duration(seconds: 5));
        expect(engine.closes, 0);
        c.dispose();
      });
    });

    test('after the game ended, held does nothing', () {
      fakeAsync((async) {
        final c = ProviderContainer(
          overrides: [
            playEngineProvider.overrideWithValue(engine),
            quitButtonsProvider.overrideWithValue(QuitButtons.selectBumpers),
          ],
        );
        playing(async, c);
        engine.running!.complete(const PlayResult('Save synced'));
        async.flushMicrotasks();
        heldButtons.add(_quit);
        async.elapse(const Duration(seconds: 5));
        expect(engine.closes, 0);
        c.dispose();
      });
    });
  });

  test('a second Play while a game runs is refused', () async {
    await c.read(playControllerProvider.notifier).play(game(1, 'G'));
    expect(await c.read(playControllerProvider.notifier).play(game(2, 'H')), contains('already running'));
    expect(engine.steps, ['states', 'prepare', 'launch']);
  });

  test('a game that isn\'t downloaded, or an emulator that isn\'t installed, is explained', () async {
    engine.downloaded = false;
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), contains('Download'));
    engine
      ..downloaded = true
      ..installed = false;
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), contains('PCSX2'));
    expect(engine.steps, isEmpty);
  });

  test("an emulator that can't keep the game's save (DSiWare in melonDS) is refused with why", () async {
    engine.whyNot = "melonDS can't save DSiWare games";
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), contains('DSiWare'));
    expect(engine.steps, isEmpty);
    expect(c.read(playControllerProvider).runningGameId, isNull);
  });

  test("the ROM is readied for the emulator first (a zip unpacked), and the readied one launches", () async {
    engine.readyPath = 'D:/G/roms/xbox/Halo/Halo.iso';
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), isNull);
    expect(engine.readiedFor, isNotNull);
    expect(engine.launchedRom, 'D:/G/roms/xbox/Halo/Halo.iso');
  });

  test('while the ROM is readied, the play state says what is happening; it clears after', () async {
    engine.readyProgress = 'Unpacking G… 40 %';
    engine.readyGate = Completer<void>();
    final started = c.read(playControllerProvider.notifier).play(game(1, 'G'));
    await pumpEventQueue();
    expect(c.read(playControllerProvider).preparing, 'Unpacking G… 40 %');
    engine.readyGate!.complete();
    expect(await started, isNull);
    expect(c.read(playControllerProvider).preparing, isNull);
    expect(c.read(playControllerProvider).runningGameId, '1');
  });

  test("a ROM that can't be readied stops the start, saying why", () async {
    engine.readyError = const NotAnXboxDisc('G');
    final reason = await c.read(playControllerProvider.notifier).play(game(1, 'G'));
    expect(reason, contains("isn't an Xbox disc image"));
    expect(engine.steps, isEmpty);
    expect(c.read(playControllerProvider).runningGameId, isNull);
  });

  test('a quick second press while the first is still starting is refused', () async {
    final first = c.read(playControllerProvider.notifier).play(game(1, 'G'));
    final second = c.read(playControllerProvider.notifier).play(game(2, 'H'));
    expect(await first, isNull);
    expect(await second, contains('already running'));
    expect(engine.steps, ['states', 'prepare', 'launch']);
  });

  test("a refusal clears the starting state, so the next Play isn't blocked", () async {
    engine.downloaded = false;
    await c.read(playControllerProvider.notifier).play(game(1, 'G'));
    expect(c.read(playControllerProvider).runningGameId, isNull);
  });

  test("the pull's problem is told, and the game still starts", () async {
    engine.problem = 'card full';
    final told = <String>[];
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G'), onNotice: told.add), isNull);
    expect(told, ['card full']);
    expect(engine.steps, ['states', 'prepare', 'launch']);
  });

  test("a request's emulator and core are used, not the platform default", () async {
    const ra = SaveMaker('retroarch', coreId: 'beetle_psx_hw');
    await c.read(playControllerProvider.notifier).play(game(1, 'G'), request: const PlayRequest(emulator: ra));
    expect(engine.launchedIn, 'retroarch');
    expect(engine.coreOverride, 'beetle_psx_hw_libretro');
    expect(engine.request?.emulator, ra);
  });

  test("remember stores the game's emulator, forget clears it", () async {
    await c
        .read(playControllerProvider.notifier)
        .play(game(1, 'G'), request: const PlayRequest(emulator: SaveMaker('duckstation'), remember: true));
    expect(engine.remembered['1'], 'duckstation');
    engine.running!.complete(const PlayResult('ok'));
    await Future<void>.delayed(Duration.zero);
    await c
        .read(playControllerProvider.notifier)
        .play(game(1, 'G'), request: const PlayRequest(emulator: SaveMaker('pcsx2'), forget: true));
    expect(engine.remembered['1'], isNull);
  });

  final auto = ResumeEntry(
    emulatorId: 'pcsx2',
    emulatorName: 'PCSX2',
    fileName: 'auto.p2s',
    slot: const AutoStateSlot(),
    savedAt: DateTime(2026, 10, 9),
    where: ResumeWhere.thisPc,
  );

  test('a game above the age limit (#224) is refused on Play and Resume, before anything runs', () async {
    final limited = ProviderContainer(
      overrides: [
        playEngineProvider.overrideWithValue(engine),
        ageLimitProvider.overrideWithValue(const AgeLimit(maxAge: 12)),
      ],
    );
    addTearDown(limited.dispose);
    final mature = Game.fromJson({
      ...gameJson(1, 'G'),
      'metadatum': {
        'age_ratings': ['ESRB:M'],
      },
    });
    final play = limited.read(playControllerProvider.notifier);
    expect(await play.play(mature), contains('above this profile'));
    expect(await play.resume(mature, auto), contains('above this profile'));
    expect(engine.steps, isEmpty);
    expect(limited.read(playControllerProvider).runningGameId, isNull);
    expect(await play.play(game(2, 'Unrated')), isNull, reason: 'unrated plays unless hidden');
  });

  test('with an age limit an emulator is not opened on its own (it opens any ROM)', () async {
    final limited = ProviderContainer(
      overrides: [
        playEngineProvider.overrideWithValue(engine),
        ageLimitProvider.overrideWithValue(const AgeLimit(maxAge: 12)),
      ],
    );
    addTearDown(limited.dispose);
    expect(
      await limited.read(playControllerProvider.notifier).openEmulator('retroarch', 'RetroArch', 'retroarch.exe'),
      contains('age limit'),
    );
    expect(limited.read(playControllerProvider).runningGameId, isNull);
  });

  test('resume pulls states, checks the chosen one, puts the save in place, then boots into the state', () async {
    expect(await c.read(playControllerProvider.notifier).resume(game(1, 'G'), auto), isNull);
    expect(engine.steps, ['states', 'check', 'prepare', 'launch']);
    expect(engine.launchedIn, 'pcsx2');
    expect(engine.loadStatePath, r'D:\G\states\auto.p2s');
    expect(c.read(playControllerProvider).runningGameId, '1');
  });

  test(
    "another player's state (#92): pulled, then taken as a copy and booted into, never checked as one's own",
    () async {
      final theirs = ResumeEntry(
        emulatorId: 'pcsx2',
        emulatorName: 'PCSX2',
        fileName: 'm.p2s',
        slot: const NumberedStateSlot(2),
        savedAt: DateTime(2026, 10, 9),
        where: ResumeWhere.romm,
        remoteId: 9,
        owner: const SaveOwner(userId: 7, username: 'maja'),
      );
      expect(await c.read(playControllerProvider.notifier).resume(game(1, 'G'), theirs), isNull);
      expect(engine.steps, ['states', 'take m.p2s', 'prepare', 'launch']);
      expect(engine.loadStatePath, '/temp/shared-state');
    },
  );

  test("another player's state that can't be taken starts nothing, and says why", () async {
    engine.sharedPath = null;
    final theirs = ResumeEntry(
      emulatorId: 'pcsx2',
      emulatorName: 'PCSX2',
      fileName: 'm.p2s',
      slot: const NumberedStateSlot(2),
      savedAt: DateTime(2026, 10, 9),
      where: ResumeWhere.romm,
      owner: const SaveOwner(userId: 7, username: 'maja'),
    );
    final reason = await c.read(playControllerProvider.notifier).resume(game(1, 'G'), theirs);
    expect(reason, "Couldn't get maja's Slot 2 from RomM (every slot is in use). Nothing was started.");
    expect(engine.steps, isNot(contains('launch')));
    expect(c.read(playControllerProvider).runningGameId, isNull);
  });

  test("a RetroArch state resumes in the core it belongs to, not the platform's default", () async {
    final rearmed = ResumeEntry(
      emulatorId: 'retroarch',
      emulatorName: 'RetroArch',
      fileName: 'WipEout.state.auto',
      slot: const AutoStateSlot(),
      savedAt: DateTime(2026, 10, 18),
      where: ResumeWhere.both,
      core: 'pcsx_rearmed',
    );
    expect(await c.read(playControllerProvider.notifier).resume(game(1, 'G'), rearmed), isNull);
    expect(engine.launchedIn, 'retroarch');
    expect(engine.coreOverride, 'pcsx_rearmed_libretro');
    expect(engine.pulledCore, 'pcsx_rearmed_libretro', reason: "the pull reads that core's state folder");
  });

  test('a state of an emulator without cores resumes with no core', () async {
    expect(await c.read(playControllerProvider.notifier).resume(game(1, 'G'), auto), isNull);
    expect(engine.coreOverride, isNull);
  });

  group('an emulator opened on its own (its settings)', () {
    test('it counts as running until it closes: no game, no second emulator', () async {
      final play = c.read(playControllerProvider.notifier);
      expect(await play.openEmulator('dolphin', 'Dolphin', r'C:\G\emulators\dolphin\Dolphin.exe'), isNull);
      expect(engine.opened, r'dolphin C:\G\emulators\dolphin\Dolphin.exe');
      expect(c.read(playControllerProvider).runningGameId, PlayController.openEmulatorId('dolphin'));
      expect(await play.play(game(1, 'G')), contains('already running'));
      expect(await play.openEmulator('pcsx2', 'PCSX2', 'p.exe'), contains('Close it first'));
      engine.closeOpened!();
      expect(c.read(playControllerProvider).runningGameId, isNull);
    });

    test('not while a game runs', () async {
      final play = c.read(playControllerProvider.notifier);
      await play.play(game(1, 'G'));
      expect(await play.openEmulator('dolphin', 'Dolphin', 'd.exe'), contains('Close it first'));
      expect(engine.opened, isNull);
    });

    test("one that won't start says why and frees the slot", () async {
      engine.openFails = true;
      final play = c.read(playControllerProvider.notifier);
      expect(await play.openEmulator('dolphin', 'Dolphin', 'd.exe'), contains("Couldn't open Dolphin"));
      expect(c.read(playControllerProvider).runningGameId, isNull);
    });
  });

  test('a state that is missing says why, and nothing starts', () async {
    engine.check = const ResumeMissing();
    expect(await c.read(playControllerProvider.notifier).resume(game(1, 'G'), auto), contains("Couldn't find"));
    expect(engine.steps, ['states', 'check']);
    expect(c.read(playControllerProvider).runningGameId, isNull);
  });

  test('a state from another emulator build asks first; No starts nothing', () async {
    engine.check = const ResumeReady('x.p2s', prompt: (stateVersion: '1.7', installed: '2.0'));
    String? asked;
    expect(
      await c
          .read(playControllerProvider.notifier)
          .resume(
            game(1, 'G'),
            auto,
            confirmVersion: (v, i) async {
              asked = '$v→$i';
              return false;
            },
          ),
      isNotNull,
    );
    expect(asked, '1.7→2.0');
    expect(engine.steps, ['states', 'check']);
  });

  test('resume is refused while a game runs', () async {
    await c.read(playControllerProvider.notifier).play(game(2, 'H'));
    expect(await c.read(playControllerProvider.notifier).resume(game(1, 'G'), auto), contains('already running'));
  });

  test("a session whose save reached RomM settles that game's waiting uploads", () async {
    final waiting = [(romId: '1', entry: BackupEntry(timestamp: DateTime(2026), md5Hash: 'h', localZipPath: 'z'))];
    final queue = UploadQueue(
      isOffline: () => false,
      pending: () => [...waiting],
      markSynced: (id, e) async => waiting.removeWhere((w) => w.entry == e),
      gameById: (_) async => null,
      romPathFor: (_) async => null,
      push: (_, _, _) async => false,
    );
    final c2 = ProviderContainer(
      overrides: [playEngineProvider.overrideWithValue(engine), uploadQueueProvider.overrideWith((ref) async => queue)],
    );
    addTearDown(c2.dispose);
    await c2.read(playControllerProvider.notifier).play(game(1, 'G'));
    engine.running!.complete(const PlayResult('Save synced to RomM.', synced: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(waiting, isEmpty);
  });

  test('a RetroArch core that is not installed yet is downloaded, then the game starts', () async {
    engine.missingCore = 'mupen64plus_next_libretro.dll';
    final told = <String>[];
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G'), onNotice: told.add), isNull);
    expect(engine.steps, ['states', 'prepare', 'launch (no core)', 'core mupen64plus_next_libretro.dll', 'launch']);
    expect(told.single, contains('mupen64plus_next'));
    expect(c.read(playControllerProvider).runningGameId, '1');
  });

  test("a core that can't be downloaded says so, and nothing runs", () async {
    engine
      ..missingCore = 'mupen64plus_next_libretro.dll'
      ..coreDownloadFails = true;
    expect(await c.read(playControllerProvider.notifier).play(game(1, 'G')), contains("couldn't be downloaded"));
    expect(c.read(playControllerProvider).runningGameId, isNull);
  });
}
