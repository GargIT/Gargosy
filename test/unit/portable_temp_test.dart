@TestOn('windows')
library;

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/portable_temp.dart';
import 'package:path/path.dart' as p;

void main() {
  test("temp files go to the Gargosy folder, not the user's AppData", () {
    final before = io.Directory.systemTemp.path;
    final mine = io.Directory.systemTemp.createTempSync('gargosy_tmp_test');
    addTearDown(() {
      usePortableTemp(before);
      mine.deleteSync(recursive: true);
    });
    final dir = p.join(mine.path, 'userdata', 'app', 'temp');
    usePortableTemp(dir);
    expect(p.equals(io.Directory.systemTemp.path, dir), isTrue);
    expect(io.Directory(dir).existsSync(), isTrue);
  });
}
