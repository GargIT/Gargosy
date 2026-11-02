import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/notifications.dart';

import '../helpers/profile_test_env.dart';

Map<String, dynamic> _share(int id, String who) => {'id': id, 'user_id': 7, 'username': who};

void main() {
  group('SharedSeen', () {
    test('the first look at a game takes what it has as seen; what comes after is news, once', () async {
      final seen = SharedSeen(MemoryPrefs());
      final old = SharedItem.of('12', [_share(1, 'Anna')], states: false);
      expect(await seen.news('12', old), isEmpty);
      expect(await seen.news('12', old), isEmpty);

      final now = [
        ...old,
        ...SharedItem.of('12', [_share(5, 'Anna')], states: true),
      ];
      final news = await seen.news('12', now);
      expect(news.map((i) => i.key), ['state:5']);
      expect(await seen.news('12', now), isEmpty);
    });

    test('kept in the profile\'s prefs: another start remembers it', () async {
      final prefs = MemoryPrefs();
      await SharedSeen(prefs).news('12', SharedItem.of('12', [_share(1, 'Anna')], states: false));
      final news = await SharedSeen(prefs)
          .news('12', SharedItem.of('12', [_share(1, 'Anna'), _share(2, 'Bo')], states: false));
      expect(news.map((i) => i.username), ['Bo']);
    });

    test('games looked at side by side don\'t lose each other\'s records', () async {
      final prefs = MemoryPrefs();
      final seen = SharedSeen(prefs);
      await Future.wait([
        for (final g in ['1', '2', '3', '4'])
          seen.news(g, SharedItem.of(g, [_share(int.parse(g), 'Anna')], states: false)),
      ]);
      final again = SharedSeen(prefs);
      for (final g in ['1', '2', '3', '4']) {
        expect(
          await again.news(
            g,
            SharedItem.of(g, [_share(int.parse(g), 'Anna'), _share(90 + int.parse(g), 'Bo')], states: false),
          ),
          hasLength(1),
          reason: 'game $g was looked at before',
        );
      }
    });

    test('no profile prefs: nothing is news', () async {
      expect(await SharedSeen(null).news('1', SharedItem.of('1', [_share(1, 'A')], states: false)), isEmpty);
    });
  });

  test('a share without a name is another player\'s; an item without an id is left out', () {
    final items = SharedItem.of('3', [
      {'id': 4, 'username': ' '},
      {'username': 'x'},
    ], states: false);
    expect(items.map((i) => i.username), ['Another player']);
  });

  test('NoticeQueue: in order, taken one at a time; nothing kept while off', () {
    final q = NoticeQueue(on: true)
      ..post(const Notice('a'))
      ..post(const Notice('b'));
    expect(q.take()?.text, 'a');
    expect(q.take()?.text, 'b');
    expect(q.take(), isNull);
    final off = NoticeQueue(on: false)..post(const Notice('c'));
    expect(off.state, isEmpty);
  });

  test('NoticeQueue: finished downloads next to each other become one notice; at most 20 wait', () {
    final q = NoticeQueue(on: true)
      ..post(Notice.downloaded('1', 'Okami'))
      ..post(Notice.downloaded('2', 'Ico'))
      ..post(Notice.downloaded('3', 'Rez'))
      ..post(Notice.uploaded(1))
      ..post(Notice.downloaded('4', 'Gish'));
    expect(q.state.map((n) => n.text), [
      '3 downloads finished.',
      'Uploaded 1 save that was waiting.',
      'Gish is downloaded.',
    ]);
    for (var i = 0; i < 30; i++) {
      q.post(Notice('n$i'));
    }
    expect(q.state, hasLength(NoticeQueue.cap));
    expect(q.state.last.text, 'n29');
  });

  test('nextRound: every game in turn, going round', () {
    final ids = ['a', 'b', 'c', 'd', 'e'];
    var (picked, cursor) = nextRound(ids, 0, 2);
    expect(picked, ['a', 'b']);
    (picked, cursor) = nextRound(ids, cursor, 2);
    expect(picked, ['c', 'd']);
    (picked, cursor) = nextRound(ids, cursor, 2);
    expect(picked, ['e', 'a']);
    expect(nextRound(['a'], 7, 20).$1, ['a']);
    expect(nextRound(const [], 3, 20).$1, isEmpty);
  });

  test('SharedSeen: one game with many shares never pushes out what another has seen', () async {
    final seen = SharedSeen(MemoryPrefs());
    await seen.news('1', SharedItem.of('1', [_share(1, 'Anna')], states: false));
    await seen.news('2', SharedItem.of('2', [for (var i = 10; i < 1500; i++) _share(i, 'Bo')], states: false));
    final news = await seen.news('1', SharedItem.of('1', [_share(1, 'Anna'), _share(2, 'Anna')], states: false));
    expect(news.map((i) => i.key), ['save:2'], reason: 'game 1 is still remembered: its new share is news');
  });

  test('a name that is not text is still a name', () {
    expect(
      SharedItem.of('1', [
        {'id': 1, 'username': 42},
      ], states: false).single.username,
      '42',
    );
  });

  test('ShareWatch: each game read once, its new shares said with the game\'s name', () async {
    final asked = <String>[];
    final said = <String>[];
    var round = 0;
    final watch = ShareWatch(
      seen: SharedSeen(MemoryPrefs()),
      shared: (id) async {
        asked.add(id);
        if (id == '9') return null; // RomM couldn't say
        return (saves: [_share(1, 'Anna'), if (round > 0) _share(2, 'Anna')], states: [if (round > 0) _share(3, 'Bo')]);
      },
      post: (n) => said.add(n.text),
    );
    await watch.check({'1': 'Okami', '9': 'Ico'});
    expect(said, isEmpty, reason: 'the first look only remembers');
    round = 1;
    await watch.check({'1': 'Okami'});
    expect(said, ['Anna shared a save of Okami.', 'Bo shared a save state of Okami.']);
    expect(asked, ['1', '9', '1']);
  });
}
