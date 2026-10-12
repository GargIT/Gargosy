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
}
