import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/install_request.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/remote_installs.dart';

import '../helpers/profile_test_env.dart';

class _FakeApi implements RemoteInstallApi {
  InstallClaim Function() answer = () => const InstallsTaken([]);
  final reports = <(String, InstallOutcome, String?)>[];
  int claims = 0;
  bool failReports = false;

  @override
  Future<InstallClaim> claim() async {
    claims++;
    return answer();
  }

  @override
  Future<void> report(String requestId, InstallOutcome outcome, {String? reason}) async {
    if (failReports) throw StateError('offline');
    reports.add((requestId, outcome, reason));
  }
}

Game _game(String id) => Game(id: id, name: 'Game $id', platformSlug: 'snes', fileSize: 1);

InstallRequest _request(String id, String rom) => InstallRequest(id: id, romId: rom);

/// Games sent from RomM's web page (#288): claimed, downloaded through the
/// queue, and RomM told how each ended.
void main() {
  late _FakeApi api;
  late MemoryPrefs prefs;
  late Set<String> onPc;
  late Set<String> pending;
  late List<String> downloads;
  late List<String> remembered;
  late List<String> notices;
  late Map<String, String> errors;
  late bool allowed;
  late bool offline;
  late bool gameReachable;
  late Future<void> Function(Game) download;

  RemoteInstalls make({Future<bool> Function()? advertise}) => RemoteInstalls(
    api: api,
    log: RemoteInstallLog(prefs),
    gameOf: (id) async => gameReachable ? _game(id) : null,
    download: (g) => download(g),
    isOnPc: (g) => onPc.contains(g.id),
    isPending: (g) => pending.contains(g.id),
    errorOf: (g) => errors[g.id],
    allows: (_) => allowed,
    remember: (g) async => remembered.add(g.id),
    onStarted: (g) => notices.add(g.id),
    advertise: advertise,
    isOffline: () => offline,
  );

  /// A download as the queue does it: pending at once, on this PC when done.
  Future<void> Function(Game) queueThat({Completer<void>? until, bool lands = true}) => (g) {
    downloads.add(g.id);
    pending.add(g.id);
    return (until?.future ?? Future<void>.value()).then((_) {
      pending.remove(g.id);
      if (lands) onPc.add(g.id);
    });
  };

  setUp(() {
    api = _FakeApi();
    prefs = MemoryPrefs();
    onPc = {};
    pending = {};
    downloads = [];
    remembered = [];
    notices = [];
    errors = {};
    allowed = true;
    offline = false;
    gameReachable = true;
    download = queueThat();
  });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a sent game is downloaded, said, then RomM is told it is done', () async {
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    final installs = make();
    await installs.check();
    await settle();
    expect(downloads, ['7']);
    expect(notices, ['7']);
    expect(api.reports, [('r1', InstallOutcome.done, null)]);
    expect(installs.state.value, RemoteInstallState.ready);
  });

  test("a game already on this PC is already installed, not downloaded, and in this profile's library", () async {
    onPc.add('7');
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(downloads, isEmpty);
    expect(remembered, ['7']);
    expect(api.reports.single.$2, InstallOutcome.alreadyInstalled);
  });

  test('a game Gargosy started before a restart and that is here now is done', () async {
    final running = Completer<void>();
    download = queueThat(until: running);
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    final first = make();
    await first.check();
    await settle();
    first.dispose();
    // The download finished as Gargosy closed; a new run finds it here.
    onPc.add('7');
    final second = make();
    await second.check();
    await settle();
    expect(downloads, ['7']);
    expect(api.reports.single, ('r1', InstallOutcome.done, null));
  });

  test("a game above the profile's age limit fails with why, and isn't downloaded", () async {
    allowed = false;
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(downloads, isEmpty);
    expect(api.reports.single.$2, InstallOutcome.failed);
    expect(api.reports.single.$3, contains('age limit'));
  });

  test("a game RomM doesn't give now waits for the next claim, unreported", () async {
    gameReachable = false;
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(api.reports, isEmpty);
  });

  test("a download the queue refuses at once fails with its error, and isn't said", () async {
    download = (g) async => errors[g.id] = 'Needs 4 GB, 1 GB free on D:.';
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(notices, isEmpty);
    expect(api.reports.single, ('r1', InstallOutcome.failed, 'Needs 4 GB, 1 GB free on D:.'));
  });

  test("a queue that takes nothing (no download service) waits for the next claim", () async {
    download = (g) async {};
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(api.reports, isEmpty);
  });

  test('a download cancelled on this PC fails, saying so, and is never downloaded again', () async {
    download = queueThat(lands: false);
    api.failReports = true;
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    final installs = make();
    await installs.check();
    await settle();
    // The report didn't reach RomM: the next claim says the same, no new download.
    api.failReports = false;
    await installs.check();
    await settle();
    expect(downloads, ['7']);
    expect(api.reports.single.$2, InstallOutcome.failed);
    expect(api.reports.single.$3, contains('cancelled'));
  });

  test('a request still downloading is not started again when RomM gives it again', () async {
    final running = Completer<void>();
    download = queueThat(until: running);
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    final installs = make();
    await installs.check();
    await settle();
    await installs.check();
    await settle();
    expect(downloads, ['7']);
    running.complete();
    await settle();
    expect(api.reports.single.$2, InstallOutcome.done);
  });

  test('a game the player was already downloading is not said again', () async {
    pending.add('7');
    final running = Completer<void>();
    download = queueThat(until: running);
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(notices, isEmpty);
    running.complete();
    await settle();
    expect(api.reports.single.$2, InstallOutcome.done);
  });

  test('RomM is told this PC takes requests until it says so', () async {
    var told = 0;
    var takes = false;
    final installs = make(advertise: () async => ++told > 0 && takes);
    await installs.check();
    await installs.check();
    takes = true;
    await installs.check();
    await installs.check();
    expect(told, 3);
  });

  test('RomM without installs, or a login not paired, is said', () async {
    final installs = make();
    api.answer = () => const InstallsOff();
    await installs.check();
    expect(installs.state.value, RemoteInstallState.off);
    api.answer = () => const InstallsNotBound();
    await installs.check();
    expect(installs.state.value, RemoteInstallState.notPaired);
  });

  test("RomM isn't asked while it's offline, and an unreachable RomM changes nothing", () async {
    offline = true;
    final installs = make();
    await installs.check();
    expect(api.claims, 0);
    offline = false;
    api.answer = () => throw StateError('unreachable');
    await installs.check();
    expect(api.claims, 1);
    expect(installs.state.value, RemoteInstallState.unknown);
  });

  test('the log keeps the newest requests only', () async {
    final log = RemoteInstallLog(prefs);
    for (var i = 0; i < RemoteInstallLog.max + 5; i++) {
      await log.end('r$i', InstallOutcome.done, null);
    }
    expect(log.outcomeOf('r0'), isNull);
    expect(log.outcomeOf('r${RemoteInstallLog.max + 4}'), (InstallOutcome.done, null));
  });

  test('a claim of RomM parses its requests and skips what is not one', () {
    expect(InstallRequest.fromJson({'id': 'abc', 'rom_id': 7})?.romId, '7');
    expect(InstallRequest.fromJson({'id': 'abc'}), isNull);
    expect(InstallRequest.fromJson('x'), isNull);
  });
}
