import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  test("a capabilities check that failed (RomM down at profile open) is asked again, not kept as 'legacy'", () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://romm.example.com'));
    final adapter = DioAdapter(dio: dio);
    final romm = RommService(
      RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', token: 't'),
      dio: dio,
      skipConnectivityCheck: true,
    );
    adapter.onGet('/api/heartbeat', (server) => server.reply(503, {'detail': 'down'}));
    await romm.fetchCapabilities();
    adapter.onGet(
      '/api/heartbeat',
      (server) => server.reply(200, {
        'SYSTEM': {'VERSION': '4.9.0'},
      }),
    );
    expect((await romm.fetchCapabilities()).version, '4.9.0');
  });
}
