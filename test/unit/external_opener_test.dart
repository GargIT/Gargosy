import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/external_opener.dart';

void main() {
  test('only an http(s) address or a folder that is there may be opened outside', () {
    final dir = io.Directory.systemTemp.createTempSync('opener');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = io.File('${dir.path}${io.Platform.pathSeparator}run.bat')..writeAsStringSync('@echo off');

    expect(
      mayOpenOutside('https://github.com/GargIT/Gargosy/issues/new?template=bug_report.yml&version=0.6.0'),
      isTrue,
    );
    expect(mayOpenOutside('http://romm.example/rom/12'), isTrue);
    expect(mayOpenOutside(dir.path), isTrue);

    expect(mayOpenOutside(file.path), isFalse, reason: 'a file, a program or a script');
    expect(mayOpenOutside(file.uri.toString()), isFalse, reason: 'file:');
    expect(mayOpenOutside('ms-settings:privacy'), isFalse);
    expect(mayOpenOutside('search-ms:query=x'), isFalse);
    expect(mayOpenOutside('https:'), isFalse, reason: 'no host');
    expect(mayOpenOutside('${dir.path}-not-there'), isFalse);
  });
}
