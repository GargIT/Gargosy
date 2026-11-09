import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';

import '../helpers/fake_dio_adapter.dart';

/// RomM 5.4 filters `/api/roms` by `platform_ids` and ignores `platform_id`,
/// listing every game (found by the e2e tests, #242).
void main() {
  RommService romm(FakeDioAdapter a) => RommService(
    RomMConfig(baseUrl: 'https://romm.example', username: '', password: '', apiKey: 't'),
    dio: fakeDio(a),
    skipConnectivityCheck: true,
  );

  final page = (status: 200, body: {'items': <Object>[], 'total': 0});

  test("a platform's games are asked for by platform_ids", () async {
    final a = FakeDioAdapter((_) => page);
    final service = romm(a);
    await service.getGames('4');
    await service.getAllGames(platformId: '4');
    await service.searchRoms(search: 'x', platformId: '4');
    for (final r in a.requests) {
      expect(r.queryParameters['platform_ids'], [4], reason: '${r.uri}');
      expect(r.queryParameters.containsKey('platform_id'), isFalse, reason: '${r.uri}');
    }
    expect(a.requests, hasLength(3));
  });
}
