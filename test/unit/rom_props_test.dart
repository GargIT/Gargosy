import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';

import '../helpers/fake_dio_adapter.dart';

void main() {
  test("status, rating and completion go as RomM 5.4's body and as the older `data`", () async {
    final adapter = FakeDioAdapter((r) => (status: 200, body: <String, dynamic>{}));
    final dio = Dio(BaseOptions(baseUrl: 'https://romm.example.com'))..httpClientAdapter = adapter;
    final romm = RommService(
      RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 't'),
      dio: dio,
    );

    expect(await romm.updateRomProps('42', status: 'finished', rating: 8, completion: 60), isTrue);

    final request = adapter.requests.single;
    expect(request.method, 'PUT');
    expect(request.path, '/api/roms/42/props');
    final body = request.data as Map<String, dynamic>;
    expect(body['status'], 'finished');
    expect(body['rating'], 8);
    expect(body['completion'], 60);
    expect(body['data'], {'status': 'finished', 'rating': 8, 'completion': 60});
  });
}
