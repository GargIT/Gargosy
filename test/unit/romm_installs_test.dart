import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/install_request.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';

/// RomM's device installs as Gargosy asks for them (#288).
void main() {
  late RommService romm;
  final sent = <RequestOptions>[];
  var status = 200;
  Object? body;

  setUp(() {
    sent.clear();
    status = 200;
    body = null;
    final dio = Dio(BaseOptions(baseUrl: 'https://romm.example.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          sent.add(o);
          final ok = o.validateStatus(status);
          final response = Response(requestOptions: o, statusCode: status, data: body);
          if (ok) {
            h.resolve(response);
          } else {
            h.reject(DioException.badResponse(statusCode: status, requestOptions: o, response: response));
          }
        },
      ),
    );
    romm = RommService(
      RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
      dio: dio,
    );
  });

  test('a claim takes the requests RomM gives for this device', () async {
    body = [
      {'id': 'r1', 'rom_id': 7, 'created_at': '2026-11-06T12:00:00Z'},
      {'id': 'r2', 'rom_id': 'not a number'},
    ];
    final claim = await romm.claimInstalls('dev-1');
    expect(sent.single.method, 'POST');
    expect(sent.single.path, '/api/devices/dev-1/installs/claim');
    expect((claim as InstallsTaken).requests.map((r) => r.id), ['r1']);
  });

  test('a login not bound to the device, and a RomM without installs, are told apart', () async {
    status = 403;
    expect(await romm.claimInstalls('dev-1'), isA<InstallsNotBound>());
    status = 404;
    expect(await romm.claimInstalls('dev-1'), isA<InstallsOff>());
  });

  test('a report sends the outcome and a reason RomM keeps', () async {
    await romm.reportInstall('dev-1', 'r1', InstallOutcome.failed, reason: 'x' * 600);
    expect(sent.single.method, 'PUT');
    expect(sent.single.path, '/api/devices/dev-1/installs/r1');
    final data = sent.single.data as Map;
    expect(data['status'], 'failed');
    expect((data['reason'] as String).length, installReasonMax);
  });

  test('a done report sends no reason', () async {
    await romm.reportInstall('dev-1', 'r1', InstallOutcome.alreadyInstalled);
    expect(sent.single.data, {'status': 'already_installed'});
  });

  test('a request RomM no longer has, or has ended, counts as told', () async {
    status = 409;
    await romm.reportInstall('dev-1', 'r1', InstallOutcome.done);
    status = 404;
    await romm.reportInstall('dev-1', 'r1', InstallOutcome.done);
  });

  test('a report RomM refuses otherwise throws, so it is made again', () async {
    status = 400;
    await expectLater(romm.reportInstall('dev-1', 'r1', InstallOutcome.done), throwsA(anything));
  });

  test('the device says whether it takes games sent from RomM', () async {
    expect(await romm.setRemoteInstall('dev-1', true), isTrue);
    expect(sent.single.method, 'PUT');
    expect(sent.single.path, '/api/devices/dev-1');
    expect(sent.single.data, {
      'capabilities': {'remote_install': true},
    });
  });

  test('registration says whether RomM made the device now or gave back one it had (#293)', () async {
    status = 201;
    body = {'device_id': 'd1'};
    expect(await romm.registerDevice(name: 'PC', platform: 'Windows', allowDuplicate: true), (id: 'd1', created: true));
    status = 200;
    expect(await romm.registerDevice(name: 'PC', platform: 'Windows', allowDuplicate: true), (
      id: 'd1',
      created: false,
    ));
  });
}
