import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/widgets/platform_logo.dart';

import '../helpers/widget_env.dart';

void main() {
  test('badge labels', () {
    expect(badgeLabel('ps2'), 'PS2');
    expect(badgeLabel('neogeoaes'), 'NEOG');
    expect(badgeLabel('3ds'), '3DS');
    expect(badgeLabel('sega-cd'), 'SEGA');
  });

  testWidgets('without a server the badge shows', (tester) async {
    await tester.pumpWidget(testApp(const Center(child: PlatformLogo(slug: 'ps2'))));
    expect(find.byKey(const ValueKey('platform-badge')), findsOneWidget);
    expect(find.text('PS2'), findsOneWidget);
  });

  testWidgets("an icon RomM doesn't have falls back to the badge", (tester) async {
    await tester.pumpWidget(
      testApp(
        const Center(child: PlatformLogo(slug: 'my-homebrew')),
        overrides: [
          platformLogoUrlProvider.overrideWithValue((slug) => 'https://romm.test/assets/platforms/$slug.svg'),
          platformLogoBuilderProvider.overrideWithValue((url, size, fallback) => fallback), // as a 404 does
        ],
      ),
    );
    expect(find.byKey(const ValueKey('platform-badge')), findsOneWidget);
  });

  testWidgets("RomM's icon is asked for by slug", (tester) async {
    final asked = <String>[];
    await tester.pumpWidget(
      testApp(
        const Center(child: PlatformLogo(slug: 'ngc')),
        overrides: [
          platformLogoUrlProvider.overrideWithValue((slug) => 'https://romm.test/assets/platforms/$slug.svg'),
          platformLogoBuilderProvider.overrideWithValue((url, size, fallback) {
            asked.add(url);
            return SizedBox(key: const ValueKey('svg'), width: size, height: size);
          }),
        ],
      ),
    );
    expect(asked, ['https://romm.test/assets/platforms/ngc.svg']);
    expect(find.byKey(const ValueKey('svg')), findsOneWidget);
  });
}
