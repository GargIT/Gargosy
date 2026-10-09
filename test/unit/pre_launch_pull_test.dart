import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/save_strategy.dart';
import 'package:gargosy/play/pre_launch_pull.dart';

void main() {
  test('a pull that comes too late writes nothing (the guard says so)', () async {
    final release = Completer<void>();
    bool? tooLateWhenWriting;
    await pullBeforeLaunch(
      backUp: () async {},
      pull: () async {
        await release.future;
        tooLateWhenWriting = SaveRestoreGuard.restoreTooLate;
        return !tooLateWhenWriting!;
      },
      markSynced: () async => fail('a late pull is not marked synced'),
      mustFinish: () async => true,
      wait: const Duration(milliseconds: 20),
    );
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tooLateWhenWriting, isTrue);
  });

  test('a pull or backup that throws does not stop the launch, and its reason is told', () async {
    final told = <String>[];
    await pullBeforeLaunch(
      backUp: () async => throw StateError('disk full'),
      pull: () async => true,
      markSynced: () async {},
      mustFinish: () async => true,
      onProblem: told.add,
    );
    await pullBeforeLaunch(
      backUp: () async {},
      pull: () async => throw SaveSyncNotPossibleException('card full'),
      markSynced: () async {},
      mustFinish: () async => true,
      onProblem: told.add,
    );
    expect(told, ['card full']);
  });

  test('a pull that put the save in place is marked synced; one that did nothing is not', () async {
    var marked = 0;
    await pullBeforeLaunch(backUp: () async {}, pull: () async => true, markSynced: () async => marked++, mustFinish: () async => true);
    await pullBeforeLaunch(backUp: () async {}, pull: () async => false, markSynced: () async => marked++, mustFinish: () async => true);
    expect(marked, 1);
  });

  test('without a shared save file the launch does not wait for the pull', () async {
    final release = Completer<bool>();
    await pullBeforeLaunch(backUp: () async {}, pull: () => release.future, markSynced: () async {}, mustFinish: () async => false)
        .timeout(const Duration(seconds: 1));
    release.complete(false);
  });
}
