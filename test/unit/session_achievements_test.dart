import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:gargosy/core/retroachievements/retroachievements_game_models.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/play/session_achievements.dart';
import 'package:gargosy/retroachievements/ra_account.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/fake_secret_store.dart';

const _all = [
  RetroAchievement(id: 1, title: 'First', description: '', points: 5, badgeName: 'b1'),
  RetroAchievement(id: 2, title: 'Second', description: '', points: 10, badgeName: 'b2'),
  RetroAchievement(id: 3, title: 'Third', description: '', points: 25, badgeName: 'b3'),
];

Map<String, dynamic> _entry(Map<String, String?> earned) => {
  'rom_ra_id': 77,
  'earned_achievements': [
    for (final id in earned.keys) {'id': id, 'date': '2026-10-27 20:00:00', 'date_hardcore': earned[id]},
  ],
};

class _Progress implements AchievementProgress {
  _Progress(this.answers);

  /// What each read of the progress gives, in turn.
  final List<Map<int, Map<String, dynamic>>?> answers;
  final calls = <String>[];

  @override
  Future<Map<int, Map<String, dynamic>>?> progression() async {
    calls.add('read');
    return answers.removeAt(0);
  }

  @override
  Future<bool> refresh(int userId) async {
    calls.add('refresh $userId');
    return true;
  }
}

Game _game({bool ra = true}) => Game.fromJson({
  ...gameJson(9, 'Sonic'),
  if (ra) 'ra_id': 77,
  'merged_ra_metadata': {'achievements': _all.map((a) => a.toRommJson()).toList()},
});

RaAccount _account({bool connected = true, bool hardcore = false}) {
  final prefs = MemoryPrefs();
  if (connected) prefs.values[kRaUsernameKey] = 'henrik';
  prefs.values[kRaHardcoreKey] = hardcore;
  return RaAccount(prefs, secrets: FakeSecretStore(), fetchToken: (u, p) async => (username: u, token: 't'));
}

void main() {
  test('only what is earned now and not before; badge names are the ids', () {
    final earned = earnedBetween(_entry({'b1': null}), _entry({'b1': null, 'b3': null}), _all);
    expect(earned.map((a) => a.title), ['Third']);
    expect(earnedBetween(null, _entry({'b2': null}), _all).map((a) => a.id), [2], reason: 'first time played');
    expect(earnedBetween(_entry({'b2': null}), _entry({'b2': null}), _all), isEmpty);
  });

  test('in hardcore, one earned in softcore before and in hardcore now counts', () {
    final before = _entry({'b1': null});
    final after = _entry({'b1': '2026-10-27 21:00:00'});
    expect(earnedBetween(before, after, _all, hardcore: true).map((a) => a.id), [1]);
    expect(earnedBetween(before, after, _all), isEmpty);
  });

  test('the line says how many, their points and the mode', () {
    expect(
      SessionAchievements('9', _all.sublist(0, 2), hardcore: false).line,
      '2 achievements earned · 15 points (softcore)',
    );
    expect(SessionAchievements('9', [_all.last], hardcore: true).line, '1 achievement earned · 25 points (hardcore)');
  });

  test('a session reads progress before, then asks RomM to read RA again and compares', () async {
    final progress = _Progress([
      {
        77: _entry({'b1': null}),
      },
      {
        77: _entry({'b1': null, 'b2': null}),
      },
    ]);
    final watch = SessionAchievementsWatch.start(_game(), progress: progress, userId: 7, account: _account())!;
    final got = await watch.finish();
    expect(progress.calls, ['read', 'refresh 7', 'read']);
    expect(got!.earned.map((a) => a.id), [2]);
    expect(got.gameId, '9');
  });

  test('nothing when RomM could not say before, or nothing was earned', () async {
    final unknown = _Progress([null, {}]);
    expect(
      await SessionAchievementsWatch.start(_game(), progress: unknown, userId: 7, account: _account())!.finish(),
      isNull,
    );
    final same = _Progress([
      {
        77: _entry({'b1': null}),
      },
      {
        77: _entry({'b1': null}),
      },
    ]);
    expect(
      await SessionAchievementsWatch.start(_game(), progress: same, userId: 7, account: _account())!.finish(),
      isNull,
    );
  });

  test('no watch without RA on the game, an RA login, RomM, or a RomM user', () {
    final p = _Progress([]);
    expect(SessionAchievementsWatch.start(_game(ra: false), progress: p, userId: 7, account: _account()), isNull);
    expect(
      SessionAchievementsWatch.start(_game(), progress: p, userId: 7, account: _account(connected: false)),
      isNull,
    );
    expect(SessionAchievementsWatch.start(_game(), progress: null, userId: 7, account: _account()), isNull);
    expect(SessionAchievementsWatch.start(_game(), progress: p, userId: null, account: _account()), isNull);
    expect(p.calls, isEmpty);
  });
}
