import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/pages/home/home_reveal.dart';

void main() {
  const step = Duration(milliseconds: 100);

  ProviderContainer container() => ProviderContainer(overrides: [homeRevealStepProvider.overrideWithValue(step)]);

  test('the rows wait for the header art, then come one a step, then all stay', () {
    fakeAsync((async) {
      final c = container();
      final sub = c.listen(homeRowsShownProvider, (_, _) {});
      expect(c.read(homeRowsShownProvider), 0);
      async.elapse(const Duration(milliseconds: 500));
      expect(c.read(homeRowsShownProvider), 0, reason: 'the art first');
      c.read(homeRowsShownProvider.notifier).artShown();
      expect(c.read(homeRowsShownProvider), 1);
      async.elapse(const Duration(milliseconds: 200));
      expect(c.read(homeRowsShownProvider), 3);
      c.read(homeRowsShownProvider.notifier).artShown();
      expect(c.read(homeRowsShownProvider), 3, reason: 'told twice: no restart');
      async.elapse(const Duration(seconds: 10));
      expect(c.read(homeRowsShownProvider), HomeRowsShown.all);
      expect(async.pendingTimers, isEmpty, reason: 'the timers stop once every row shows');
      sub.close();
      c.dispose();
    });
  });

  test('art that never comes holds the rows back only so long', () {
    fakeAsync((async) {
      final c = container();
      final sub = c.listen(homeRowsShownProvider, (_, _) {});
      async.elapse(step * HomeRowsShown.waitSteps - const Duration(milliseconds: 1));
      expect(c.read(homeRowsShownProvider), 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(c.read(homeRowsShownProvider), 1);
      sub.close();
      c.dispose();
    });
  });

  test('a zero step shows every row at once', () {
    final c = ProviderContainer(overrides: [homeRevealStepProvider.overrideWithValue(Duration.zero)]);
    addTearDown(c.dispose);
    expect(c.read(homeRowsShownProvider), HomeRowsShown.all);
  });
}
