import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/ui/screens/settings/report_bug.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
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

  test('the newest log, redacted again, beside the logs folder; none without logs', () {
    expect(copyNewestLog(root), isNull);
    io.Directory(root.logs).createSync(recursive: true);
    io.File(p.join(root.logs, 'gargosy-20261030-100000.log')).writeAsStringSync('old\n');
    io.File(p.join(root.logs, 'gargosy-20261031-100000.log')).writeAsStringSync('new\nAuthorization: Bearer abc123\n');
    final copy = copyNewestLog(root)!;
    expect(p.dirname(copy), root.appData);
    final text = io.File(copy).readAsStringSync();
    expect(text, startsWith('new'));
    expect(text, isNot(contains('abc123')));
  });
}
