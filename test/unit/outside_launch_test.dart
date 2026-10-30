import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/play/outside_launch.dart';
import 'package:gargosy/profiles/profile.dart';

Profile _p(String id) => Profile(
  id: id,
  name: id,
  colorIndex: 0,
  serverUrl: 'https://romm.example',
  rommUserId: 1,
  rommUsername: id,
  createdAt: DateTime(2026),
);

void main() {
  test('reads --play, --profile and --play-stay', () {
    final l = OutsideLaunch.parse(['--root=x', '--play=7564', '--profile=0f8e-4b2a', '--play-stay'])!;
    expect(l.romId, '7564');
    expect(l.profileId, '0f8e-4b2a');
    expect(l.stay, isTrue);
    final plain = OutsideLaunch.parse(['--play=12'])!;
    expect(plain.profileId, isNull);
    expect(plain.stay, isFalse);
  });

  test('no launch without --play, or with a rom id or profile id that is not one', () {
    for (final args in [
      <String>[],
      ['--fullscreen'],
      ['--play='],
      ['--play=abc'],
      [r'--play=..\x'],
      ['--play=1', '--profile=..'],
      ['--play=1', r'--profile=a\b'],
    ]) {
      expect(OutsideLaunch.parse(args), isNull, reason: '$args');
    }
  });

  test('the profile: the one named, else the only one; several and none named: the player picks', () {
    final a = _p('aaa'), b = _p('bbb');
    expect(const OutsideLaunch(romId: '1', profileId: 'bbb').profileIn([a, b]), b);
    expect(const OutsideLaunch(romId: '1', profileId: 'ccc').profileIn([a, b]), isNull);
    expect(const OutsideLaunch(romId: '1').profileIn([a]), a);
    expect(const OutsideLaunch(romId: '1').profileIn([a, b]), isNull);
  });
}
