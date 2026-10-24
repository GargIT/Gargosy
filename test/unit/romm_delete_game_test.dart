import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';

import '../helpers/fake_dio_adapter.dart';

void main() {
  RommService romm(FakeDioAdapter a) => RommService(
    RomMConfig(baseUrl: 'https://romm.example', username: '', password: '', apiKey: 't'),
    dio: fakeDio(a),
    skipConnectivityCheck: true,
  );

  group('canDeleteGames', () {
    test("RomM 5.4: an admin, or the rom.delete action; else not", () async {
      Future<bool> with_(Object body) => romm(FakeDioAdapter((r) => (status: 200, body: body))).canDeleteGames();
      expect(await with_({'is_admin': true, 'grants': []}), isTrue);
      expect(
        await with_({
          'is_admin': false,
          'grants': [
            {'action': 'rom.write'},
            {'action': 'rom.delete'},
          ],
        }),
        isTrue,
      );
      expect(
        await with_({
          'is_admin': false,
          'grants': [
            {'action': 'rom.read'},
          ],
        }),
        isFalse,
      );
    });

    test("an older RomM without /api/permissions/me: an admin's or editor's role", () async {
      Future<bool> role(String r) => romm(
        FakeDioAdapter(
          (q) =>
              q.path.endsWith('/permissions/me') ? (status: 404, body: {}) : (status: 200, body: {'id': 1, 'role': r}),
        ),
      ).canDeleteGames();
      expect(await role('admin'), isTrue);
      expect(await role('editor'), isTrue);
      expect(await role('viewer'), isFalse);
    });

    test('offline or refused: false', () async {
      expect(await romm(FakeDioAdapter((_) => (status: -1, body: null))).canDeleteGames(), isFalse);
      expect(await romm(FakeDioAdapter((_) => (status: 403, body: {}))).canDeleteGames(), isFalse);
    });
  });

  group('deleteGame', () {
    test('asks RomM to delete the game, its file only when asked', () async {
      final a = FakeDioAdapter((_) => (status: 200, body: {'successful_items': 1, 'failed_items': 0, 'errors': []}));
      expect(await romm(a).deleteGame(42, fromServerDisk: true), RomDeleteResult.deleted);
      expect((a.requests.last.method, a.requests.last.path), ('POST', '/api/roms/delete'));
      expect(a.requests.last.data, {
        'roms': [42],
        'delete_from_fs': [42],
      });
      await romm(a).deleteGame(42, fromServerDisk: false);
      expect(a.requests.last.data, {
        'roms': [42],
        'delete_from_fs': <int>[],
      });
    });

    test('refused (403) is notAllowed; a failed item or no answer is failed', () async {
      expect(
        await romm(FakeDioAdapter((_) => (status: 403, body: {'detail': 'Forbidden'})))
            .deleteGame(1, fromServerDisk: true),
        RomDeleteResult.notAllowed,
      );
      expect(
        await romm(
          FakeDioAdapter(
            (_) => (
              status: 200,
              body: {
                'successful_items': 0,
                'failed_items': 1,
                'errors': ['ROM with ID 1 not found'],
              },
            ),
          ),
        ).deleteGame(1, fromServerDisk: true),
        RomDeleteResult.failed,
      );
      expect(
        await romm(FakeDioAdapter((_) => (status: -1, body: null))).deleteGame(1, fromServerDisk: true),
        RomDeleteResult.failed,
      );
    });
  });
}
