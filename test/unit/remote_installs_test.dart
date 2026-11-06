import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/install_request.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/remote_installs.dart';

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

InstallRequest _request(String id, String rom, {DateTime? at}) =>
    InstallRequest(id: id, romId: rom, createdAt: at ?? DateTime.utc(2026, 11, 6, 12));

/// Games sent from RomM's web page (#288): claimed, downloaded through the
/// queue, and RomM told how each ended.
void main() {
  late _FakeApi api;
  late Set<String> onPc;
  late Map<String, DateTime> installed;
  late List<String> downloads;
  late Map<String, String> errors;
  late bool allowed;
  late bool offline;
  late Future<void> Function(Game) download;

  RemoteInstalls make() => RemoteInstalls(
    api: api,
    gameOf: (id) async => id == 'gone' ? null : _game(id),
    download: (g) => download(g),
    isOnPc: (g) => onPc.contains(g.id),
    installedAt: (g) => installed[g.id],
    errorOf: (g) => errors[g.id],
    allows: (_) => allowed,
    isOffline: () => offline,
  );

  setUp(() {
    api = _FakeApi();
    onPc = {};
    installed = {};
    downloads = [];
    errors = {};
    allowed = true;
    offline = false;
    download = (g) async {
      downloads.add(g.id);
      onPc.add(g.id);
    };
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a sent game is downloaded, then RomM is told it is done', () async {
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    final installs = make();
    await installs.check();
    await settle();
    expect(downloads, ['7']);
    expect(api.reports, [('r1', InstallOutcome.done, null)]);
    expect(installs.state.value, RemoteInstallState.ready);
  });

  test('a game on this PC before it was sent is already installed, and not downloaded', () async {
    onPc.add('7');
    installed['7'] = DateTime.utc(2026, 1, 1);
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(downloads, isEmpty);
    expect(api.reports.single.$2, InstallOutcome.alreadyInstalled);
  });

  test('a game that came after it was sent (Gargosy restarted) is done', () async {
    onPc.add('7');
    installed['7'] = DateTime.utc(2026, 11, 6, 13);
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(api.reports.single.$2, InstallOutcome.done);
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

  test("a game RomM doesn't give fails", () async {
    api.answer = () => InstallsTaken([_request('r1', 'gone')]);
    await make().check();
    await settle();
    expect(api.reports.single.$2, InstallOutcome.failed);
  });

  test("a failed download fails with the download's error", () async {
    download = (g) async => errors[g.id] = 'Needs 4 GB, 1 GB free on D:.';
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(api.reports.single, ('r1', InstallOutcome.failed, 'Needs 4 GB, 1 GB free on D:.'));
  });

  test('a download cancelled on this PC fails, saying so', () async {
    download = (g) async {};
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    await make().check();
    await settle();
    expect(api.reports.single.$2, InstallOutcome.failed);
    expect(api.reports.single.$3, contains('cancelled'));
  });

  test('a request still downloading is not started again when RomM gives it again', () async {
    final running = Completer<void>();
    download = (g) {
      downloads.add(g.id);
      return running.future;
    };
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    final installs = make();
    await installs.check();
    await settle();
    await installs.check();
    await settle();
    expect(downloads, ['7']);
    onPc.add('7');
    running.complete();
    await settle();
    expect(api.reports.single.$2, InstallOutcome.done);
  });

  test("a report that doesn't reach RomM is made again from the next claim", () async {
    api.failReports = true;
    api.answer = () => InstallsTaken([_request('r1', '7')]);
    final installs = make();
    await installs.check();
    await settle();
    api.failReports = false;
    await installs.check();
    await settle();
    // Downloaded the first time; the second look finds it on this PC.
    expect(downloads, ['7']);
    expect(api.reports.single, ('r1', InstallOutcome.done, null));
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

  test('a claim of RomM parses its requests and skips what is not one', () {
    expect(InstallRequest.fromJson({'id': 'abc', 'rom_id': 7, 'created_at': '2026-11-06T12:00:00Z'})?.romId, '7');
    expect(InstallRequest.fromJson({'id': 'abc'}), isNull);
    expect(InstallRequest.fromJson('x'), isNull);
  });
}
