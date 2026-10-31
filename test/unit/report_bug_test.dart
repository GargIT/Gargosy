import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/about_providers.dart';
import 'package:gargosy/ui/screens/settings/report_bug.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  late AppRoot root;

  void log(String name, String text) {
    io.Directory(root.logs).createSync(recursive: true);
    io.File(p.join(root.logs, name)).writeAsStringSync(text);
  }

  group('without the app', () {
    setUp(() async => root = await tempAppRoot());
    tearDown(() => io.Directory(root.root).deleteSync(recursive: true));

    test("the bug form with the versions in its fields; RomM's only when known", () {
      final url = bugFormUrl(version: '0.6.0', windows: 'Windows 11 26300', romm: '5.4.0');
      expect(url.host, 'github.com');
      expect(url.path, '/GargIT/Gargosy/issues/new');
      expect(url.queryParameters, {
        'template': 'bug_report.yml',
        'version': '0.6.0',
        'windows': 'Windows 11 26300',
        'romm': '5.4.0',
      });
      expect(bugFormUrl(version: '1', windows: 'w').queryParameters.containsKey('romm'), isFalse);
    });

    test('Windows 11 is told by its build, as Dart says Windows 10', () {
      expect(windowsName('"Windows 10 Home" 10.0 (Build 26300)'), '"Windows 11 Home" 10.0 (Build 26300)');
      expect(windowsName('"Windows 10 Pro" 10.0 (Build 19045)'), '"Windows 10 Pro" 10.0 (Build 19045)');
    });

    test('the last two logs in their order (a restart in the same second is newer), redacted again', () async {
      expect(await copyLogsForBug(root), isNull);
      log('gargosy-20261030-100000.log', 'oldest\n');
      log('gargosy-20261031-100000.log', 'crash\nAuthorization: Bearer abc123\n');
      log('gargosy-20261031-100000-2.log', 'restarted\n');
      final copy = (await copyLogsForBug(root))!;
      expect(p.dirname(copy), bugReportDir(root));
      final text = io.File(copy).readAsStringSync();
      expect(text, isNot(contains('oldest')));
      expect(text.indexOf('crash'), lessThan(text.indexOf('restarted')));
      expect(text, isNot(contains('abc123')));
    });
  });

  testWidgets('Report a bug opens the form first, then the folder with the copy', (tester) async {
    root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    log('gargosy-20261031-100000.log', 'line\n');
    final opened = <String>[];
    await tester.pumpWidget(
      testApp(
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => reportBug(context, ref, windows: 'w'),
            child: const Text('report'),
          ),
        ),
        root: root,
        overrides: [
          appPreferencesProvider.overrideWithValue(MemoryPrefs()),
          externalOpenerProvider.overrideWithValue(opened.add),
          rommServerVersionProvider.overrideWith((ref) async => '5.4.0'),
        ],
      ),
    );
    await tester.tap(find.text('report'));
    for (var i = 0; i < 20 && opened.length < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(opened.first, startsWith('https://github.com/GargIT/Gargosy/issues/new'));
    expect(opened.last, bugReportDir(root));
  });
}
