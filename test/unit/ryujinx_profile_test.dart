// Issue #9: Ryujinx on a profile's data with -r, downloaded from Ryubing's GitLab.
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_registry_data.dart';
import 'package:gargosy/core/emulator/release_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/ryujinx_save_strategy.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/fullscreen.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

Map<String, Object?> release(String tag, List<String> files, {bool upcoming = false}) => {
      'tag_name': tag,
      'name': 'Ryujinx $tag',
      'upcoming_release': upcoming,
      'assets': {
        'links': [
          for (final f in files)
            {
              'name': f,
              'url': 'https://git.ryujinx.app/ryubing/ryujinx/-/releases/$tag/downloads/$f',
              'direct_asset_url': 'https://git.ryujinx.app/api/v4/projects/1/packages/generic/Ryubing/$tag/$f',
            },
        ],
        'sources': [
          {'format': 'zip', 'url': 'https://git.ryujinx.app/ryubing/ryujinx/-/archive/$tag/ryujinx-$tag.zip'},
        ],
      },
    };

class _Api implements HttpClientAdapter {
  _Api(this.body);
  final Object body;
  final asked = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    asked.add(options.uri);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final windows = ['win_x64', '.zip'];
  const excluded = ['debug', 'source', 'canary'];

  group('the download: Ryubing on GitLab', () {
    test('the registry no longer points at the gone GitHub repo', () {
      final def = kEmulatorDefinitions.firstWhere((d) => d['id'] == 'ryujinx');
      expect(def['type'], 'gitlab');
      expect(def['gitlab_host'], 'git.ryujinx.app');
      expect(def['gitlab_repo'], 'ryubing/ryujinx');
      expect(def.containsKey('github_repo'), isFalse);
    });

    test('the newest stable release\'s win_x64 zip, by its direct link', () {
      final got = ReleaseService.gitlabAssets([
        release('1.3.3', ['ryujinx-1.3.3-win_x64.zip', 'ryujinx-1.3.3-linux_x64.tar.gz', 'ryujinx-1.3.3-win_arm64.zip']),
        release('1.3.2', ['ryujinx-1.3.2-win_x64.zip']),
      ], windows, excluded);
      expect(got.single['name'], 'ryujinx-1.3.3-win_x64.zip');
      expect(got.single['url'], endsWith('/generic/Ryubing/1.3.3/ryujinx-1.3.3-win_x64.zip'));
    });

    test('an upcoming release, a canary or a release candidate is skipped, never offered', () {
      final got = ReleaseService.gitlabAssets([
        release('1.4.0', ['ryujinx-1.4.0-win_x64.zip'], upcoming: true),
        release('1.3.140-canary', ['ryujinx-canary-1.3.140-win_x64.zip']),
        release('1.3.4-rc1', ['ryujinx-1.3.4-rc1-win_x64.zip']),
        release('1.3.3', ['ryujinx-1.3.3-win_x64.zip']),
      ], windows, excluded);
      expect(got.single['name'], 'ryujinx-1.3.3-win_x64.zip');
    });

    test('a release with no Windows zip is passed over for an older one', () {
      final got = ReleaseService.gitlabAssets([
        release('1.3.4', ['ryujinx-1.3.4-linux_x64.tar.gz']),
        release('1.3.3', ['ryujinx-1.3.3-win_x64.zip']),
      ], windows, excluded);
      expect(got.single['name'], 'ryujinx-1.3.3-win_x64.zip');
    });

    test("GitLab's API: the project path encoded, newest releases first", () async {
      final api = _Api([release('1.3.3', ['ryujinx-1.3.3-win_x64.zip'])]);
      final got = await ReleaseService(Dio()..httpClientAdapter = api).getLatestReleaseAssets(
        platform: ReleasePlatform.gitlab,
        repo: 'ryubing/ryujinx',
        requiredFilters: windows,
        excludedFilters: excluded,
        baseUrl: 'https://git.ryujinx.app',
      );
      expect(api.asked.single.toString(), 'https://git.ryujinx.app/api/v4/projects/ryubing%2Fryujinx/releases?per_page=20');
      expect(got.single['name'], 'ryujinx-1.3.3-win_x64.zip');
    });
  });

