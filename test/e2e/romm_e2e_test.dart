@Tags(['e2e'])
library;

import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_admin.dart';
import 'package:gargosy/core/romm/romm_auth_client.dart';
import 'package:gargosy/core/romm/romm_collection_edits.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_play_sessions.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';
import 'e2e_env.dart';

/// Gargosy's RomM calls against a real RomM (#242): CI's in Docker
/// (`tool/e2e/start_romm.sh`), or any RomM named by `ROMM_E2E_*`
/// (`docs/e2e-tests.md`). Everything made on RomM is deleted again.
void main() {
  final env = E2eEnv.read();
  late E2eLogin player;
  late Platform platform;
  late Game game;
  late io.Directory temp;

  setUpAll(() async {
    if (env == null) return;
    temp = await io.Directory.systemTemp.createTemp('gargosy-e2e');
    player = await env.signIn();
    final platforms = await player.romm.getPlatforms();
    platform = platforms.firstWhere(
      (p) => p.slug == env.platform || p.fsSlug == env.platform,
      orElse: () => throw StateError('No platform ${env.platform} on ${env.url}: ${platforms.map((p) => p.slug)}'),
    );
    final games = await player.romm.getGames('${platform.id}');
    // The smallest on RomM's disk (one missing there has size 0): the download test fetches it.
    final onDisk = games.where((g) => g.fileSize > 0).toList()..sort((a, b) => a.fileSize.compareTo(b.fileSize));
    if (onDisk.isEmpty) throw StateError('No game of ${env.platform} is on the server disk');
    game = onDisk.first;
  });

  tearDownAll(() async {
    if (env == null) return;
    await player.close();
    await deleteTempDir(temp.path);
  });

  LibraryApi library() => RommLibraryApi(player.romm.dio, () => player.romm.authOptions);

  Future<io.File> fileOf(String name, List<int> bytes) async =>
      io.File(p.join(temp.path, name))..writeAsBytesSync(bytes);

  List<int> bytesOf(int n, int seed) {
    final r = Random(seed);
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  group('a player', skip: E2eEnv.skip, () {
    test('signs in with a client token', () async {
      final me = await RommAuthClient(env!.url).fetchMe(player.token);
      if (env.user != null) expect(me.username, env.user);
      expect(me.oauthScopes, containsAll(['roms.read', 'assets.write', 'collections.write']));
      final caps = await player.romm.fetchCapabilities();
      expect(caps, isNotNull);
    });

    test("sees the platforms with their games", () async {
      expect(platform.gamesCount, greaterThan(0));
      expect(platform.name, isNotEmpty);
    });

    test('pages the gallery with its A–Z index', () async {
      final page = await library().page(GalleryQuery(platformId: platform.id), withCharIndex: true);
      expect(page.total, platform.gamesCount);
      expect(page.games, isNotEmpty);
      expect(page.charIndex, isNotNull);
      expect(page.charIndex, isNotEmpty);
      expect(page.charIndex!.values, contains(0), reason: 'the first letter starts at the top');
    });

    test('opens a game with its files', () async {
      final full = await player.romm.getGame(game.id);
      expect(full, isNotNull);
      expect(full!.id, game.id);
      expect(full.platformId, platform.id, reason: "getGames lists only the platform's games");
      expect(full.fsName, isNotEmpty);
      expect(full.files, isNotEmpty);
    });

    test("downloads a game, checked against RomM's hashes", () async {
      final root = AppRoot(p.join(temp.path, 'gargosy'));
      await root.ensureLayout();
      final files = RomFiles(root);
      final service = DownloadService(
        dio: player.romm.dio,
        auth: () => player.romm.authOptions,
        files: files,
        guard: PathGuard(root),
        tempDir: p.join(root.appData, 'temp'),
        urlFor: player.romm.getDownloadUrl,
        detail: player.romm.getGame,
      );
      await service.download(game);
      final at = files.pathFor(game);
      expect(io.FileSystemEntity.typeSync(at), isNot(io.FileSystemEntityType.notFound));
      if (io.FileSystemEntity.isFileSync(at)) expect(io.File(at).lengthSync(), game.fileSize);
    });

    test('uploads a save and pulls it back', () async {
      final bytes = bytesOf(8 * 1024, 1);
      final file = await fileOf('${E2eEnv.mark} save.srm', bytes);
      final up = await player.romm.uploadSave(game.id, file, emulator: 'gargosy-e2e', slot: 'gargosy-e2e');
      expect(up.ok, isTrue, reason: 'conflict: ${up.conflict}');
      final id = '${up.saved?['id']}';
      try {
        final saves = await player.romm.getSaves(game.id);
        final save = saves.firstWhere((s) => s.id == id);
        expect(save.slot, 'gargosy-e2e');
        expect(await player.romm.downloadSave(save.url), Uint8List.fromList(bytes));
      } finally {
        expect(await player.romm.deleteSaves([int.parse(id)]), isTrue);
      }
      expect((await player.romm.getSaves(game.id)).where((s) => s.id == id), isEmpty);
    });

    test('uploads a state, labels it and pulls it back', () async {
      final bytes = bytesOf(4 * 1024, 2);
      final file = await fileOf('${E2eEnv.mark} state.state', bytes);
      final state = await player.romm.uploadState(
        game.id,
        file,
        fileName: '${E2eEnv.mark} state.state',
        emulator: 'gargosy-e2e',
      );
      try {
        final labelled = await player.romm.setStateLabels(state.id, ['gargosy-e2e']);
        expect(labelled.labels, ['gargosy-e2e']);
        final listed = (await player.romm.listStates(game.id)).firstWhere((s) => s.id == state.id);
        expect(listed.labels, ['gargosy-e2e']);
        expect(await player.romm.downloadState(state.id), Uint8List.fromList(bytes));
      } finally {
        expect(await player.romm.deleteStates([state.id]), isTrue);
      }
    });

    test('makes a collection, renames and shares it, then deletes it', () async {
      final edits = RommCollectionEdits(player.romm.dio, () => player.romm.authOptions);
      var c = await edits.create('${E2eEnv.mark} collection', gameId: game.id);
      try {
        expect(c.romIds, contains(int.parse(game.id)));
        c = await edits.rename(c, '${E2eEnv.mark} renamed');
        expect(c.name, '${E2eEnv.mark} renamed');
        expect(c.romIds, contains(int.parse(game.id)), reason: 'a rename keeps its games');
        c = await edits.setShared(c, true);
        expect(c.isPublic, isTrue);
        final mine = await library().collections();
        expect(mine.map((m) => m.id), contains(c.id));
      } finally {
        await edits.delete(c);
      }
      expect((await library().collections()).map((m) => m.id), isNot(contains(c.id)));
    });

    test('sends a play session and reads it back', () async {
      final sessions = RommPlaySessions(player.romm.dio, () => player.romm.authOptions);
      final end = DateTime.now().subtract(const Duration(minutes: 1));
      final start = end.subtract(const Duration(minutes: 7));
      final before = DateTime.now().subtract(const Duration(hours: 1));
      await sessions.record([PlaySessionRecord(gameId: game.id, start: start, end: end)]);
      try {
        final since = await sessions.sessionsSince(before);
        expect(since, isNotNull);
        final ours = since!.where((s) => s.gameId == game.id && s.start.difference(start).inSeconds.abs() < 2);
        expect(ours, hasLength(1));
        expect(ours.single.end.difference(end).inSeconds.abs(), lessThan(2));
        final time = await sessions.timeFor(game.id);
        expect(time!.sessions, greaterThanOrEqualTo(1));
      } finally {
        await _deleteSessions(player, game.id, start);
      }
    });
  });

  group('an admin', skip: E2eEnv.skip ?? (env!.hasAdmin ? null : 'Set ROMM_E2E_ADMIN_USER to run'), () {
    late E2eLogin admin;
    setUpAll(() async => admin = await E2eLogin.signIn(env!.url, env.adminUser!, env.adminPassword!));
    tearDownAll(() => admin.close());

    test('may scan, upload and match; the player may not', () async {
      final rights = await admin.romm.rights();
      expect((rights.scan, rights.upload, rights.match, rights.deleteGames), (true, true, true, true));
      final theirs = await player.romm.rights();
      expect((theirs.scan, theirs.upload), (false, false));
    });

    test('scans a platform and follows it to the end', () async {
      final progress = await _scan(admin, platform.id);
      expect(progress.finished, isTrue, reason: 'status ${progress.status}');
      expect(progress.scannedGames, greaterThanOrEqualTo(0));
    });

    test('uploads a game in pieces, which a scan adds; then deletes it', () async {
      // Over one piece (10 MB), so it goes in two.
      final name = '${E2eEnv.mark} Upload ${DateTime.now().millisecondsSinceEpoch}.${_extensionOf(game)}';
      final file = await fileOf(name, bytesOf(10 * 1024 * 1024 + 4096, 3));
      final heard = <int>[];
      await admin.romm.uploadGame(platform.id, file.path, onProgress: (sent, total) => heard.add(sent));
      expect(heard.last, file.lengthSync());
      await _scan(admin, platform.id);
      final found = (await admin.romm.getGames('${platform.id}')).where((g) => g.fsName == name).toList();
      expect(found, hasLength(1), reason: 'the uploaded game after a scan');
      expect(found.single.fileSize, file.lengthSync());
      expect(await admin.romm.deleteGame(int.parse(found.single.id), fromServerDisk: true), RomDeleteResult.deleted);
    });
  });
}

/// [g]'s file extension, without the dot.
String _extensionOf(Game g) => p.extension(g.fsName ?? '.bin').replaceFirst('.', '');

/// A quick scan of [platformId], followed until it ends.
Future<ScanProgress> _scan(E2eLogin admin, int platformId) async {
  final id = await admin.romm.startScan(ScanKind.quick, platformIds: [platformId]);
  final until = DateTime.now().add(const Duration(minutes: 3));
  while (true) {
    final progress = await admin.romm.scanProgress(id);
    if (!progress.running) return progress;
    if (DateTime.now().isAfter(until)) fail('Scan $id still ${progress.status} after 3 minutes');
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

/// Deletes the test's play session of [gameId] that started at [start].
Future<void> _deleteSessions(E2eLogin login, String gameId, DateTime start) async {
  final list =
      (await login.raw.get<List<dynamic>>('/api/play-sessions', queryParameters: {'rom_id': gameId})).data ?? const [];
  for (final s in list) {
    if (s is! Map) continue;
    // RomM's times are UTC, with or without a zone.
    final raw = '${s['start_time']}';
    final at = DateTime.tryParse(RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(raw) ? raw : '${raw}Z');
    if (at != null && at.difference(start.toUtc()).inSeconds.abs() < 2) {
      await login.raw.delete<void>('/api/play-sessions/${s['id']}', options: Options(validateStatus: (_) => true));
    }
  }
}
