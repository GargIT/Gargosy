import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/update/update_checker.dart';
import 'package:gargosy/update/update_version.dart';

import '../../helpers/github_fake.dart';
import '../../helpers/profile_test_env.dart';

void main() {
  late MemoryPrefs prefs;
  late FakeGitHub github;
  late DateTime now;

  setUp(() {
    prefs = MemoryPrefs();
    now = DateTime.utc(2026, 10, 12, 12);
    github = FakeGitHub((_) => const GitHubReply(500));
  });

  UpdateChecker checker(String installed) => UpdateChecker(
        dio: Dio()..httpClientAdapter = github,
        prefs: prefs,
        installed: UpdateVersion.parse(installed)!,
        clock: () => now,
      );

  group('Latest', () {
    test('asks releases/latest and offers a newer release', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0', digest: 'sha256:ABCDEF'));
      final result = await checker('0.1.0').check();
      expect(github.requests.single.uri.toString(), 'https://api.github.com/repos/GargIT/Gargosy/releases/latest');
      final release = (result! as UpdateAvailable).release;
      expect(release.version.toString(), '0.2.0');
      expect(release.sha256, 'abcdef');
      expect(release.size, 1000);
      expect(release.assetUrl, endsWith('/v0.2.0/Gargosy-0.2.0.zip'));
      expect(release.notes, 'Notes');
    });

    test('ignores a pre-release even if GitHub returned one', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0-preview.4', prerelease: true));
      expect(await checker('0.1.0').check(), isA<UpToDate>());
    });

    test('from a preview, an older release is not offered: no downgrade', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.1.0'));
      final result = await checker('0.2.0-preview.4').check() as UpToDate;
      expect(result.newest.toString(), '0.1.0', reason: 'the UI says why nothing is offered');
    });

    test('the same version is up to date', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.1.0'));
      expect(await checker('0.1.0').check(), isA<UpToDate>());
    });
  });

  group('Preview', () {
    setUp(() => prefs.values[UpdatePrefs.channel] = 'preview');

    test('picks the newest of releases and pre-releases', () async {
      github.handler = (r) => GitHubReply(200, [
            githubRelease('0.2.0-preview.12', prerelease: true, tag: 'v0.2.0-preview'),
            githubRelease('0.1.0'),
            githubRelease('0.1.1'),
          ]);
      final result = await checker('0.1.0').check() as UpdateAvailable;
      expect(github.requests.single.uri.toString(), 'https://api.github.com/repos/GargIT/Gargosy/releases?per_page=10');
      expect(result.release.version.toString(), '0.2.0-preview.12');
      expect(result.release.prerelease, isTrue);
    });

    test('once 0.2.0 ships, a preview user gets 0.2.0', () async {
      github.handler = (r) => GitHubReply(200, [
            githubRelease('0.2.0'),
            githubRelease('0.2.0-preview.12', prerelease: true, tag: 'v0.2.0-preview'),
          ]);
      final result = await checker('0.2.0-preview.12').check() as UpdateAvailable;
      expect(result.release.version.toString(), '0.2.0');
    });

    test('preview.10 is newer than preview.9', () async {
      github.handler = (r) => GitHubReply(200, [githubRelease('0.2.0-preview.10', prerelease: true)]);
      expect(await checker('0.2.0-preview.9').check(), isA<UpdateAvailable>());
    });

    test('drafts and releases without a Gargosy zip are skipped', () async {
      final noZip = githubRelease('0.4.0')..['assets'] = [];
      github.handler = (r) => GitHubReply(200, [githubRelease('0.3.0', draft: true), noZip, githubRelease('0.1.0')]);
      expect(await checker('0.1.0').check(), isA<UpToDate>());
    });

    test('while the preview is rebuilt, the list has only the release: nothing older is offered', () async {
      github.handler = (r) => GitHubReply(200, [githubRelease('0.1.0')]);
      expect(await checker('0.2.0-preview.4').check(), isA<UpToDate>());
    });
  });

  group('limits', () {
    test('a second check within 6 h answers from the last one without asking GitHub', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0'));
      expect(await checker('0.1.0').check(), isA<UpdateAvailable>());
      now = now.add(const Duration(hours: 5));
      expect(await checker('0.1.0').check(), isA<UpdateAvailable>());
      expect(github.requests, hasLength(1));
    });

    test('Check now (force) asks again within 6 h; after 6 h it asks by itself', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0'));
      await checker('0.1.0').check();
      await checker('0.1.0').check(force: true);
      expect(github.requests, hasLength(2));
      now = now.add(const Duration(hours: 7));
      await checker('0.1.0').check();
      expect(github.requests, hasLength(3));
    });

    test('the ETag is sent back, and a 304 keeps the last answer', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0'), {'etag': 'W/"abc"'});
      await checker('0.1.0').check();
      github.handler = (r) => const GitHubReply(304);
      final again = await checker('0.1.0').check(force: true);
      expect(github.requests.last.headers['If-None-Match'], 'W/"abc"');
      expect((again! as UpdateAvailable).release.version.toString(), '0.2.0');
    });

    test('a 304 is compared with the running version again (it may have been updated since)', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0'), {'etag': '"e"'});
      await checker('0.1.0').check();
      github.handler = (r) => const GitHubReply(304);
      expect(await checker('0.2.0').check(force: true), isA<UpToDate>());
    });

    test("the other channel's ETag and answer are never used", () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0'), {'etag': '"latest"'});
      await checker('0.1.0').check();
      prefs.values[UpdatePrefs.channel] = 'preview';
      github.handler = (r) => GitHubReply(200, [githubRelease('0.2.0-preview.3', prerelease: true)]);
      final result = await checker('0.1.0').check(force: true); // the channel switch checks at once
      expect(github.requests.last.headers.containsKey('If-None-Match'), isFalse);
      expect((result! as UpdateAvailable).release.version.toString(), '0.2.0-preview.3');
    });

    test('within 6 h after a channel switch, nothing is known yet: null, no request', () async {
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0'));
      await checker('0.1.0').check();
      prefs.values[UpdatePrefs.channel] = 'preview';
      expect(await checker('0.1.0').check(), isNull);
      expect(github.requests, hasLength(1));
    });
  });

  group("couldn't check", () {
    test('offline', () async {
      github.handler = (r) => const GitHubReply.offline();
      expect((await checker('0.1.0').check() as CheckFailed).reason, contains("Couldn't reach GitHub"));
    });

    test('404: no release yet, or a preview being rebuilt', () async {
      github.handler = (r) => const GitHubReply(404, {'message': 'Not Found'});
      expect((await checker('0.1.0').check() as CheckFailed).reason, contains('no release on this channel'));
    });

    test('403 rate limit', () async {
      github.handler = (r) => const GitHubReply(403, {'message': 'API rate limit exceeded'});
      expect((await checker('0.1.0').check() as CheckFailed).reason, contains('limit'));
    });

    test('a body that is not what GitHub sends', () async {
      prefs.values[UpdatePrefs.channel] = 'preview';
      github.handler = (r) => const GitHubReply(200, {'not': 'a list'});
      expect(await checker('0.1.0').check(), isA<CheckFailed>());
    });

    test('a failed check is not remembered as a check: the next start asks again', () async {
      github.handler = (r) => const GitHubReply.offline();
      await checker('0.1.0').check();
      github.handler = (r) => GitHubReply(200, githubRelease('0.2.0'));
      expect(await checker('0.1.0').check(), isA<UpdateAvailable>());
    });
  });

  test('settings: Latest and automatic checks by default', () async {
    final c = checker('0.1.0');
    expect(c.channel, UpdateChannel.latest);
    expect(c.autoCheck, isTrue);
    await c.setChannel(UpdateChannel.preview);
    await c.setAutoCheck(false);
    expect(prefs.values[UpdatePrefs.channel], 'preview');
    expect(prefs.values[UpdatePrefs.autoCheck], false);
  });
}
