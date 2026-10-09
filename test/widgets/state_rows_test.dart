import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/resume_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/ui/screens/play/state_rows.dart';

import '../helpers/widget_env.dart';

void main() {
  testWidgets('a state from another emulator build says so in the list (the resume then loads it as seen)', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(StateRows(
      states: [
        ResumeEntry(
          emulatorId: 'duckstation',
          emulatorName: 'DuckStation',
          fileName: 'auto.sav',
          slot: const AutoStateSlot(),
          savedAt: DateTime(2026, 10, 1),
          where: ResumeWhere.thisPc,
          emulatorVersion: '0.1-6000',
          installedVersion: '0.1-7000',
          compat: StateCompat.mismatch,
        ),
      ],
      chosen: null,
      loading: false,
      onChoose: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Made with DuckStation 0.1-6000; you have 0.1-7000'), findsOneWidget);
  });
}
