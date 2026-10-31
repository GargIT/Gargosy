// Issue #16, from the review of #19: a check for an older channel never
// lands after a switch, and a check that throws doesn't leave "Checking…".
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/providers/retry.dart';
import 'package:gargosy/providers/update_providers.dart';
import 'package:gargosy/update/update_checker.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../helpers/profile_test_env.dart';

/// A checker whose answers the test hands out one by one.
class _Checker extends UpdateChecker {
  _Checker() : super(dio: Dio(), prefs: MemoryPrefs(), installed: Version(0, 1, 0));
  final pending = <Completer<UpdateCheck?>>[];

  @override
  Future<UpdateCheck?> check({bool force = false}) {
    final c = Completer<UpdateCheck?>();
    pending.add(c);
    return c.future;
  }
}

void main() {
  late _Checker checker;
  late ProviderContainer container;
  setUp(() {
    checker = _Checker();
    container = ProviderContainer(retry: noRetry, overrides: [updateCheckerProvider.overrideWithValue(checker)]);
  });
  tearDown(() => container.dispose());

  UpdateNotifier notifier() => container.read(updateStateProvider.notifier);
  UpdateState state() => container.read(updateStateProvider);

  test("a Preview answer that comes after the switch to Latest isn't shown", () async {
    await checker.setChannel(UpdateChannel.preview);
    final first = notifier().checkNow();
    final switched = notifier().setChannel(UpdateChannel.latest);
    await Future<void>.delayed(Duration.zero);
    expect(checker.pending, hasLength(2), reason: 'the switch checks again at once');
    checker.pending[1].complete(const UpToDate());
    await switched;
    checker.pending[0].complete(const CheckFailed('preview: an answer for the old channel'));
    await first;
    expect(state().result, isA<UpToDate>());
    expect(state().checking, isFalse);
  });

  test('a check that throws ends checking: Check now works again', () async {
    final first = notifier().checkNow();
    checker.pending.single.completeError(const FormatException('odd JSON'));
    await first;
    expect(state().checking, isFalse);
    final again = notifier().checkNow();
    expect(checker.pending, hasLength(2));
    checker.pending.last.complete(const UpToDate());
    await again;
    expect(state().result, isA<UpToDate>());
  });
}