  group('the profile', () {
    late AppRoot root;
    setUp(() async => root = await tempAppRoot());
    tearDown(() => deleteTempDir(root.root));

    LaunchContext ctx(String profile) {
      final exeDir = p.join(root.emulators, 'ryujinx', 'publish');
      io.Directory(exeDir).createSync(recursive: true);
      return LaunchContext(
        data: ProfilePaths(root, profile).emulatorDir('ryujinx'),
        exeDir: exeDir,
        bios: root.bios,
        profileId: profile,
        profilesDir: root.profiles,
        guard: PathGuard(root, activeProfileId: profile),
      );
    }

    test('-r <data>: the whole Ryujinx folder is the profile\'s', () async {
      final c = ctx('aaa');
      expect(await ProfileLaunchConfig.of('ryujinx')!.prepare(c), ['-r', c.data]);
      expect(Fullscreen.supports('ryujinx'), isTrue);
    });

    test('prod.keys and title.keys from bios\\ into the profile\'s system\\', () async {
      io.File(p.join(root.bios, 'switch', 'prod.keys'))
        ..createSync(recursive: true)
        ..writeAsStringSync('prod');
      final c = ctx('aaa');
      await ProfileLaunchConfig.of('ryujinx')!.prepare(c);
      expect(io.File(p.join(c.data, 'system', 'prod.keys')).readAsStringSync(), 'prod');
      expect(io.File(p.join(c.data, 'system', 'title.keys')).existsSync(), isFalse, reason: 'not in bios\\');
    });

    test("the profile's keys are its own copies: never replaced, and a change never reaches bios\\", () async {
      final shared = io.File(p.join(root.bios, 'switch', 'prod.keys'))
        ..createSync(recursive: true)
        ..writeAsStringSync('shared');
      final c = ctx('aaa');
      io.File(p.join(c.data, 'system', 'prod.keys'))
        ..createSync(recursive: true)
        ..writeAsStringSync("newer, the profile's own");
      await ProfileLaunchConfig.of('ryujinx')!.prepare(c);
      expect(io.File(p.join(c.data, 'system', 'prod.keys')).readAsStringSync(), "newer, the profile's own");
      final d = ctx('bbb');
      await ProfileLaunchConfig.of('ryujinx')!.prepare(d);
      io.File(p.join(d.data, 'system', 'prod.keys')).writeAsStringSync('Install Keys');
      expect(shared.readAsStringSync(), 'shared');
    });

    test('two profiles never share it', () async {
      final a = await ProfileLaunchConfig.of('ryujinx')!.prepare(ctx('aaa'));
      final b = await ProfileLaunchConfig.of('ryujinx')!.prepare(ctx('bbb'));
      expect(a.last, isNot(b.last));
      expect(EmulatorLayout.of('ryujinx').seed, containsAll(['bis/user/save', 'system']));
    });

    test("the save code looks in the profile's folder, not %APPDATA%\\Ryujinx", () async {
      final data = ProfilePaths(root, 'aaa').emulatorDir('ryujinx');
      final strategy = RyujinxSaveStrategy(profileRoot: () async => data);
      final game = Game(id: '1', name: 'Zelda', fsName: 'Zelda.nsp', platformSlug: 'switch', fileSize: 0);
      await expectLater(
        strategy.getSaveDir(game, p.join(root.roms, 'switch', 'Zelda.nsp')),
        throwsA(predicate((e) => '$e'.contains(p.join(data, 'bis', 'user', 'save')))),
      );
    });
  });

  group("a game's save, as Ryujinx keeps it", () {
    late AppRoot root;
    late String base;
    setUp(() async {
      root = await tempAppRoot();
      base = p.join(ProfilePaths(root, 'aaa').emulatorDir('ryujinx'), 'bis', 'user', 'save');
      io.Directory(base).createSync(recursive: true);
    });
    tearDown(() => deleteTempDir(root.root));

    /// bis\user\save\<id>\ with ExtraData0 for [title] (type 1 = a user's
    /// save) and a file in its committed 0\.
    void save(String id, String title, {int type = 1, String file = 'save.dat'}) {
      final extra = Uint8List(0x40);
      final t = BigInt.parse(title, radix: 16);
      for (var i = 0; i < 8; i++) {
        extra[i] = ((t >> (8 * i)) & BigInt.from(0xFF)).toInt();
      }
      extra[0x20] = type;
      io.File(p.join(base, id, 'ExtraData0'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(extra);
      io.File(p.join(base, id, '0', file))
        ..createSync(recursive: true)
        ..writeAsStringSync(title);
    }

    Game game(String title) => Game(id: title, name: 'G $title', platformSlug: 'switch', fileSize: 0, titleId: title);

    test('each game gets its own folder, never the newest one of another game', () async {
      save('0000000000000001', '0100000000010000');
      save('0000000000000002', '01007EF00011E000');
      final strategy = RyujinxSaveStrategy(profileRoot: () async => p.dirname(p.dirname(p.dirname(base))));
      expect(await strategy.getSaveDir(game('0100000000010000'), 'x.nsp'), p.join(base, '0000000000000001', '0'));
      expect(await strategy.getSaveDir(game('01007EF00011E000'), 'y.nsp'), p.join(base, '0000000000000002', '0'));
    });

    test("a user's save comes before a device or cache save of the same title", () {
      save('0000000000000003', '0100000000010000', type: 2);
      save('0000000000000004', '0100000000010000', type: 1);
      expect(RyujinxSaveStrategy.saveFolderFor(base, '0100000000010000'), p.join(base, '0000000000000004'));
    });

    test('no save made yet: no folder, and a pull says to start the game once', () async {
      save('0000000000000001', '0100000000010000');
      final strategy = RyujinxSaveStrategy(profileRoot: () async => p.dirname(p.dirname(p.dirname(base))));
      expect(await strategy.getSaveDir(game('01007EF00011E000'), 'y.nsp'), isNull);
      expect(await strategy.getSaveFiles(game('01007EF00011E000'), 'y.nsp'), isEmpty);
      await expectLater(
        strategy.restoreSave(game('01007EF00011E000'), 'y.nsp', Uint8List(4), 'save.dat'),
        throwsA(predicate((e) => '$e'.contains('start the game once'))),
      );
      expect(io.File(p.join(base, '0000000000000001', '0', 'save.dat')).readAsStringSync(), '0100000000010000',
          reason: "another game's save is never written over");
    });

    test("a restore goes into that game's committed folder", () async {
      save('0000000000000001', '0100000000010000');
      save('0000000000000002', '01007EF00011E000');
      final strategy = RyujinxSaveStrategy(profileRoot: () async => p.dirname(p.dirname(p.dirname(base))));
      await strategy.restoreSave(game('01007EF00011E000'), 'y.nsp', Uint8List.fromList(utf8.encode('from RomM')), 'save.dat');
      expect(io.File(p.join(base, '0000000000000002', '0', 'save.dat')).readAsStringSync(), 'from RomM');
      expect(io.File(p.join(base, '0000000000000001', '0', 'save.dat')).readAsStringSync(), '0100000000010000');
    });
  });
}
