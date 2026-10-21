// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/romm/romm_state.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// A save list that couldn't be read must not look like "no saves".
void main() {
  const baseUrl = 'https://romm.example.com';
  late RommService service;
  late DioAdapter adapter;

  setUp(() {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    adapter = DioAdapter(dio: dio);
    service = RommService(
      RomMConfig(baseUrl: baseUrl, username: '', password: '', apiKey: 'key'),
      dio: dio,
      skipConnectivityCheck: true,
    );
  });

  test('a listed game gives its saves, newest first', () async {
    adapter.onGet(
      '/api/saves',
      (server) => server.reply(200, {
        'items': [
          {'id': 1, 'file_name': 'old.srm', 'updated_at': '2026-09-01T00:00:00Z'},
          {'id': 2, 'file_name': 'new.srm', 'updated_at': '2026-10-01T00:00:00Z'},
        ],
      }),
      queryParameters: {'rom_id': '7'},
    );

    final saves = await service.getSavesListOrNull('7');

    expect(saves!.map((s) => s['file_name']), ['new.srm', 'old.srm']);
  });

  test('a game without saves gives an empty list', () async {
    adapter.onGet('/api/saves', (server) => server.reply(200, {'items': []}), queryParameters: {'rom_id': '7'});
    expect(await service.getSavesListOrNull('7'), isEmpty);
  });

  test('a server error gives null, not an empty list', () async {
    adapter.onGet('/api/saves', (server) => server.reply(500, {'detail': 'boom'}), queryParameters: {'rom_id': '7'});
    expect(await service.getSavesListOrNull('7'), isNull);
  });

  test('a refused request gives null', () async {
    adapter.onGet('/api/saves', (server) => server.reply(401, {'detail': 'no'}), queryParameters: {'rom_id': '7'});
    expect(await service.getSavesListOrNull('7'), isNull);
  });

  test("other players' public saves come with the game, the profile's own left out (#92)", () async {
    adapter.onGet(
      '/api/roms/7',
      (server) => server.reply(200, {
        'id': 7,
        'all_user_saves': [
          {'id': 1, 'file_name': 'mine.ps2', 'user_id': 3, 'username': 'me'},
          {'id': 2, 'file_name': 'maja.ps2', 'user_id': 7, 'username': 'maja', 'is_public': true},
        ],
      }),
    );
    final shared = await service.getSharedSavesOrNull('7', exceptUserId: 3);
    expect(shared!.map((s) => s['file_name']), ['maja.ps2']);
  });

  test("a game that can't be read gives null shared saves", () async {
    adapter.onGet('/api/roms/7', (server) => server.reply(500, {'detail': 'boom'}));
    expect(await service.getSharedSavesOrNull('7', exceptUserId: 3), isNull);
  });

  test("Share (#92): a save's or state's visibility is set with is_public; a refusal is false", () async {
    adapter.onPut('/api/saves/5/visibility', (server) => server.reply(200, {'id': 5}), data: {'is_public': true});
    adapter.onPut('/api/states/6/visibility', (server) => server.reply(200, {'id': 6}), data: {'is_public': false});
    adapter.onPut(
      '/api/saves/7/visibility',
      (server) => server.reply(404, {'detail': 'no'}),
      data: {'is_public': true},
    );
    expect(await service.setSaveShared(5, true), isTrue);
    expect(await service.setStateShared(6, false), isTrue);
    expect(await service.setSaveShared(7, true), isFalse);
  });

  test('a state on RomM says whether it is shared', () {
    expect(RommState.fromJson({'id': 1, 'file_name': 'a', 'is_public': true}).isPublic, isTrue);
    expect(RommState.fromJson({'id': 1, 'file_name': 'a'}).isPublic, isFalse);
  });
}
