import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/providers/retry.dart';
import 'package:gargosy/core/constants/app_constants.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/about_providers.dart';
import 'package:gargosy/providers/update_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/settings/about_section.dart';
import 'package:gargosy/ui/screens/settings/settings_pages.dart';
import 'package:gargosy/ui/screens/settings/updates_block.dart';
import 'package:gargosy/ui/shell/user_menu.dart';
import 'package:gargosy/ui/widgets/update_dot.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
import 'package:gargosy/update/update_checker.dart';
import 'package:gargosy/update/update_installer.dart';
import 'package:gargosy/update/update_version.dart';
import 'package:path/path.dart' as p;

import '../helpers/github_fake.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

const _zipUrl = 'https://github.com/GargIT/Gargosy/releases/download/v0.2.0/Gargosy-0.2.0.zip';

/// GitHub's API and its release download, from one adapter.
class _GitHub implements HttpClientAdapter {
  _GitHub(this.zip);
  final Uint8List zip;
  Object? releases;
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    asked.add(url);
    if (url == _zipUrl) {
      return ResponseBody.fromBytes(
        zip,
        200,
        headers: {
          Headers.contentLengthHeader: ['${zip.length}'],
        },
      );
    }
    if (releases == null) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    return ResponseBody.fromString(
      jsonEncode(releases),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _releaseZip() {
  final archive = Archive();
  void add(String name, String text) {
    final data = Uint8List.fromList(utf8.encode(text));
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  add('Gargosy/Gargosy.exe', 'MZ new');
  add('Gargosy/app-files.txt', 'Gargosy.exe\r\napp-files.txt\r\n');
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late AppRoot root;
  late _GitHub github;
  late MemoryPrefs prefs;
  late ProviderContainer c;
  late List<List<String>> updaterStarts;
  late int quits;
  late List<String> opened;

  Future<void> settle(WidgetTester tester, [int rounds = 30]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester tester, {bool shipUpdater = true, Map<String, String> env = const {}}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    if (shipUpdater) io.File(p.join(root.root, 'GargosyUpdate.exe')).writeAsStringSync('MZ updater');
    final zip = _releaseZip();
    github = _GitHub(zip)
      ..releases = githubRelease('0.2.0', size: zip.length, body: '## Changes\n\n- Updates in the app');
    prefs = MemoryPrefs();
    updaterStarts = [];
    quits = 0;
    opened = [];
    AppConstants.version = '0.1.0';
    c = ProviderContainer(
      retry: noRetry,
      overrides: [
        appRootProvider.overrideWithValue(root),
        appPreferencesProvider.overrideWithValue(prefs),
        updateDioProvider.overrideWithValue(Dio()..httpClientAdapter = github),
        installedVersionProvider.overrideWithValue(UpdateVersion.parse('0.1.0')!),
        appUpdaterProvider.overrideWith(
          (ref) => UpdateInstaller(
            root: root,
            pid: 77,
            args: const ['--fullscreen'],
            currentVersion: '0.1.0',
            platform: PlatformInfo('windows', environment: env),
            start: (exe, args) async => updaterStarts.add([exe, ...args]),
          ),
        ),
        appQuitProvider.overrideWithValue(() async => quits++),
        externalOpenerProvider.overrideWithValue(opened.add),
        rommServerVersionProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(c.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          navigatorKey: nav,
          theme: gargosyTheme(),
          builder: (context, child) => InputRouter(navigatorKey: nav, startGamepads: false, child: child!),
          home: const Scaffold(body: SingleChildScrollView(child: AboutSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> checkNow(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Check now'));
    await tester.tap(find.text('Check now'));
    await settle(tester);
  }

  String status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('update-status'))).data!;

  testWidgets('before a check, then up to date', (tester) async {
    await pump(tester);
    expect(status(tester), 'Not checked yet.');
    github.releases = githubRelease('0.1.0');
    await checkNow(tester);
    expect(status(tester), 'Gargosy is up to date.');
    expect(find.byKey(const Key('update-now')), findsNothing);
  });

  testWidgets("couldn't check is a line, not a dialog", (tester) async {
    await pump(tester);
    github.releases = null;
    await checkNow(tester);
    expect(status(tester), startsWith("Couldn't check: Couldn't reach GitHub"));
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('available → confirm → download → the updater starts and Gargosy quits', (tester) async {
    await pump(tester);
    await checkNow(tester);
    expect(status(tester), '0.2.0 is available.');
    await tester.ensureVisible(find.byKey(const Key('update-now')));
    await tester.tap(find.byKey(const Key('update-now')));
    await tester.pumpAndSettle();
    expect(find.text('Update to 0.2.0?'), findsOneWidget);
    expect(find.textContaining('Your games, emulators and saves are not touched'), findsOneWidget);
    inputActionBus.add(GameAction.confirm); // A on Update (it has focus); the progress never settles
    await settle(tester, 60);
    expect(updaterStarts, hasLength(1));
    final args = updaterStarts.single;
    expect(args.first, p.join(root.appData, 'update', 'GargosyUpdate.exe'));
    expect(
      args,
      containsAllInOrder(['--pid', '77', '--from', p.join(root.appData, 'update', 'Gargosy'), '--version', '0.2.0']),
    );
    expect(args.last, '--fullscreen');
    expect(io.File(p.join(root.appData, 'update', 'Gargosy', 'Gargosy.exe')).existsSync(), isTrue);
    expect(quits, 1);
    expect(find.text('Restarting…'), findsOneWidget);
  });

  testWidgets('B at the question changes nothing', (tester) async {
    await pump(tester);
    await checkNow(tester);
    await tester.ensureVisible(find.byKey(const Key('update-now')));
    await tester.tap(find.byKey(const Key('update-now')));
    await tester.pumpAndSettle();
    await press(tester, GameAction.back);
    await settle(tester);
    expect(updaterStarts, isEmpty);
    expect(github.asked.where((u) => u == _zipUrl), isEmpty);
  });

  testWidgets('refused while a game runs', (tester) async {
    await pump(tester);
    await checkNow(tester);
    c.read(playControllerProvider.notifier).state = const PlayState(runningGameId: '1');
    await tester.ensureVisible(find.byKey(const Key('update-now')));
    await tester.tap(find.byKey(const Key('update-now')));
    await tester.pumpAndSettle();
    expect(find.text('Update to 0.2.0?'), findsNothing);
    expect(find.textContaining("can't update while a game runs"), findsOneWidget);
  });

  testWidgets('without the updater (0.1.0): no Update now, the release page instead', (tester) async {
    await pump(tester, shipUpdater: false);
    await checkNow(tester);
    expect(find.byKey(const Key('update-now')), findsNothing);
    expect(find.textContaining('update it by hand'), findsOneWidget);
    await tester.ensureVisible(find.text('Open the release page'));
    await tester.tap(find.text('Open the release page'));
    await tester.pump();
    expect(opened.single, 'https://github.com/GargIT/Gargosy/releases/tag/v0.2.0');
  });

  testWidgets('hidden in Program Files', (tester) async {
    // The drive the test's Gargosy folder is on (the system temp folder's):
    // '/' is the current drive, which on CI isn't the temp folder's.
    await pump(tester, env: {'ProgramFiles': p.rootPrefix(io.Directory.systemTemp.path)});
    await checkNow(tester);
    expect(find.byKey(const Key('update-now')), findsNothing);
    expect(find.textContaining('Windows protects'), findsOneWidget);
  });

  testWidgets('the channel: Preview asks for the list at once', (tester) async {
    await pump(tester);
    github.releases = [githubRelease('0.2.0-preview.7', prerelease: true, tag: 'v0.2.0-preview')];
    await tester.ensureVisible(find.text('Latest'));
    await tester.tap(find.text('Latest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview').last);
    await settle(tester);
    expect(prefs.values[UpdatePrefs.channel], 'preview');
    expect(github.asked.last, endsWith('/releases?per_page=10'));
    expect(status(tester), '0.2.0-preview.7 is available.');
  });

  testWidgets('a release older than the running preview is not offered, and the line says why', (tester) async {
    await pump(tester);
    github.releases = githubRelease('0.0.9');
    await checkNow(tester);
    expect(status(tester), contains('never goes back'));
  });

  testWidgets('release notes open in the reader', (tester) async {
    await pump(tester);
    await checkNow(tester);
    await tester.ensureVisible(find.text("What's in 0.2.0"));
    await tester.tap(find.text("What's in 0.2.0"));
    await settle(tester);
    expect(find.text('Updates in the app', findRichText: true), findsOneWidget);
  });

  testWidgets('Check automatically is on by default and can be turned off', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Check automatically'));
    await tester.tap(find.text('Check automatically'));
    await tester.pumpAndSettle();
    expect(prefs.values[UpdatePrefs.autoCheck], false);
  });

  test('the line in About after an update', () {
    expect(updateOutcomeLine(null, '0.2.0'), isNull);
    expect(updateOutcomeLine(const UpdatedFrom('0.1.0'), '0.2.0'), 'Updated from v0.1.0 to v0.2.0.');
    expect(
      updateOutcomeLine(const UpdateFailed('Failed: x is locked.'), '0.1.0'),
      "The update couldn't be installed: Failed: x is locked.",
    );
  });

  testWidgets('the dot shows only while an update is available', (tester) async {
    await pump(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: UpdateDot(child: SizedBox(width: 34, height: 34))),
      ),
    );
    expect(find.byKey(const Key('update-dot')), findsNothing);
    await tester.runAsync(() => c.read(updateStateProvider.notifier).checkNow());
    await tester.pump();
    expect(find.byKey(const Key('update-dot')), findsOneWidget);
  });

  testWidgets("the user menu's Update available opens About", (tester) async {
    final profile = Profile(
      id: 'p1',
      name: 'Ann',
      colorIndex: 0,
      serverUrl: 'https://romm.local',
      rommUserId: 1,
      rommUsername: 'ann',
      createdAt: DateTime(2026),
    );
    UserMenuChoice? picked;
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        child: MaterialApp(
          theme: gargosyTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await showUserMenu(context, profile: profile, update: 'Update available: 0.2.0'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Update available: 0.2.0'));
    await tester.tap(find.text('Update available: 0.2.0'));
    await tester.pumpAndSettle();
    expect(picked, const UserMenuChoice.settings(SettingsPage.about));
  });
}
