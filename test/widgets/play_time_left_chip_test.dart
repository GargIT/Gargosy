import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/play/play_limits.dart';
import 'package:gargosy/play/play_time_left.dart';
import 'package:gargosy/profiles/play_limit.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/widgets/play_time_left.dart';

import '../helpers/widget_env.dart';

void main() {
  final now = DateTime(2026, 11, 3, 16);

  Future<void> pump(WidgetTester tester, PlayLimit limit, Duration used) async {
    await tester.pumpWidget(
      testApp(
        const Center(child: PlayTimeLeftChip()),
        overrides: [
          playLimitProvider.overrideWithValue(limit),
          playClockProvider.overrideWithValue(() => now),
          playTimeCounterProvider.overrideWithValue(
            () async => PlayCheck(const PlayAllowed(null), used: used, at: now),
          ),
        ],
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the time left under a limit', (tester) async {
    await pump(tester, const PlayLimit(minutesPerDay: 60), const Duration(minutes: 18));
    expect(find.text('42 min left'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('used up: when play is back, in red', (tester) async {
    await pump(tester, const PlayLimit(minutesPerDay: 30), const Duration(minutes: 30));
    expect(find.text('Back at 00:00 tomorrow'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('nothing without a limit', (tester) async {
    await pump(tester, PlayLimit.off, Duration.zero);
    expect(find.byKey(const ValueKey('play-time-left')), findsNothing);
  });
}
