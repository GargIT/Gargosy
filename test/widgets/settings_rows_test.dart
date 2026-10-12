import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/ui/screens/settings/settings_rows.dart';
import 'package:gargosy/ui/widgets/g_focusable.dart';
import 'package:gargosy/ui/widgets/profile_badge.dart';

import '../helpers/widget_env.dart';

void main() {
  testWidgets('a card shows its title upper-case, with the badge on the right', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const SettingsCard(
      title: 'RetroAchievements',
      icon: Icons.emoji_events,
      trailing: SettingsBadge('Connected as @anna'),
      children: [Text('row')],
    )));
    expect(find.text('RETROACHIEVEMENTS'), findsOneWidget);
    final title = tester.getRect(find.text('RETROACHIEVEMENTS'));
    final badge = tester.getRect(find.text('Connected as @anna'));
    expect(badge.left, greaterThan(title.right));
    expect(badge.center.dy, closeTo(title.center.dy, 2));
  });

  testWidgets('a field with an action takes focus and A runs it; a read-only one is passed by', (tester) async {
    await setDesktopSize(tester);
    var renamed = 0;
    await tester.pumpWidget(testApp(Column(children: [
      SettingsField(label: 'Name', value: 'Anna', action: 'Rename', autofocus: true, onActivate: () => renamed++),
      const SettingsField(label: 'RomM account', value: 'anna on r'),
    ])));
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.text('Anna'), matching: find.byType(GFocusable)), findsOneWidget);
    expect(find.ancestor(of: find.text('anna on r'), matching: find.byType(GFocusable)), findsNothing);
    await press(tester, GameAction.confirm);
    expect(renamed, 1);
    // Clicking the label works too.
    await tester.tap(find.text('Name'));
    expect(renamed, 2);
  });

  testWidgets('a toggle flips with A', (tester) async {
    await setDesktopSize(tester);
    bool? got;
    await tester.pumpWidget(testApp(SettingsToggle(label: 'Hardcore mode', on: false, onChanged: (v) => got = v)));
    await tester.tap(find.text('Hardcore mode'));
    expect(got, isTrue);
  });

  testWidgets('the avatar shows the initial when there is no picture', (tester) async {
    await setDesktopSize(tester);
    final p = Profile(
        id: 'a', name: 'anna', colorIndex: 1, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna', createdAt: DateTime(2026));
    await tester.pumpWidget(testApp(ProfileAvatar(profile: p, size: 48)));
    expect(find.text('A'), findsOneWidget);
    expect(find.byType(GFocusable), findsNothing);
  });
}
