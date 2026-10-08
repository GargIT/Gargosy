import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/pages/platforms_page.dart';
import 'package:gargosy/ui/screens/gallery_screen.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/widget_env.dart';

void main() {
  testWidgets('lists platforms with their counts; A opens the platform\'s gallery', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const PlatformsPage(), overrides: [
      platformsProvider.overrideWith((ref) async => [
            Platform.fromJson({'id': 1, 'name': 'PlayStation 2', 'slug': 'ps2', 'fs_slug': 'ps2', 'display_name': 'PlayStation 2', 'rom_count': 1335}),
            Platform.fromJson({'id': 2, 'name': 'Dreamcast', 'slug': 'dc', 'fs_slug': 'dc', 'display_name': 'Dreamcast', 'rom_count': 91}),
          ]),
      libraryApiProvider.overrideWithValue(FakeLibraryApi(const [])),
      favouriteIdsProvider.overrideWithValue(const {}),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('PlayStation 2'), findsOneWidget);
    expect(find.text('1335 games'), findsOneWidget);
    await press(tester, GameAction.confirm);
    expect(find.byType(GalleryScreen), findsOneWidget);
  });

  testWidgets('shows the error with retry', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const PlatformsPage(), overrides: [
      platformsProvider.overrideWith((ref) async => throw Exception('SocketException: connection refused')),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });
}
