import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_collection_edits.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';

import '../helpers/fake_dio_adapter.dart';

void main() {
  Map<String, Object?> collection(int id, String name, {List<int> roms = const [], bool shared = false}) => {
    'id': id,
    'name': name,
    'rom_ids': roms,
    'rom_count': roms.length,
    'is_public': shared,
    'is_favorite': false,
    'user_id': 7,
  };

  RommCollectionEdits edits(FakeDioAdapter a) =>
      RommCollectionEdits(fakeDio(a), () => Options(headers: {'Authorization': 'Bearer t'}));

  test('a game in and out changes only that game', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: collection(3, 'RPGs', roms: [9])));
    final c = await edits(a).setIn(3, '9', true);
    expect(c.romIds, {9});
    await edits(a).setIn(3, '9', false);
    expect(a.requests.map((r) => '${r.method} ${r.path}'), [
      'POST /api/collections/3/roms',
      'DELETE /api/collections/3/roms',
    ]);
    expect(a.requests.first.data, {
      'rom_ids': [9],
    });
  });

  test('a new collection, shared, with the game in it', () async {
    final a = FakeDioAdapter(
      (r) => (status: 200, body: collection(4, 'Couch', roms: r.path.endsWith('/roms') ? [9] : const [])),
    );
    final c = await edits(a).create('Couch', shared: true, gameId: '9');
    expect(c.romIds, {9});
    expect(a.requests.first.path, '/api/collections');
    expect(a.requests.first.queryParameters, {'is_favorite': false, 'is_public': true});
    expect(Map.fromEntries((a.requests.first.data as FormData).fields)['name'], 'Couch');
    expect(a.requests.last.path, '/api/collections/4/roms');
  });

  test('rename keeps the games; share and delete', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: collection(3, 'Old', roms: [1, 2])));
    await edits(a).rename(const RommCollection(id: 3, name: 'Old', romIds: {1, 2}), 'New');
    final form = (a.requests.single.data as FormData).fields;
    expect(a.requests.single.method, 'PUT');
    expect(Map.fromEntries(form)['name'], 'New');
    expect(jsonDecode(form.firstWhere((f) => f.key == 'rom_ids').value), [1, 2]);
    await edits(a).setShared(3, true);
    expect(a.requests.last.path, '/api/collections/3/visibility');
    expect(a.requests.last.data, {'is_public': true});
    await edits(a).delete(3);
    expect('${a.requests.last.method} ${a.requests.last.path}', 'DELETE /api/collections/3');
  });

  test("RomM's reason is said; a refusal without one says who may", () async {
    final taken = FakeDioAdapter((r) => (status: 400, body: {'detail': 'Collection Couch already exists'}));
    await expectLater(
      edits(taken).create('Couch'),
      throwsA(isA<CollectionEditException>().having((e) => '$e', 'message', 'Collection Couch already exists')),
    );
    final forbidden = FakeDioAdapter((r) => (status: 403, body: {}));
    await expectLater(
      edits(forbidden).delete(3),
      throwsA(isA<CollectionEditException>().having((e) => '$e', 'message', contains('owner'))),
    );
  });
}
