import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/notifications.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/notification_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/shell/shell_notices.dart';

import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester, {bool on = true}) async {
    await setDesktopSize(tester);
    final prefs = MemoryPrefs();
    await prefs.setBool(NotificationSettings.prefKey, on);
    await tester.pumpWidget(
      testApp(
        const ShellNotices(child: Text('Home')),
        overrides: [
          appPreferencesProvider.overrideWithValue(prefs),
          rommOfflineProvider.overrideWithValue(true),
          shareWatchProvider.overrideWithValue(null),
        ],
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.text('Home')));
  }

  testWidgets('said one at a time, the next after the first has shown', (tester) async {
    final c = await pump(tester);
    c.read(noticesProvider.notifier)
      ..post(const Notice('Okami is downloaded.'))
      ..post(const Notice('Uploaded 1 save that was waiting.'));
    await tester.pump();
    expect(find.text('Okami is downloaded.'), findsOneWidget);
    expect(find.text('Uploaded 1 save that was waiting.'), findsNothing);
    await tester.pump(ShellNotices.spacing);
    await tester.pumpAndSettle();
    expect(find.text('Uploaded 1 save that was waiting.'), findsOneWidget);
    await tester.pump(ShellNotices.spacing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('never while a game runs: kept, and said once it has ended', (tester) async {
    final c = await pump(tester);
    c.read(playControllerProvider.notifier).state = const PlayState(runningGameId: '1');
    c.read(noticesProvider.notifier).post(const Notice('Anna shared a save of Okami.'));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Anna shared a save of Okami.'), findsNothing);
    expect(c.read(noticesProvider), hasLength(1));

    c.read(playControllerProvider.notifier).state = const PlayState();
    await tester.pump();
    await tester.pump();
    expect(find.text('Anna shared a save of Okami.'), findsOneWidget);
    await tester.pump(ShellNotices.spacing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('off: nothing is kept or said', (tester) async {
    final c = await pump(tester, on: false);
    c.read(noticesProvider.notifier).post(const Notice('Okami is downloaded.'));
    await tester.pump();
    expect(find.text('Okami is downloaded.'), findsNothing);
    expect(c.read(noticesProvider), isEmpty);
  });
}
