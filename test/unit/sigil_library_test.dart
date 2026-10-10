import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/sigil/sigil_library.dart';

void main() {
  test('sigil.dll loads and is the pinned version', () => expect(sigilVersion(), '1.0.0'));

  test('a missing sigil.dll is a clear error naming the file', () {
    final was = SigilLibrary.path;
    addTearDown(() => SigilLibrary.path = was);
    SigilLibrary.path = r'C:\nowhere\sigil.dll';
    expect(
      () => SigilLibrary.open(),
      throwsA(isA<SigilUnavailable>().having((e) => '$e', 'message', contains(r'C:\nowhere\sigil.dll'))),
    );
  });

  test('a sigil.dll of another version than Gargosy was built for is refused, naming both', () {
    expect(
      () => SigilLibrary.checkVersion(r'C:\x\sigil.dll', '1.1.0'),
      throwsA(
        isA<SigilUnavailable>().having((e) => '$e', 'message', allOf(contains('1.1.0'), contains(sigilPinnedVersion))),
      ),
    );
    SigilLibrary.checkVersion(r'C:\x\sigil.dll', sigilPinnedVersion); // the pinned one passes
  });
}
