import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/update/update_version.dart';

void main() {
  test('the version comes from the asset name', () {
    expect(UpdateVersion.fromAsset('Gargosy-0.2.0.zip').toString(), '0.2.0');
    expect(UpdateVersion.fromAsset('Gargosy-0.2.0-preview.4.zip').toString(), '0.2.0-preview.4');
  });

  test('an asset name that is not a Gargosy zip gives null', () {
    expect(UpdateVersion.fromAsset('Gargosy-latest.zip'), isNull);
    expect(UpdateVersion.fromAsset('Source code (zip)'), isNull);
    expect(UpdateVersion.fromAsset('Gargosy-0.2.0.7z'), isNull);
    expect(UpdateVersion.fromAsset('Other-0.2.0.zip'), isNull);
  });

  test('semver order: preview.3 < preview.10 < the release', () {
    final p3 = UpdateVersion.parse('0.2.0-preview.3')!;
    final p9 = UpdateVersion.parse('0.2.0-preview.9')!;
    final p10 = UpdateVersion.parse('0.2.0-preview.10')!;
    final release = UpdateVersion.parse('0.2.0')!;
    expect(p3 < p10, isTrue);
    expect(p10 > p9, isTrue);
    expect(p10 < release, isTrue);
    expect(UpdateVersion.parse('0.3.0-preview.1')! > release, isTrue);
  });

  test('a leading v and build metadata are dropped', () {
    expect(UpdateVersion.parse('v0.2.0').toString(), '0.2.0');
    expect(UpdateVersion.parse('0.2.0-preview.4+1').toString(), '0.2.0-preview.4');
    expect(UpdateVersion.parse('0.1.0+1'), UpdateVersion.parse('0.1.0'));
    expect(UpdateVersion.parse(''), isNull);
    expect(UpdateVersion.parse('not a version'), isNull);
  });

  test('never a downgrade, and the same version is not newer', () {
    final installed = UpdateVersion.parse('0.2.0-preview.5')!;
    expect(UpdateVersion.isNewer(UpdateVersion.parse('0.1.0')!, installed), isFalse);
    expect(UpdateVersion.isNewer(UpdateVersion.parse('0.2.0-preview.5')!, installed), isFalse);
    expect(UpdateVersion.isNewer(UpdateVersion.parse('0.2.0-preview.6')!, installed), isTrue);
    expect(UpdateVersion.isNewer(UpdateVersion.parse('0.2.0')!, installed), isTrue);
  });
}
