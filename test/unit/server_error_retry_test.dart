import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/server_error_retry.dart';
import 'package:gargosy/ui/widgets/error_retry.dart';

import '../helpers/fake_dio_adapter.dart';

void main() {
  Dio dio(List<int> statuses) {
    var i = 0;
    final d = Dio(BaseOptions(baseUrl: 'https://romm'));
    d.httpClientAdapter = FakeDioAdapter((r) => (status: statuses[i < statuses.length ? i++ : statuses.length - 1], body: {'ok': true}));
    d.interceptors.add(ServerErrorRetry(d, delays: const [Duration.zero, Duration.zero]));
    return d;
  }

  test('a read that RomM answers with a server error once is asked again, and works', () async {
    final d = dio([500, 200]);
    final r = await d.get('/api/roms');
    expect(r.statusCode, 200);
    expect((d.httpClientAdapter as FakeDioAdapter).requests, hasLength(2));
  });

  test('it gives up after two retries, and never repeats a change (POST)', () async {
    final d = dio([500, 500, 500, 500]);
    await expectLater(d.get('/api/roms'), throwsA(isA<DioException>()));
    expect((d.httpClientAdapter as FakeDioAdapter).requests, hasLength(3));
    final p = dio([500, 200]);
    await expectLater(p.post('/api/collections'), throwsA(isA<DioException>()));
    expect((p.httpClientAdapter as FakeDioAdapter).requests, hasLength(1));
  });

  test("a server error says which request, in words", () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/api/roms', baseUrl: 'https://romm'),
      response: Response(requestOptions: RequestOptions(path: '/api/roms'), statusCode: 500),
      type: DioExceptionType.badResponse,
    );
    expect(describeLoadError(e), 'RomM had a problem answering (error 500 for /api/roms). Try again in a moment.');
  });
}
