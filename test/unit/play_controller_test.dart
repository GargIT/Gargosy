import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/core/save/catalog/play_request.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/play/play_menu.dart';

import '../helpers/game_fixtures.dart';

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

  @override
  bool stateSyncAvailable(Game game) => stateSyncOn;

  @override
  Future<String> syncStatesNow(Game game) async {
    steps.add('sync states');
    return '1 state down, 0 up';
  }

  @override
  Future<bool> setRommUser(Game game, {String? status, int? rating, int? completion, bool? backlogged, bool? nowPlaying}) async {
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
  @override
  Future<String?> romPathFor(Game game) async {
    await Future<void>.delayed(Duration.zero); // lists a folder
    return downloaded ? r'D:\G\roms\ps2\g.chd' : null;
  }

  String? problem;
  @override
  Future<void> prepare(Game game, String romPath, EmulatorStrategy s,
      {PlayRequest? request, String? coreOverride, void Function(String)? onProblem}) async {
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
  Future<StatePull> pullStates(Game game, String romPath, EmulatorStrategy s,
      {String? priority, String? coreOverride, void Function(String)? onProblem}) async {
    steps.add('states');
    return statePull;
  }

  @override
  Future<ResumeCheck> checkResume(ResumeEntry entry, Game game, String romPath, StatePull pull) async {
    steps.add('check');
    return check;
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
  Future<PlaySession> launch(Game game, String romPath, EmulatorStrategy s, {String? coreOverride, String? loadStatePath}) async {
    final missing = missingCore;
    if (missing != null) {
      missingCore = null;
      steps.add('launch (no core)');
      throw MissingRetroArchCoreException(coreName: missing, corePath: r'D:\G\emulators\retroarch\cores\' + missing, exePath: 'ra.exe');
    }
    steps.add('launch');
    this.loadStatePath = loadStatePath;
    launchedIn = s.emulatorId;
    this.coreOverride = coreOverride;
    running = Completer<PlayResult>();
    return PlaySession(running!.future);
  }
}

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
    await c.read(playControllerProvider.notifier).play(game(1, 'G'),
        request: const PlayRequest(emulator: SaveMaker('duckstation'), remember: true));
    expect(engine.remembered['1'], 'duckstation');
    engine.running!.complete(const PlayResult('ok'));
    await Future<void>.delayed(Duration.zero);
    await c.read(playControllerProvider.notifier).play(game(1, 'G'),
        request: const PlayRequest(emulator: SaveMaker('pcsx2'), forget: true));
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

  test('resume pulls states, checks the chosen one, puts the save in place, then boots into the state', () async {
    expect(await c.read(playControllerProvider.notifier).resume(game(1, 'G'), auto), isNull);
    expect(engine.steps, ['states', 'check', 'prepare', 'launch']);
    expect(engine.launchedIn, 'pcsx2');
    expect(engine.loadStatePath, r'D:\G\states\auto.p2s');
    expect(c.read(playControllerProvider).runningGameId, '1');
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
        await c.read(playControllerProvider.notifier).resume(game(1, 'G'), auto, confirmVersion: (v, i) async {
          asked = '$v→$i';
          return false;
        }),
        isNotNull);
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
    final c2 = ProviderContainer(overrides: [
      playEngineProvider.overrideWithValue(engine),
      uploadQueueProvider.overrideWith((ref) async => queue),
    ]);
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
