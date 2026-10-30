import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/shortcut_maker.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/game/make_shortcut.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

class _Maker implements ShortcutMaker {
  _Maker(this.desktop, {this.fails = false});
  final String desktop;
  final bool fails;
  List<String>? args;

  @override
  String get extension => '.lnk';

  @override
  Future<String?> desktopDir() async => desktop;

  @override
  Future<void> make({
    required String linkPath,
    required String target,
    required List<String> args,
    required String workingDir,
    String? iconPath,
    String description = '',
  }) async {
    if (fails) throw const io.FileSystemException('blocked');
    this.args = args;
    io.File(linkPath).writeAsStringSync('link');
  }
}

void main() {
  final game = Game.fromJson(gameJson(7564, 'Burnout 3: Takedown', fsName: 'Burnout 3 (USA).chd'));

  Future<void> pump(WidgetTester tester, _Maker maker, AppRoot root) async {
    final profile = Profile(
      id: 'aaa',
      name: 'Anna',
      colorIndex: 0,
      serverUrl: 'https://romm.example',
      rommUserId: 1,
      rommUsername: 'anna',
      createdAt: DateTime(2026),
    );
    final paths = ProfilePaths(root, 'aaa');
    await tester.pumpWidget(
      testApp(
        Consumer(
          builder: (context, ref, _) =>
              TextButton(onPressed: () => makeGameShortcut(context, ref, game), child: const Text('make')),
        ),
        root: root,
        overrides: [
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          shortcutMakerProvider.overrideWithValue(maker),
          rommHeartbeatEnabledProvider.overrideWithValue(false),
          appExecutableProvider.overrideWithValue(p.join(root.root, 'Gargosy.exe')),
          activeProfileProvider.overrideWith(
            (ref) => ActiveProfileNotifier(ref)
              ..state = ProfileContext(
                profile: profile,
                paths: paths,
                guard: paths.guard,
                login: const ProfileLogin(token: 't', kind: 'device'),
              ),
          ),
        ],
      ),
    );
    await tester.tap(find.text('make'));
    // The cover read, the icon and the link: real IO, then the toast.
    for (var i = 0; i < 100 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Create desktop shortcut: a link for this game in this profile, and says where', (tester) async {
    final root = (await tester.runAsync(tempAppRoot))!;
    final desktop = (await tester.runAsync(() => io.Directory.systemTemp.createTemp('desktop')))!;
    addTearDown(() {
      io.Directory(root.root).deleteSync(recursive: true);
      desktop.deleteSync(recursive: true);
    });
    final maker = _Maker(desktop.path);
    await pump(tester, maker, root);
    expect(maker.args, ['--play=7564', '--profile=aaa']);
    expect(find.text('Shortcut made on the desktop: Burnout 3 Takedown.lnk'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10)); // the toast goes
  });

  testWidgets('a shortcut that can\'t be made says why', (tester) async {
    final root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    await pump(tester, _Maker(root.root, fails: true), root);
    expect(find.textContaining('The shortcut couldn\'t be made'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}
