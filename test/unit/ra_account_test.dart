import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:gargosy/core/retroachievements/retroachievements_models.dart';
import 'package:gargosy/retroachievements/ra_account.dart';

import '../helpers/profile_test_env.dart';

void main() {
  late MemoryPrefs prefs;
  late RaAccount account;
  String? refuse;

  setUp(() {
    prefs = MemoryPrefs();
    refuse = null;
    account = RaAccount(
      prefs,
      fetchToken: (u, p) async {
        if (refuse != null) throw RetroAchievementsAuthException(refuse!);
        return (username: u, token: 'tok-$u');
      },
    );
  });

  test('connect keeps the username and the token, never the password', () async {
    await account.connect('anna', 'hunter2');
    expect(account.username, 'anna');
    final login = await RetroAchievementsEmulatorLogin.load(prefs);
    expect(login?.token, 'tok-anna');
    expect(prefs.values.values.whereType<String>().any((v) => v.contains('hunter2')), isFalse);
  });

  test('a refused login stores nothing and says why', () async {
    refuse = 'Invalid username or password.';
    await expectLater(account.connect('anna', 'nope'), throwsA(isA<RetroAchievementsAuthException>()));
    expect(account.username, isNull);
    expect(await RetroAchievementsEmulatorLogin.load(prefs), isNull);
  });

  test('hardcore is off until turned on; disconnect forgets the login', () async {
    await account.connect('anna', 'hunter2');
    expect(account.hardcore, isFalse);
    await account.setHardcore(true);
    expect((await RetroAchievementsEmulatorLogin.load(prefs))?.hardcore, isTrue);
    await account.disconnect();
    expect(account.username, isNull);
    expect(await RetroAchievementsEmulatorLogin.load(prefs), isNull);
  });

  test("disconnect also signs the profile's emulators out", () async {
    var signedOut = 0;
    final a = RaAccount(
      prefs,
      fetchToken: (u, p) async => (username: u, token: 't'),
      signOutEmulators: () async => signedOut++,
    );
    await a.connect('anna', 'pw');
    await a.disconnect();
    expect(signedOut, 1);
  });
}
