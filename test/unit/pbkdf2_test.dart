import 'dart:convert';

import 'package:convert/convert.dart' show hex;
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/pbkdf2.dart';

void main() {
  String run(int c) => hex.encode(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), c, 32));

  test('known vectors', () {
    expect(run(1), '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(run(2), 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    expect(run(4096), 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
  });

  test('lengths beyond one block', () {
    expect(pbkdf2Sha256(utf8.encode('p'), utf8.encode('s'), 1, 40).length, 40);
  });
}
