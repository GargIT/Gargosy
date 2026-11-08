import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_admin.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/library/library_scan.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/game/fix_match_dialog.dart';
import 'package:gargosy/ui/screens/settings/romm_library_section.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  RommService romm(FakeDioAdapter a) => RommService(
    RomMConfig(baseUrl: 'https://romm.example', username: '', password: '', apiKey: 't'),
    dio: fakeDio(a),
    skipConnectivityCheck: true,
  );

  /// Lets the fake RomM answer: its replies come through real futures.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Settings → RomM library', () {
    testWidgets("without RomM's permission it says so, with no buttons", (tester) async {
      await setDesktopSize(tester);
      await tester.pumpWidget(
        testApp(
          const RommLibrarySection(),
          overrides: [
            rommRightsProvider.overrideWith((ref) async => RommRights.none),
            rommOfflineProvider.overrideWithValue(false),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('may not scan'), findsOneWidget);
      expect(find.byKey(const Key('scan-quick')), findsNothing);
    });

    testWidgets("Quick scan starts RomM's scan and shows how it goes", (tester) async {
      final a = FakeDioAdapter((r) {
        if (r.method == 'POST') return (status: 202, body: {'task_id': 'job'});
        return (
          status: 200,
          body: {
            'status': 'started',
            'meta': {
              'scan_stats': {'total_roms': 10, 'scanned_roms': 4, 'new_roms': 2},
            },
          },
        );
      });
      final service = romm(a);
      await setDesktopSize(tester);
      await tester.pumpWidget(
        testApp(
          const RommLibrarySection(),
          overrides: [
            rommRightsProvider.overrideWith((ref) async => const RommRights(scan: true)),
            rommOfflineProvider.overrideWithValue(false),
            rommServiceProvider.overrideWithValue(service),
            libraryScanProvider.overrideWith(
              (ref) => LibraryScanNotifier(service, () {}, every: const Duration(hours: 1)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-quick')));
      await settle(tester, () => a.requests.length >= 2);
      expect(a.requests.first.data, {'type': 'quick'});
      expect(tester.widget<Text>(find.byKey(const Key('scan-line'))).data, 'Scanned 4 of 10 games · 2 new');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  testWidgets("Fix match: RomM's finds by the file name, one picked and confirmed is set", (tester) async {
    final a = FakeDioAdapter((r) {
      if (r.path == '/api/search/roms') {
        return (
          status: 200,
          body: [
            {'name': 'Burnout 3: Takedown', 'igdb_id': 1234, 'summary': 'Crash.', 'platform_id': 1},
            {'name': 'Burnout Revenge', 'igdb_id': 5678, 'platform_id': 1},
          ],
        );
      }
      return (status: 200, body: {'id': 7564});
    });
    final game = Game.fromJson(gameJson(7564, 'Burnout', fsName: 'Burnout 3 (USA).chd'));
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(
        Consumer(
          builder: (context, ref, _) =>
              TextButton(onPressed: () => fixMatch(context, ref, game), child: const Text('fix')),
        ),
        overrides: [rommServiceProvider.overrideWithValue(romm(a))],
      ),
    );
    await tester.tap(find.text('fix'));
    await settle(tester, () => find.text('Burnout Revenge').evaluate().isNotEmpty);
    expect(a.requests.single.queryParameters, {'rom_id': '7564', 'search_by': 'name'});
    expect(find.text('Found by its file name.'), findsOneWidget);
    expect(find.text('Search for another name…'), findsOneWidget);

    await tester.tap(find.text('Burnout 3: Takedown'));
    await tester.pumpAndSettle();
    expect(find.text('Match Burnout with Burnout 3: Takedown?'), findsOneWidget);
    await tester.tap(find.text('Match'));
    await settle(tester, () => a.requests.length >= 2);
    expect(a.requests.last.method, 'PUT');
    expect(a.requests.last.path, '/api/roms/7564');
    expect(find.text('Matched with Burnout 3: Takedown.'), findsOneWidget);
  });
}
